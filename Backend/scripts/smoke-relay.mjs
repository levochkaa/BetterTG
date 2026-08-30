import { createECDH, randomBytes, randomUUID } from 'node:crypto'
import ece from 'http_ece'
import Redis from 'ioredis'

const baseURL = process.env.SMOKE_BASE_URL ?? 'http://localhost:8080'
const jsonHeaders = { 'content-type': 'application/json' }

async function responseJSON(response, operation) {
    if (!response.ok) throw new Error(`${operation} failed with HTTP ${response.status}`)
    return response.json()
}

async function verifyEncoding(contentEncoding) {
    let installation
    try {
        installation = await responseJSON(
            await fetch(`${baseURL}/api/v1/installations`, {
                method: 'POST',
                headers: { ...jsonHeaders, 'idempotency-key': randomUUID() },
                body: JSON.stringify({
                    apnsToken: randomBytes(32).toString('hex'),
                    apnsEnvironment: 'sandbox',
                    appVersion: 'smoke',
                    osVersion: process.platform,
                }),
            }),
            'installation creation',
        )
        const authorization = { authorization: `Bearer ${installation.managementSecret}` }
        const subscription = await responseJSON(
            await fetch(
                `${baseURL}/api/v1/installations/${installation.installationId}/telegram-subscriptions`,
                { method: 'POST', headers: authorization },
            ),
            'subscription creation',
        )

        const endpoint = new URL(subscription.endpoint)
        const smokeOrigin = new URL(baseURL)
        endpoint.protocol = smokeOrigin.protocol
        endpoint.hostname = smokeOrigin.hostname
        endpoint.port = smokeOrigin.port

        const sender = createECDH('prime256v1')
        sender.generateKeys()
        const salt = contentEncoding === 'aesgcm' ? randomBytes(16) : undefined
        const ciphertext = ece.encrypt(
            Buffer.from(
                JSON.stringify({
                    data: {
                        loc_key: 'MESSAGE_TEXT',
                        loc_args: ['Smoke', `${contentEncoding} relay verified`],
                        user_id: 1,
                        custom: { from_id: 2, msg_id: contentEncoding === 'aesgcm' ? 4 : 3 },
                    },
                }),
            ),
            {
                version: contentEncoding,
                privateKey: sender,
                dh: Buffer.from(subscription.p256dhBase64url, 'base64url'),
                authSecret: Buffer.from(subscription.authBase64url, 'base64url'),
                salt,
            },
        )
        const headers = {
            'content-type': 'application/octet-stream',
            'content-encoding': contentEncoding,
            ttl: '60',
        }
        if (salt) {
            headers.encryption = `salt=${salt.toString('base64url')}`
            headers['crypto-key'] = `dh=${sender.getPublicKey().toString('base64url')}`
        }
        const pushRequest = { method: 'POST', headers, body: ciphertext }
        const first = await fetch(endpoint, pushRequest)
        const location = first.headers.get('location')
        if (first.status !== 201 || !location) {
            throw new Error(`${contentEncoding} ingress failed with HTTP ${first.status}`)
        }
        const duplicate = await fetch(endpoint, pushRequest)
        if (duplicate.status !== 201) {
            throw new Error(
                `${contentEncoding} deduplicated ingress failed with HTTP ${duplicate.status}`,
            )
        }

        const redisURL = process.env.SMOKE_REDIS_URL
        if (!redisURL) {
            await Bun.sleep(500)
            return
        }
        const digest = location.split('/').at(-1)
        const jobId = `${subscription.subscriptionId}-${digest}`
        const redis = new Redis(redisURL, { maxRetriesPerRequest: 2 })
        try {
            for (let attempt = 0; attempt < 50; attempt += 1) {
                const jobKey = `bull:telegram-web-push:${jobId}`
                if ((await redis.exists(jobKey)) === 0) return
                const failedReason = await redis.hget(jobKey, 'failedReason')
                if (failedReason) throw new Error('relay worker failed the smoke job')
                await Bun.sleep(100)
            }
            throw new Error('relay worker did not complete the smoke job')
        } finally {
            redis.disconnect()
        }
    } finally {
        if (installation) {
            await fetch(`${baseURL}/api/v1/installations/${installation.installationId}`, {
                method: 'DELETE',
                headers: { authorization: `Bearer ${installation.managementSecret}` },
            }).catch(() => undefined)
        }
    }
}

await verifyEncoding('aes128gcm')
await verifyEncoding('aesgcm')
console.log('Encrypted Web Push relay smoke passed for aes128gcm and aesgcm')

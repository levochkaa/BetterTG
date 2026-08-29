import { Injectable, Logger, type OnModuleDestroy } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import { createSigner } from 'fast-jwt'
import http2, { type ClientHttp2Session, type IncomingHttpHeaders } from 'node:http2'
import { readFileSync } from 'node:fs'

import type { Environment } from '@/config/environment'
import { MetricsService } from '@/observability/metrics.service'

import type { ApnsRequest, ApnsResult } from './apns.types'

const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000

interface ProviderCredentials {
    keyId: string
    signer: ((payload: Record<string, unknown>) => string) | null
    token: { value: string; createdAt: number } | null
}

const invalidTokenReasons = new Set([
    'BadDeviceToken',
    'DeviceTokenNotForTopic',
    'ExpiredToken',
    'Unregistered',
])

@Injectable()
export class ApnsClientService implements OnModuleDestroy {
    private readonly logger = new Logger(ApnsClientService.name)
    private readonly clients = new Map<string, ClientHttp2Session>()
    private readonly dryRun: boolean
    private readonly sandboxUrl: string
    private readonly productionUrl: string
    private readonly requestTimeoutMs: number
    private readonly teamId: string
    private readonly credentials: Record<ApnsRequest['environment'], ProviderCredentials>

    constructor(
        config: ConfigService<Environment, true>,
        private readonly metrics: MetricsService,
    ) {
        this.dryRun = config.get('APNS_DRY_RUN', { infer: true })
        this.sandboxUrl = config.get('APNS_SANDBOX_URL', { infer: true })
        this.productionUrl = config.get('APNS_PRODUCTION_URL', { infer: true })
        this.requestTimeoutMs = config.get('APNS_REQUEST_TIMEOUT_MS', { infer: true })
        this.teamId = config.get('APPLE_TEAM_ID', { infer: true })
        this.credentials = {
            sandbox: this.makeCredentials(
                config.get('APNS_SANDBOX_KEY_ID', { infer: true }),
                config.get('APNS_SANDBOX_AUTH_KEY', { infer: true }),
                config.get('APNS_SANDBOX_AUTH_KEY_FILE', { infer: true }),
            ),
            production: this.makeCredentials(
                config.get('APNS_PRODUCTION_KEY_ID', { infer: true }),
                config.get('APNS_PRODUCTION_AUTH_KEY', { infer: true }),
                config.get('APNS_PRODUCTION_AUTH_KEY_FILE', { infer: true }),
            ),
        }
    }

    onModuleDestroy(): void {
        for (const client of this.clients.values()) {
            if (!client.closed && !client.destroyed) client.close()
        }
        this.clients.clear()
    }

    async send(request: ApnsRequest): Promise<ApnsResult> {
        const payload = JSON.stringify(request.payload)
        if (Buffer.byteLength(payload) > 4096) {
            return { kind: 'permanent', reason: 'PayloadTooLarge' }
        }
        if (this.dryRun) {
            return { kind: 'success', status: 200 }
        }
        const credentials = this.credentials[request.environment]
        if (!credentials.signer || !credentials.keyId || !this.teamId) {
            return { kind: 'permanent', reason: 'MissingProviderCredentials' }
        }

        const authority = request.environment === 'sandbox' ? this.sandboxUrl : this.productionUrl
        const headers: http2.OutgoingHttpHeaders = {
            ':method': 'POST',
            ':path': `/3/device/${encodeURIComponent(request.deviceToken)}`,
            authorization: `bearer ${this.getProviderToken(credentials)}`,
            'apns-id': request.deliveryId,
            'apns-topic': request.topic,
            'apns-push-type': request.pushType,
            'apns-priority': request.priority,
            'apns-expiration': request.expiration,
        }
        if (request.collapseId) headers['apns-collapse-id'] = request.collapseId

        try {
            return await this.performRequest(authority, headers, payload, credentials)
        } catch {
            this.removeClient(authority)
            return { kind: 'retryable', reason: 'ConnectionError' }
        }
    }

    private performRequest(
        authority: string,
        headers: http2.OutgoingHttpHeaders,
        payload: string,
        credentials: ProviderCredentials,
    ): Promise<ApnsResult> {
        return new Promise((resolve) => {
            const client = this.client(authority)
            let settled = false
            let responseStatus: number | undefined
            let responseBody = ''

            const finish = (result: ApnsResult) => {
                if (settled) return
                settled = true
                resolve(result)
            }

            let stream: http2.ClientHttp2Stream
            try {
                stream = client.request(headers)
            } catch {
                finish({ kind: 'retryable', reason: 'ConnectionError' })
                return
            }

            stream.setEncoding('utf8')
            stream.on('response', (responseHeaders: IncomingHttpHeaders) => {
                responseStatus = Number(responseHeaders[':status'])
            })
            stream.on('data', (chunk: string) => {
                if (responseBody.length < 4096) responseBody += chunk
            })
            stream.on('error', () => finish({ kind: 'retryable', reason: 'StreamError' }))
            stream.on('end', () =>
                finish(this.classifyResponse(responseStatus, responseBody, credentials)),
            )
            stream.setTimeout(this.requestTimeoutMs, () => {
                stream.close()
                finish({ kind: 'retryable', reason: 'Timeout' })
            })
            stream.end(payload)
        })
    }

    private classifyResponse(
        status: number | undefined,
        body: string,
        credentials: ProviderCredentials,
    ): ApnsResult {
        if (status === 200) return { kind: 'success', status: 200 }
        const reason = this.parseReason(body)
        if (reason === 'ExpiredProviderToken') credentials.token = null
        if (
            status === 429 ||
            status === 500 ||
            status === 503 ||
            reason === 'TooManyRequests' ||
            reason === 'ExpiredProviderToken'
        ) {
            return { kind: 'retryable', status, reason }
        }
        if (status !== undefined && reason && invalidTokenReasons.has(reason)) {
            return { kind: 'invalid-token', status, reason }
        }
        return { kind: 'permanent', status, reason }
    }

    private client(authority: string): ClientHttp2Session {
        const existing = this.clients.get(authority)
        if (existing && !existing.closed && !existing.destroyed) return existing

        const client = http2.connect(authority)
        client.on('connect', () => {
            this.metrics.apnsConnectionEvents.add(1, { event: 'connect', authority })
            this.logger.log({ event: 'apns.connection.opened', authority })
        })
        client.on('goaway', () => {
            this.metrics.apnsConnectionEvents.add(1, { event: 'goaway', authority })
            this.removeClient(authority)
        })
        client.on('error', () => {
            this.metrics.apnsConnectionEvents.add(1, { event: 'error', authority })
            this.removeClient(authority)
        })
        client.on('close', () => {
            this.metrics.apnsConnectionEvents.add(1, { event: 'close', authority })
            this.clients.delete(authority)
        })
        this.clients.set(authority, client)
        return client
    }

    private removeClient(authority: string): void {
        const client = this.clients.get(authority)
        this.clients.delete(authority)
        if (client && !client.closed && !client.destroyed) client.close()
    }

    private getProviderToken(credentials: ProviderCredentials): string {
        if (credentials.token && Date.now() - credentials.token.createdAt < PROVIDER_TOKEN_TTL_MS) {
            return credentials.token.value
        }
        if (!credentials.signer) throw new Error('APNs signer is unavailable')
        const value = credentials.signer({
            iss: this.teamId,
            iat: Math.floor(Date.now() / 1000),
        })
        credentials.token = { value, createdAt: Date.now() }
        return value
    }

    private makeCredentials(
        keyId: string,
        authKeyValue: string,
        authKeyFile: string,
    ): ProviderCredentials {
        const value = authKeyValue || (authKeyFile ? readFileSync(authKeyFile, 'utf8') : '')
        const authKey = this.normalizeAuthKey(value)
        return {
            keyId,
            signer: authKey ? createSigner({ key: authKey, algorithm: 'ES256', kid: keyId }) : null,
            token: null,
        }
    }

    private parseReason(body: string): string | undefined {
        try {
            const parsed = JSON.parse(body) as { reason?: unknown }
            return typeof parsed.reason === 'string' ? parsed.reason : undefined
        } catch {
            return undefined
        }
    }

    private normalizeAuthKey(value: string): string {
        if (!value) return ''
        if (value.includes('BEGIN PRIVATE KEY')) return value.replaceAll('\\n', '\n')
        return Buffer.from(value, 'base64').toString('utf8')
    }
}

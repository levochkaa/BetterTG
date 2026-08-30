import { InjectQueue } from '@nestjs/bullmq'
import { Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common'
import { InjectRepository } from '@nestjs/typeorm'
import type { Queue } from 'bullmq'
import type { Repository } from 'typeorm'

import { RedisService } from '@/infrastructure/redis.service'
import { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'
import { MetricsService } from '@/observability/metrics.service'
import { SecretBoxService } from '@/security/secret-box.service'

import {
    TELEGRAM_WEB_PUSH_QUEUE,
    type TelegramWebPushJob,
    type WebPushEncryptionMetadata,
} from '../web-push-job'

const DEDUPLICATION_TTL_SECONDS = 24 * 60 * 60
const AES128GCM_MIN_BODY_BYTES = 104
const AESGCM_MIN_BODY_BYTES = 19

interface WebPushHeaders {
    contentEncoding?: string
    encryption?: string
    cryptoKey?: string
}

@Injectable()
export class WebPushIngressService {
    private readonly logger = new Logger(WebPushIngressService.name)

    constructor(
        @InjectRepository(TelegramPushSubscriptionEntity)
        private readonly subscriptions: Repository<TelegramPushSubscriptionEntity>,
        @InjectQueue(TELEGRAM_WEB_PUSH_QUEUE)
        private readonly queue: Queue<TelegramWebPushJob>,
        private readonly redis: RedisService,
        private readonly secretBox: SecretBoxService,
        private readonly metrics: MetricsService,
    ) {}

    async accept(
        capabilityToken: string,
        ciphertext: Buffer,
        headers: WebPushHeaders,
        ipAddress: string,
    ): Promise<string> {
        if (!/^[A-Za-z0-9_-]{40,}$/.test(capabilityToken)) {
            throw new NotFoundException()
        }

        const endpointTokenHash = this.secretBox.hashCapability(capabilityToken)
        const subscription = await this.subscriptions.findOne({
            where: { endpointTokenHash },
            relations: { installation: true },
        })
        if (!subscription || subscription.installation.status !== 'active') {
            this.metrics.ingress.add(1, { status: 'unknown_subscription' })
            throw new NotFoundException()
        }

        let encryption: WebPushEncryptionMetadata
        try {
            encryption = parseEncryptionMetadata(headers)
        } catch {
            this.metrics.ingress.add(1, { status: 'unsupported_encoding' })
            this.reject(
                subscription.id,
                'invalid_encryption_metadata',
                headers.contentEncoding,
                ciphertext.length,
            )
        }

        const minimumBodyBytes =
            encryption.contentEncoding === 'aesgcm'
                ? AESGCM_MIN_BODY_BYTES
                : AES128GCM_MIN_BODY_BYTES
        if (ciphertext.length < minimumBodyBytes || ciphertext.length > 8192) {
            this.metrics.ingress.add(1, { status: 'invalid_size' })
            this.reject(
                subscription.id,
                'invalid_size',
                encryption.contentEncoding,
                ciphertext.length,
            )
        }

        await Promise.all([
            this.redis.enforceRateLimit(`webpush:ip:${ipAddress}`, 600, 60),
            this.redis.enforceRateLimit(`webpush:subscription:${subscription.id}`, 120, 60),
        ])

        const digest = this.secretBox.ciphertextDigest(ciphertext)
        const deduplicationKey = `webpush:dedupe:${subscription.id}:${digest}`
        const firstDelivery = await this.redis.client.set(
            deduplicationKey,
            '1',
            'EX',
            DEDUPLICATION_TTL_SECONDS,
            'NX',
        )
        if (firstDelivery !== 'OK') {
            this.metrics.ingress.add(1, { status: 'duplicate' })
            return digest
        }

        try {
            const receivedAt = new Date()
            await this.queue.add(
                'deliver',
                {
                    subscriptionId: subscription.id,
                    ciphertextBase64: ciphertext.toString('base64'),
                    encryption,
                    receivedAt: receivedAt.toISOString(),
                },
                {
                    jobId: `${subscription.id}-${digest}`,
                    attempts: 5,
                    backoff: { type: 'exponential', delay: 1000, jitter: 0.5 },
                    removeOnComplete: true,
                    removeOnFail: { age: 3600, count: 100 },
                },
            )
            await this.subscriptions.update({ id: subscription.id }, { lastReceivedAt: receivedAt })
            this.metrics.ingress.add(1, { status: 'accepted' })
            this.logger.log({
                event: 'webpush.accepted',
                subscriptionId: subscription.id,
                contentEncoding: encryption.contentEncoding,
                bodyBytes: ciphertext.length,
            })
            return digest
        } catch {
            await this.redis.client.del(deduplicationKey)
            this.metrics.ingress.add(1, { status: 'enqueue_failed' })
            throw new ServiceUnavailableException('push queue is unavailable')
        }
    }

    private reject(
        subscriptionId: string,
        reason: string,
        contentEncoding: string | undefined,
        bodyBytes: number,
    ): never {
        this.logger.warn({
            event: 'webpush.rejected',
            subscriptionId,
            reason,
            contentEncoding: contentEncoding?.toLowerCase() ?? 'missing',
            bodyBytes,
        })
        throw new NotFoundException()
    }
}

function parseEncryptionMetadata(headers: WebPushHeaders): WebPushEncryptionMetadata {
    const contentEncoding = headers.contentEncoding?.trim().toLowerCase()
    if (contentEncoding === 'aes128gcm') return { contentEncoding }
    if (contentEncoding !== 'aesgcm') throw new Error('unsupported content encoding')

    const saltBase64url = readHeaderParameter(headers.encryption, 'salt')
    const senderPublicKeyBase64url = readHeaderParameter(headers.cryptoKey, 'dh')
    const salt = decodeCanonicalBase64url(saltBase64url)
    const senderPublicKey = decodeCanonicalBase64url(senderPublicKeyBase64url)
    if (salt.length !== 16) throw new Error('invalid salt')
    if (senderPublicKey.length !== 65 || senderPublicKey[0] !== 4) {
        throw new Error('invalid sender public key')
    }

    const recordSizeValue = readHeaderParameter(headers.encryption, 'rs', false)
    const recordSize = recordSizeValue === undefined ? 4096 : Number(recordSizeValue)
    if (!Number.isSafeInteger(recordSize) || recordSize <= 18 || recordSize > 65_536) {
        throw new Error('invalid record size')
    }

    return {
        contentEncoding,
        saltBase64url,
        senderPublicKeyBase64url,
        recordSize,
    }
}

function readHeaderParameter(
    header: string | undefined,
    name: string,
    required = true,
): string | undefined {
    const parameter = header
        ?.split(/[;,]/)
        .map((part) => part.trim())
        .find((part) => part.slice(0, part.indexOf('=')).trim().toLowerCase() === name)
    if (!parameter) {
        if (required) throw new Error(`missing ${name}`)
        return undefined
    }
    const separator = parameter.indexOf('=')
    let value = parameter.slice(separator + 1).trim()
    if (value.startsWith('"') && value.endsWith('"')) value = value.slice(1, -1)
    if (!value) throw new Error(`empty ${name}`)
    return value
}

function decodeCanonicalBase64url(value: string | undefined): Buffer {
    if (!value || !/^[A-Za-z0-9_-]+={0,2}$/.test(value)) throw new Error('invalid base64url')
    const unpadded = value.replace(/=+$/, '')
    const decoded = Buffer.from(unpadded, 'base64url')
    if (decoded.toString('base64url') !== unpadded) throw new Error('non-canonical base64url')
    return decoded
}

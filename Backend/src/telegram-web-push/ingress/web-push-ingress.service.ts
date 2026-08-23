import { InjectQueue } from '@nestjs/bullmq'
import { Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common'
import { InjectRepository } from '@nestjs/typeorm'
import type { Queue } from 'bullmq'
import type { Repository } from 'typeorm'

import { RedisService } from '@/infrastructure/redis.service'
import { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'
import { MetricsService } from '@/observability/metrics.service'
import { SecretBoxService } from '@/security/secret-box.service'

import { TELEGRAM_WEB_PUSH_QUEUE, type TelegramWebPushJob } from '../web-push-job'

const DEDUPLICATION_TTL_SECONDS = 24 * 60 * 60

@Injectable()
export class WebPushIngressService {
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
        contentEncoding: string | undefined,
        ipAddress: string,
    ): Promise<string> {
        if (!/^[A-Za-z0-9_-]{40,}$/.test(capabilityToken)) throw new NotFoundException()
        if (contentEncoding?.toLowerCase() !== 'aes128gcm') {
            this.metrics.ingress.add(1, { status: 'unsupported_encoding' })
            throw new NotFoundException()
        }
        if (ciphertext.length < 104 || ciphertext.length > 8192) {
            this.metrics.ingress.add(1, { status: 'invalid_size' })
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
            return digest
        } catch {
            await this.redis.client.del(deduplicationKey)
            this.metrics.ingress.add(1, { status: 'enqueue_failed' })
            throw new ServiceUnavailableException('push queue is unavailable')
        }
    }
}

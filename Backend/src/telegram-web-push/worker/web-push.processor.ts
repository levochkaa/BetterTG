import { Processor, WorkerHost } from '@nestjs/bullmq'
import { Logger } from '@nestjs/common'
import { InjectRepository } from '@nestjs/typeorm'
import type { Job } from 'bullmq'
import type { Repository } from 'typeorm'

import { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'
import { InstallationEntity } from '@/installations/installation.entity'
import { ApnsClientService } from '@/notifications/apns/apns-client.service'
import { ApnsPayloadMapperService } from '@/notifications/apns/apns-payload-mapper.service'
import { MetricsService } from '@/observability/metrics.service'
import { SecretBoxService } from '@/security/secret-box.service'

import { classifyTelegramPush } from '../classification/telegram-push-classifier'
import {
    InvalidWebPushPayloadError,
    WebPushDecryptorService,
} from '../crypto/web-push-decryptor.service'
import { TELEGRAM_WEB_PUSH_QUEUE, type TelegramWebPushJob } from '../web-push-job'

@Processor(TELEGRAM_WEB_PUSH_QUEUE, { concurrency: 20 })
export class WebPushProcessor extends WorkerHost {
    private readonly logger = new Logger(WebPushProcessor.name)

    constructor(
        @InjectRepository(TelegramPushSubscriptionEntity)
        private readonly subscriptions: Repository<TelegramPushSubscriptionEntity>,
        @InjectRepository(InstallationEntity)
        private readonly installations: Repository<InstallationEntity>,
        private readonly decryptor: WebPushDecryptorService,
        private readonly mapper: ApnsPayloadMapperService,
        private readonly apns: ApnsClientService,
        private readonly secretBox: SecretBoxService,
        private readonly metrics: MetricsService,
    ) {
        super()
    }

    async process(job: Job<TelegramWebPushJob>): Promise<void> {
        const startedAt = performance.now()
        const subscription = await this.subscriptions.findOne({
            where: { id: job.data.subscriptionId },
            relations: { installation: true },
        })
        if (!subscription || subscription.installation.status !== 'active') return

        try {
            const payload = this.decryptor.decryptTelegramPayload(
                subscription,
                Buffer.from(job.data.ciphertextBase64, 'base64'),
                job.data.encryption,
            )
            const action = classifyTelegramPush(payload.data.loc_key)
            this.metrics.classification.add(1, { loc_key: payload.data.loc_key, action })
            const command = this.mapper.map(
                action,
                payload,
                String(job.id ?? `${subscription.id}:${job.data.receivedAt}`),
            )
            if (!command) {
                this.logger.log({
                    event: 'webpush.ignored',
                    subscriptionId: subscription.id,
                    locKey: payload.data.loc_key,
                    action,
                })
                return
            }

            const installation = subscription.installation
            const deviceToken = this.secretBox
                .decrypt(
                    installation.apnsTokenEncrypted,
                    `installation:${installation.id}:apns-token`,
                )
                .toString('utf8')
            const result = await this.apns.send({
                ...command,
                deviceToken,
                environment: installation.apnsEnvironment,
                topic: installation.bundleId,
            })
            this.metrics.apnsRequests.add(1, {
                status: result.kind,
                push_type: command.pushType,
                reason: 'reason' in result ? (result.reason ?? 'unknown') : 'none',
            })

            if (result.kind === 'retryable') throw new RetryableApnsError(result.reason)
            if (result.kind === 'invalid-token') {
                await this.installations.update({ id: installation.id }, { status: 'disabled' })
            }
            if (result.kind === 'success') {
                this.logger.log({
                    event: 'apns.delivered',
                    subscriptionId: subscription.id,
                    locKey: payload.data.loc_key,
                    pushType: command.pushType,
                })
            }
            if (result.kind === 'permanent' || result.kind === 'invalid-token') {
                this.logger.warn({
                    event: 'apns.delivery_failed',
                    subscriptionId: subscription.id,
                    locKey: payload.data.loc_key,
                    result: result.kind,
                    reason: result.reason,
                })
            }
        } catch (error) {
            if (error instanceof InvalidWebPushPayloadError) {
                this.metrics.decryptionFailures.add(1)
                this.logger.warn({
                    event: 'webpush.decryption_failed',
                    subscriptionId: subscription.id,
                })
                return
            }
            throw error
        } finally {
            this.metrics.processingDuration.record(performance.now() - startedAt)
        }
    }
}

export class RetryableApnsError extends Error {
    constructor(reason?: string) {
        super(reason ?? 'retryable APNs failure')
        this.name = 'RetryableApnsError'
    }
}

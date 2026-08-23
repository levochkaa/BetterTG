import { describe, expect, it, mock } from 'bun:test'
import { ConfigService } from '@nestjs/config'
import type { Queue } from 'bullmq'
import type { Repository } from 'typeorm'

import type { Environment } from '@/config/environment'
import type { RedisService } from '@/infrastructure/redis.service'
import { InstallationEntity } from '@/installations/installation.entity'
import { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'
import type { MetricsService } from '@/observability/metrics.service'
import { SecretBoxService } from '@/security/secret-box.service'

import type { TelegramWebPushJob } from '../web-push-job'
import { WebPushIngressService } from './web-push-ingress.service'

function secretBox(): SecretBoxService {
    return new SecretBoxService(
        new ConfigService<Environment, true>({
            ENCRYPTION_CURRENT_KEY_ID: 'test',
            ENCRYPTION_KEYS: 'test:AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
            MANAGEMENT_TOKEN_PEPPER: 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
        } as Environment),
    )
}

describe('WebPushIngressService', () => {
    it('queues ciphertext only and deduplicates retries', async () => {
        const box = secretBox()
        const installation = Object.assign(new InstallationEntity(), { status: 'active' as const })
        const subscription = Object.assign(new TelegramPushSubscriptionEntity(), {
            id: '018f47a0-7b8d-7c1f-8c2e-723456789abc',
            endpointTokenHash: box.hashCapability('a'.repeat(43)),
            installation,
        })
        const findOne = mock(() => Promise.resolve(subscription))
        const update = mock(() => Promise.resolve({ affected: 1 }))
        const add = mock((_name: string, _data: TelegramWebPushJob) => Promise.resolve(undefined))
        const set = mock(() => Promise.resolve<string | null>('OK'))
        const del = mock(() => Promise.resolve(1))
        const rateLimit = mock(() => Promise.resolve())
        const metricAdd = mock(() => undefined)
        const service = new WebPushIngressService(
            { findOne, update } as unknown as Repository<TelegramPushSubscriptionEntity>,
            { add } as unknown as Queue<TelegramWebPushJob>,
            {
                client: { set, del },
                enforceRateLimit: rateLimit,
            } as unknown as RedisService,
            box,
            { ingress: { add: metricAdd } } as unknown as MetricsService,
        )
        const ciphertext = Buffer.alloc(104, 7)

        const digest = await service.accept('a'.repeat(43), ciphertext, 'aes128gcm', '127.0.0.1')

        expect(digest).toBe(box.ciphertextDigest(ciphertext))
        expect(add).toHaveBeenCalledTimes(1)
        const queued = add.mock.calls[0]?.[1]
        expect(queued?.ciphertextBase64).toBe(ciphertext.toString('base64'))
        expect(JSON.stringify(queued)).not.toContain('loc_args')

        set.mockImplementationOnce(() => Promise.resolve(null))
        await service.accept('a'.repeat(43), ciphertext, 'aes128gcm', '127.0.0.1')
        expect(add).toHaveBeenCalledTimes(1)
    })
})

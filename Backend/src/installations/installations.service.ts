import { ConflictException, Injectable, NotFoundException } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import { InjectRepository } from '@nestjs/typeorm'
import { createECDH, randomBytes, randomUUID } from 'node:crypto'
import { DataSource, Repository } from 'typeorm'

import type { Environment } from '@/config/environment'
import { RedisService } from '@/infrastructure/redis.service'
import { SecretBoxService } from '@/security/secret-box.service'
import { AppAttestKeyEntity } from '@/app-attest/app-attest-key.entity'

import { InstallationEntity } from './installation.entity'
import { TelegramPushSubscriptionEntity } from './telegram-push-subscription.entity'
import type {
    CreateInstallationDto,
    InstallationCreatedResponse,
    TelegramSubscriptionResponse,
    UpdateApnsTokenDto,
} from './installations.dto'

const IDEMPOTENCY_TTL_SECONDS = 10 * 60

@Injectable()
export class InstallationsService {
    private readonly bundleId: string
    private readonly publicBaseUrl: string

    constructor(
        config: ConfigService<Environment, true>,
        private readonly secretBox: SecretBoxService,
        private readonly redis: RedisService,
        private readonly dataSource: DataSource,
        @InjectRepository(InstallationEntity)
        private readonly installations: Repository<InstallationEntity>,
        @InjectRepository(TelegramPushSubscriptionEntity)
        private readonly subscriptions: Repository<TelegramPushSubscriptionEntity>,
    ) {
        this.bundleId = config.get('BUNDLE_ID', { infer: true })
        this.publicBaseUrl = config.get('PUBLIC_BASE_URL', { infer: true }).replace(/\/$/, '')
    }

    async cachedCreation(idempotencyKey: string): Promise<InstallationCreatedResponse | null> {
        const value = await this.redis.client.get(this.idempotencyResultKey(idempotencyKey))
        return value
            ? (JSON.parse(
                  this.secretBox
                      .decrypt(value, `installation-idempotency:${idempotencyKey}`)
                      .toString('utf8'),
              ) as InstallationCreatedResponse)
            : null
    }

    async create(
        dto: CreateInstallationDto,
        appAttestKeyId: string | null,
        idempotencyKey: string,
    ): Promise<InstallationCreatedResponse> {
        const cached = await this.cachedCreation(idempotencyKey)
        if (cached) return cached

        const lockKey = `installation:create:lock:${idempotencyKey}`
        const locked = await this.redis.client.set(lockKey, '1', 'EX', 15, 'NX')
        if (locked !== 'OK') throw new ConflictException('installation creation is already running')

        try {
            const secondCheck = await this.cachedCreation(idempotencyKey)
            if (secondCheck) return secondCheck

            const installationId = randomUUID()
            const managementSecret = this.secretBox.randomToken()
            await this.installations.save(
                this.installations.create({
                    id: installationId,
                    managementSecretHash: this.secretBox.hashManagementToken(managementSecret),
                    apnsTokenEncrypted: this.secretBox.encrypt(
                        dto.apnsToken.toLowerCase(),
                        `installation:${installationId}:apns-token`,
                    ),
                    apnsEnvironment: dto.apnsEnvironment,
                    bundleId: this.bundleId,
                    appAttestKeyId,
                    appVersion: dto.appVersion ?? null,
                    osVersion: dto.osVersion ?? null,
                    status: 'active',
                    lastSeenAt: new Date(),
                }),
            )

            const response = { installationId, managementSecret }
            await this.redis.client.set(
                this.idempotencyResultKey(idempotencyKey),
                this.secretBox.encrypt(
                    JSON.stringify(response),
                    `installation-idempotency:${idempotencyKey}`,
                ),
                'EX',
                IDEMPOTENCY_TTL_SECONDS,
            )
            await this.redis.client.set(
                this.installationIdempotencyKey(installationId),
                idempotencyKey,
                'EX',
                IDEMPOTENCY_TTL_SECONDS,
            )
            return response
        } finally {
            await this.redis.client.del(lockKey)
        }
    }

    async updateApnsToken(
        installation: InstallationEntity,
        dto: UpdateApnsTokenDto,
    ): Promise<void> {
        installation.apnsTokenEncrypted = this.secretBox.encrypt(
            dto.apnsToken.toLowerCase(),
            `installation:${installation.id}:apns-token`,
        )
        installation.apnsEnvironment = dto.apnsEnvironment
        installation.appVersion = dto.appVersion ?? installation.appVersion
        installation.osVersion = dto.osVersion ?? installation.osVersion
        installation.status = 'active'
        installation.lastSeenAt = new Date()
        await this.installations.save(installation)
    }

    async rotateSubscription(
        installation: InstallationEntity,
    ): Promise<TelegramSubscriptionResponse> {
        const subscriptionId = randomUUID()
        const endpointToken = this.secretBox.randomToken()
        const ecdh = createECDH('prime256v1')
        ecdh.generateKeys()
        const publicKey = ecdh.getPublicKey(undefined, 'uncompressed')
        const privateKey = ecdh.getPrivateKey()
        const authSecret = randomBytes(16)

        await this.dataSource.transaction(async (manager) => {
            const repository = manager.getRepository(TelegramPushSubscriptionEntity)
            await repository.delete({ installationId: installation.id })
            await repository.save(
                repository.create({
                    id: subscriptionId,
                    installationId: installation.id,
                    endpointTokenHash: this.secretBox.hashCapability(endpointToken),
                    p256dhPublicKey: publicKey.toString('base64url'),
                    p256dhPrivateKeyEncrypted: this.secretBox.encrypt(
                        privateKey,
                        `telegram-subscription:${subscriptionId}:private-key`,
                    ),
                    authSecretEncrypted: this.secretBox.encrypt(
                        authSecret,
                        `telegram-subscription:${subscriptionId}:auth-secret`,
                    ),
                    lastReceivedAt: null,
                }),
            )
        })

        return {
            subscriptionId,
            endpoint: `${this.publicBaseUrl}/webpush/v1/${endpointToken}`,
            p256dhBase64url: publicKey.toString('base64url'),
            authBase64url: authSecret.toString('base64url'),
        }
    }

    async deleteSubscription(installationId: string, subscriptionId: string): Promise<void> {
        const result = await this.subscriptions.delete({ id: subscriptionId, installationId })
        if (!result.affected) throw new NotFoundException()
    }

    async deleteInstallation(installationId: string): Promise<void> {
        await this.dataSource.transaction(async (manager) => {
            const repository = manager.getRepository(InstallationEntity)
            const installation = await repository.findOneBy({ id: installationId })
            if (!installation) throw new NotFoundException()
            await repository.delete({ id: installationId })
            if (installation.appAttestKeyId) {
                const remaining = await repository.countBy({
                    appAttestKeyId: installation.appAttestKeyId,
                })
                if (remaining === 0) {
                    await manager
                        .getRepository(AppAttestKeyEntity)
                        .delete({ keyId: installation.appAttestKeyId })
                }
            }
        })

        const idempotencyKey = await this.redis.client.get(
            this.installationIdempotencyKey(installationId),
        )
        const keys = [this.installationIdempotencyKey(installationId)]
        if (idempotencyKey) keys.push(this.idempotencyResultKey(idempotencyKey))
        await this.redis.client.del(...keys)
    }

    private idempotencyResultKey(idempotencyKey: string): string {
        return `installation:create:result:${idempotencyKey}`
    }

    private installationIdempotencyKey(installationId: string): string {
        return `installation:create:idempotency:${installationId}`
    }
}

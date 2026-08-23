import { Injectable, UnauthorizedException } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import { InjectRepository } from '@nestjs/typeorm'
import { createHash } from 'node:crypto'
import { DataSource, Repository } from 'typeorm'
import { verifyAssertion, verifyAttestation } from 'appattest-checker-node'

import type { Environment } from '@/config/environment'
import { RedisService } from '@/infrastructure/redis.service'
import { SecretBoxService } from '@/security/secret-box.service'

import { AppAttestKeyEntity } from './app-attest-key.entity'
import type { VerifyAttestationDto } from './app-attest.dto'

const CHALLENGE_TTL_SECONDS = 5 * 60

@Injectable()
export class AppAttestService {
    private readonly mode: Environment['APP_ATTEST_MODE']
    private readonly appId: string
    private readonly allowDevelopmentEnvironment: boolean

    constructor(
        private readonly config: ConfigService<Environment, true>,
        private readonly redis: RedisService,
        private readonly secretBox: SecretBoxService,
        private readonly dataSource: DataSource,
        @InjectRepository(AppAttestKeyEntity)
        private readonly keys: Repository<AppAttestKeyEntity>,
    ) {
        this.mode = config.get('APP_ATTEST_MODE', { infer: true })
        this.appId = `${config.get('APPLE_TEAM_ID', { infer: true })}.${config.get('BUNDLE_ID', { infer: true })}`
        this.allowDevelopmentEnvironment = config.get('APP_ATTEST_ALLOW_DEVELOPMENT', {
            infer: true,
        })
    }

    async issueChallenge(ipAddress: string): Promise<{ challenge: string }> {
        await this.redis.enforceRateLimit(`app-attest:${ipAddress}`, 30, 60)
        const challenge = this.secretBox.randomToken()
        await this.redis.client.set(this.challengeKey(challenge), '1', 'EX', CHALLENGE_TTL_SECONDS)
        return { challenge }
    }

    async registerAttestation(dto: VerifyAttestationDto): Promise<void> {
        if (this.mode === 'bypass') return
        await this.consumeChallenge(dto.challenge)

        const result = await verifyAttestation(
            {
                appId: this.appId,
                developmentEnv: this.allowDevelopmentEnvironment,
            },
            dto.keyId,
            Buffer.from(dto.challenge, 'utf8'),
            Buffer.from(dto.attestation, 'base64'),
        )
        if ('verifyError' in result) throw new UnauthorizedException('invalid app attestation')

        const existing = await this.keys.findOneBy({ keyId: dto.keyId })
        if (existing && existing.publicKeyPem !== result.publicKeyPem) {
            throw new UnauthorizedException('attestation key collision')
        }

        await this.keys.save(
            this.keys.create({
                keyId: dto.keyId,
                publicKeyPem: result.publicKeyPem,
                receiptEncrypted: this.secretBox.encrypt(
                    result.receipt,
                    `app-attest:${dto.keyId}:receipt`,
                ),
                signCount: existing?.signCount ?? 0,
                revoked: false,
            }),
        )
    }

    async verifyRequest(
        rawBody: Buffer | undefined,
        challenge: string | undefined,
        keyId: string | undefined,
        assertionBase64: string | undefined,
    ): Promise<string | null> {
        if (this.mode === 'bypass') return null
        if (!rawBody || !challenge || !keyId || !assertionBase64) {
            throw new UnauthorizedException('App Attest assertion is required')
        }

        await this.consumeChallenge(challenge)
        const assertion = Buffer.from(assertionBase64, 'base64')
        const clientDataHash = createHash('sha256').update(rawBody).digest()

        await this.dataSource.transaction(async (manager) => {
            const repository = manager.getRepository(AppAttestKeyEntity)
            const key = await repository.findOne({
                where: { keyId, revoked: false },
                lock: { mode: 'pessimistic_write' },
            })
            if (!key) throw new UnauthorizedException('unknown App Attest key')

            const result = await verifyAssertion(
                clientDataHash,
                key.publicKeyPem,
                this.appId,
                assertion,
            )
            if ('verifyError' in result || result.signCount <= key.signCount) {
                throw new UnauthorizedException('invalid App Attest assertion')
            }

            key.signCount = result.signCount
            await repository.save(key)
        })

        return keyId
    }

    private async consumeChallenge(challenge: string): Promise<void> {
        const consumed = await this.redis.client.call('GETDEL', this.challengeKey(challenge))
        if (consumed !== '1') throw new UnauthorizedException('invalid or expired challenge')
    }

    private challengeKey(challenge: string): string {
        return `app-attest:challenge:${createHash('sha256').update(challenge).digest('hex')}`
    }
}

import { Injectable } from '@nestjs/common'
import { createECDH } from 'node:crypto'
import { decrypt } from 'http_ece'

import type { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'
import { SecretBoxService } from '@/security/secret-box.service'

import { parseTelegramPushPayload, type TelegramPushPayload } from '../telegram-push-payload'

export class InvalidWebPushPayloadError extends Error {
    constructor() {
        super('invalid encrypted Web Push payload')
        this.name = 'InvalidWebPushPayloadError'
    }
}

@Injectable()
export class WebPushDecryptorService {
    constructor(private readonly secretBox: SecretBoxService) {}

    decryptBytes(subscription: TelegramPushSubscriptionEntity, ciphertext: Buffer): Buffer {
        try {
            const privateKey = this.secretBox.decrypt(
                subscription.p256dhPrivateKeyEncrypted,
                `telegram-subscription:${subscription.id}:private-key`,
            )
            const authSecret = this.secretBox.decrypt(
                subscription.authSecretEncrypted,
                `telegram-subscription:${subscription.id}:auth-secret`,
            )
            const ecdh = createECDH('prime256v1')
            ecdh.setPrivateKey(privateKey)
            return decrypt(ciphertext, {
                version: 'aes128gcm',
                privateKey: ecdh,
                authSecret,
            })
        } catch {
            throw new InvalidWebPushPayloadError()
        }
    }

    decryptTelegramPayload(
        subscription: TelegramPushSubscriptionEntity,
        ciphertext: Buffer,
    ): TelegramPushPayload {
        try {
            const plaintext = this.decryptBytes(subscription, ciphertext)
            if (plaintext.length > 4096) throw new InvalidWebPushPayloadError()
            return parseTelegramPushPayload(JSON.parse(plaintext.toString('utf8')) as unknown)
        } catch {
            throw new InvalidWebPushPayloadError()
        }
    }
}

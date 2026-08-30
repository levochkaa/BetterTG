import { Injectable } from '@nestjs/common'
import { createECDH } from 'node:crypto'
import { decrypt } from 'http_ece'

import type { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'
import { SecretBoxService } from '@/security/secret-box.service'

import { parseTelegramPushPayload, type TelegramPushPayload } from '../telegram-push-payload'
import type { WebPushEncryptionMetadata } from '../web-push-job'

export class InvalidWebPushPayloadError extends Error {
    readonly reason: string

    constructor(cause?: unknown) {
        super('invalid encrypted Web Push payload')
        this.name = 'InvalidWebPushPayloadError'
        this.reason = classifyDecryptionFailure(cause)
    }
}

@Injectable()
export class WebPushDecryptorService {
    constructor(private readonly secretBox: SecretBoxService) {}

    decryptBytes(
        subscription: TelegramPushSubscriptionEntity,
        ciphertext: Buffer,
        encryption: WebPushEncryptionMetadata = { contentEncoding: 'aes128gcm' },
    ): Buffer {
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
            if (encryption.contentEncoding === 'aesgcm') {
                if (!encryption.senderPublicKeyBase64url || !encryption.saltBase64url) {
                    throw new Error('missing legacy Web Push encryption metadata')
                }
                return decrypt(ciphertext, {
                    version: 'aesgcm',
                    privateKey: ecdh,
                    authSecret,
                    dh: Buffer.from(encryption.senderPublicKeyBase64url, 'base64url'),
                    salt: Buffer.from(encryption.saltBase64url, 'base64url'),
                    rs: encryption.recordSize,
                })
            }
            return decrypt(ciphertext, {
                version: 'aes128gcm',
                privateKey: ecdh,
                authSecret,
            })
        } catch (error) {
            throw new InvalidWebPushPayloadError(error)
        }
    }

    decryptTelegramPayload(
        subscription: TelegramPushSubscriptionEntity,
        ciphertext: Buffer,
        encryption: WebPushEncryptionMetadata = { contentEncoding: 'aes128gcm' },
    ): TelegramPushPayload {
        try {
            const plaintext = this.decryptBytes(subscription, ciphertext, encryption)
            if (plaintext.length > 4096) {
                throw new InvalidWebPushPayloadError(new Error('plaintext_too_large'))
            }
            return parseTelegramPushPayload(JSON.parse(plaintext.toString('utf8')) as unknown)
        } catch (error) {
            if (error instanceof InvalidWebPushPayloadError) throw error
            throw new InvalidWebPushPayloadError(error)
        }
    }
}

function classifyDecryptionFailure(cause: unknown): string {
    const message = cause instanceof Error ? cause.message.toLowerCase() : ''
    if (message.includes('authenticate') || message.includes('auth tag')) {
        return 'authentication_failed'
    }
    if (message.includes('padding')) return 'invalid_padding'
    if (message.includes('truncated')) return 'truncated_payload'
    if (message.includes('block')) return 'invalid_record'
    if (message.includes('plaintext_too_large')) return 'plaintext_too_large'
    if (cause instanceof SyntaxError) return 'invalid_json'
    return 'invalid_key_material_or_payload'
}

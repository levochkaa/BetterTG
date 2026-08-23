import { describe, expect, it } from 'bun:test'
import { ConfigService } from '@nestjs/config'
import { createECDH } from 'node:crypto'
import { encrypt } from 'http_ece'

import type { Environment } from '@/config/environment'
import { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'
import { SecretBoxService } from '@/security/secret-box.service'

import { InvalidWebPushPayloadError, WebPushDecryptorService } from './web-push-decryptor.service'

function secretBox(): SecretBoxService {
    return new SecretBoxService(
        new ConfigService<Environment, true>({
            ENCRYPTION_CURRENT_KEY_ID: 'test',
            ENCRYPTION_KEYS: 'test:AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
            MANAGEMENT_TOKEN_PEPPER: 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
        } as Environment),
    )
}

describe('WebPushDecryptorService', () => {
    it('decrypts an RFC 8291 aes128gcm message using stored receiver secrets', () => {
        const box = secretBox()
        const subscription = new TelegramPushSubscriptionEntity()
        subscription.id = '018f47a0-7b8d-7c1f-8c2e-323456789abc'
        subscription.p256dhPrivateKeyEncrypted = box.encrypt(
            Buffer.from('q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94', 'base64url'),
            `telegram-subscription:${subscription.id}:private-key`,
        )
        subscription.authSecretEncrypted = box.encrypt(
            Buffer.from('BTBZMqHH6r4Tts7J_aSIgg', 'base64url'),
            `telegram-subscription:${subscription.id}:auth-secret`,
        )
        const ciphertext = Buffer.from(
            'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
            'base64url',
        )

        expect(
            new WebPushDecryptorService(box).decryptBytes(subscription, ciphertext).toString(),
        ).toBe('When I grow up, I want to be a watermelon')
    })

    it('parses a synthetic Telegram payload and rejects tampering', () => {
        const box = secretBox()
        const receiver = createECDH('prime256v1')
        receiver.generateKeys()
        const sender = createECDH('prime256v1')
        sender.generateKeys()
        const authSecret = Buffer.alloc(16, 7)
        const subscription = new TelegramPushSubscriptionEntity()
        subscription.id = '018f47a0-7b8d-7c1f-8c2e-423456789abc'
        subscription.p256dhPrivateKeyEncrypted = box.encrypt(
            receiver.getPrivateKey(),
            `telegram-subscription:${subscription.id}:private-key`,
        )
        subscription.authSecretEncrypted = box.encrypt(
            authSecret,
            `telegram-subscription:${subscription.id}:auth-secret`,
        )
        const ciphertext = encrypt(
            Buffer.from(
                JSON.stringify({
                    data: {
                        loc_key: 'MESSAGE_TEXT',
                        loc_args: ['Alice', 'Hello'],
                        custom: { from_id: 1, msg_id: 2 },
                    },
                }),
            ),
            {
                version: 'aes128gcm',
                privateKey: sender,
                dh: receiver.getPublicKey(),
                authSecret,
            },
        )
        const decryptor = new WebPushDecryptorService(box)

        expect(decryptor.decryptTelegramPayload(subscription, ciphertext).data.loc_key).toBe(
            'MESSAGE_TEXT',
        )
        ciphertext[ciphertext.length - 1] = (ciphertext.at(-1) ?? 0) ^ 1
        expect(() => decryptor.decryptTelegramPayload(subscription, ciphertext)).toThrow(
            InvalidWebPushPayloadError,
        )
    })
})

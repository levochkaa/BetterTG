import { Injectable } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import {
    createCipheriv,
    createDecipheriv,
    createHash,
    createHmac,
    randomBytes,
    timingSafeEqual,
} from 'node:crypto'

import type { Environment } from '@/config/environment'

interface EncryptedValue {
    keyId: string
    iv: Buffer
    tag: Buffer
    ciphertext: Buffer
}

@Injectable()
export class SecretBoxService {
    private readonly currentKeyId: string
    private readonly encryptionKeys: Map<string, Buffer>
    private readonly managementTokenPepper: Buffer

    constructor(config: ConfigService<Environment, true>) {
        this.currentKeyId = config.get('ENCRYPTION_CURRENT_KEY_ID', { infer: true })
        this.encryptionKeys = this.parseKeyring(config.get('ENCRYPTION_KEYS', { infer: true }))
        this.managementTokenPepper = this.decodeKey(
            config.get('MANAGEMENT_TOKEN_PEPPER', { infer: true }),
            'MANAGEMENT_TOKEN_PEPPER',
        )

        if (!this.encryptionKeys.has(this.currentKeyId)) {
            throw new Error(
                `ENCRYPTION_CURRENT_KEY_ID ${this.currentKeyId} is missing from keyring`,
            )
        }
    }

    encrypt(value: Buffer | string, associatedData: string): string {
        const key = this.encryptionKeys.get(this.currentKeyId)
        if (!key) throw new Error('current encryption key is unavailable')

        const iv = randomBytes(12)
        const cipher = createCipheriv('aes-256-gcm', key, iv)
        cipher.setAAD(Buffer.from(associatedData, 'utf8'))
        const ciphertext = Buffer.concat([
            cipher.update(typeof value === 'string' ? Buffer.from(value, 'utf8') : value),
            cipher.final(),
        ])
        const tag = cipher.getAuthTag()

        return [
            'v1',
            this.currentKeyId,
            iv.toString('base64url'),
            tag.toString('base64url'),
            ciphertext.toString('base64url'),
        ].join('.')
    }

    decrypt(value: string, associatedData: string): Buffer {
        const encrypted = this.parseEncryptedValue(value)
        const key = this.encryptionKeys.get(encrypted.keyId)
        if (!key) throw new Error(`encryption key ${encrypted.keyId} is unavailable`)

        const decipher = createDecipheriv('aes-256-gcm', key, encrypted.iv)
        decipher.setAAD(Buffer.from(associatedData, 'utf8'))
        decipher.setAuthTag(encrypted.tag)
        return Buffer.concat([decipher.update(encrypted.ciphertext), decipher.final()])
    }

    hashManagementToken(token: string): string {
        return createHmac('sha256', this.managementTokenPepper).update(token).digest('hex')
    }

    hashCapability(token: string): string {
        return createHash('sha256').update(token).digest('hex')
    }

    ciphertextDigest(ciphertext: Buffer): string {
        return createHash('sha256').update(ciphertext).digest('hex')
    }

    randomToken(bytes = 32): string {
        return randomBytes(bytes).toString('base64url')
    }

    secureHashMatches(expectedHex: string, actualHex: string): boolean {
        const expected = Buffer.from(expectedHex, 'hex')
        const actual = Buffer.from(actualHex, 'hex')
        return expected.length === actual.length && timingSafeEqual(expected, actual)
    }

    private parseKeyring(value: string): Map<string, Buffer> {
        const entries = value.split(',').map((entry) => entry.trim())
        const keys = new Map<string, Buffer>()

        for (const entry of entries) {
            const separator = entry.indexOf(':')
            if (separator <= 0) throw new Error('ENCRYPTION_KEYS contains an invalid entry')
            const keyId = entry.slice(0, separator)
            const encodedKey = entry.slice(separator + 1)
            if (keys.has(keyId)) throw new Error(`duplicate encryption key id ${keyId}`)
            keys.set(keyId, this.decodeKey(encodedKey, `ENCRYPTION_KEYS:${keyId}`))
        }

        return keys
    }

    private decodeKey(value: string, field: string): Buffer {
        const key = Buffer.from(value, 'base64')
        if (key.length !== 32) throw new Error(`${field} must contain exactly 32 bytes`)
        return key
    }

    private parseEncryptedValue(value: string): EncryptedValue {
        const [version, keyId, iv, tag, ciphertext, ...extra] = value.split('.')
        if (
            version !== 'v1' ||
            !keyId ||
            !iv ||
            !tag ||
            ciphertext === undefined ||
            extra.length > 0
        ) {
            throw new Error('encrypted value has an invalid envelope')
        }

        return {
            keyId,
            iv: Buffer.from(iv, 'base64url'),
            tag: Buffer.from(tag, 'base64url'),
            ciphertext: Buffer.from(ciphertext, 'base64url'),
        }
    }
}

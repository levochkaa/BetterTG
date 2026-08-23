import { describe, expect, it } from 'bun:test'
import { ConfigService } from '@nestjs/config'

import type { Environment } from '@/config/environment'

import { SecretBoxService } from './secret-box.service'

function service(): SecretBoxService {
    return new SecretBoxService(
        new ConfigService<Environment, true>({
            ENCRYPTION_CURRENT_KEY_ID: 'v2',
            ENCRYPTION_KEYS:
                'v1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=,v2:AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
            MANAGEMENT_TOKEN_PEPPER: 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
        } as Environment),
    )
}

describe('SecretBoxService', () => {
    it('encrypts with associated data and decrypts with the keyring', () => {
        const secretBox = service()
        const encrypted = secretBox.encrypt('private', 'installation:1:apns')

        expect(encrypted.startsWith('v1.v2.')).toBe(true)
        expect(secretBox.decrypt(encrypted, 'installation:1:apns').toString()).toBe('private')
        expect(() => secretBox.decrypt(encrypted, 'installation:2:apns')).toThrow()
    })

    it('produces stable, domain-specific token hashes', () => {
        const secretBox = service()

        expect(secretBox.hashManagementToken('token')).toBe(secretBox.hashManagementToken('token'))
        expect(secretBox.hashManagementToken('token')).not.toBe(secretBox.hashCapability('token'))
    })
})

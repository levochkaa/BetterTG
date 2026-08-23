import { describe, expect, it } from 'bun:test'

import { validateEnvironment } from './environment'

describe('validateEnvironment', () => {
    it('provides safe local defaults', () => {
        const environment = validateEnvironment({})

        expect(environment.NODE_ENV).toBe('development')
        expect(environment.APNS_DRY_RUN).toBe(true)
        expect(environment.APP_ATTEST_MODE).toBe('bypass')
    })

    it('rejects insecure production configuration', () => {
        expect(() =>
            validateEnvironment({
                NODE_ENV: 'production',
                PUBLIC_BASE_URL: 'http://push.example.com',
            }),
        ).toThrow()
    })

    it('accepts production configuration with HTTPS and enforced attestation', () => {
        const environment = validateEnvironment({
            NODE_ENV: 'production',
            PUBLIC_BASE_URL: 'https://push.example.com',
            APP_ATTEST_MODE: 'enforce',
            ENCRYPTION_CURRENT_KEY_ID: 'v1',
            ENCRYPTION_KEYS: 'v1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            APNS_DRY_RUN: 'true',
        })

        expect(environment.APP_ATTEST_MODE).toBe('enforce')
    })
})

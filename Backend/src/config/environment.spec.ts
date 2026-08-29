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

    it('requires credentials for both APNs environments in real production delivery', () => {
        const production = {
            NODE_ENV: 'production',
            PUBLIC_BASE_URL: 'https://push.example.com',
            APP_ATTEST_MODE: 'enforce',
            ENCRYPTION_CURRENT_KEY_ID: 'v1',
            ENCRYPTION_KEYS: 'v1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            APNS_DRY_RUN: 'false',
            APNS_SANDBOX_KEY_ID: 'SBXKEY0001',
            APNS_SANDBOX_AUTH_KEY: 'sandbox-key',
        }

        expect(() => validateEnvironment(production)).toThrow()
        expect(
            validateEnvironment({
                ...production,
                APNS_PRODUCTION_KEY_ID: 'PRDKEY0001',
                APNS_PRODUCTION_AUTH_KEY: 'production-key',
            }).APNS_DRY_RUN,
        ).toBe(false)
    })
})

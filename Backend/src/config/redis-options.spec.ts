import { describe, expect, it } from 'bun:test'

import { redisOptionsFromUrl } from './redis-options'

describe('redisOptionsFromUrl', () => {
    it('parses credentials, TLS, and database', () => {
        expect(
            redisOptionsFromUrl('rediss://user:password@redis.example.com:6380/4'),
        ).toMatchObject({
            host: 'redis.example.com',
            port: 6380,
            username: 'user',
            password: 'password',
            db: 4,
            tls: {},
            maxRetriesPerRequest: null,
        })
    })
})

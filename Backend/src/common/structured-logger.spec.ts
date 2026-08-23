import { describe, expect, it } from 'bun:test'

import { redactForLog } from './structured-logger'

describe('redactForLog', () => {
    it('redacts secrets recursively without hiding safe metadata', () => {
        expect(
            redactForLog({
                event: 'delivery.failed',
                authorization: 'Bearer secret',
                nested: { apnsToken: 'token', status: 410 },
                loc_args: ['private text'],
            }),
        ).toEqual({
            event: 'delivery.failed',
            authorization: '[REDACTED]',
            nested: { apnsToken: '[REDACTED]', status: 410 },
            loc_args: '[REDACTED]',
        })
    })
})

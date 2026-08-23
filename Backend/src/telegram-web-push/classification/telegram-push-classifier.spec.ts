import { describe, expect, it } from 'bun:test'

import { classifyTelegramPush } from './telegram-push-classifier'

describe('classifyTelegramPush', () => {
    it('allows catalogued visible messages', () => {
        expect(classifyTelegramPush('CHAT_MESSAGE_TEXT')).toBe('alert')
        expect(classifyTelegramPush('CHANNEL_MESSAGE_PHOTO')).toBe('alert')
    })

    it('handles service and call pushes before visible rules', () => {
        expect(classifyTelegramPush('READ_HISTORY')).toBe('background')
        expect(classifyTelegramPush('MESSAGE_MUTED')).toBe('drop')
        expect(classifyTelegramPush('DC_UPDATE')).toBe('drop')
        expect(classifyTelegramPush('PHONE_CALL_REQUEST')).toBe('call')
    })

    it('fails closed for a new unreviewed key', () => {
        expect(classifyTelegramPush('MESSAGE_FUTURE_UNKNOWN')).toBe('unknown')
    })
})

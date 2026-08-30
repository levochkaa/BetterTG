import { describe, expect, it } from 'bun:test'

import { parseTelegramPushPayload } from './telegram-push-payload'

describe('parseTelegramPushPayload', () => {
    it('accepts a bounded Telegram message payload', () => {
        const payload = parseTelegramPushPayload({
            data: {
                loc_key: 'CHAT_MESSAGE_TEXT',
                loc_args: ['Alice', 'Family', 'Hello'],
                user_id: 42,
                custom: { chat_id: 5, msg_id: 9 },
            },
        })

        expect(payload.data.custom.msg_id).toBe(9)
    })

    it('normalizes the flat payload sent by Telegram Web Push', () => {
        const payload = parseTelegramPushPayload({
            loc_key: 'MESSAGE_TEXT',
            loc_args: ['Alice', 'Hello'],
            user_id: 42,
            custom: { from_id: '5', msg_id: '9', silent: '1' },
            mute: '0',
            badge: '1',
            title: 'Alice',
            description: 'Hello',
        })

        expect(payload.data.loc_key).toBe('MESSAGE_TEXT')
        expect(payload.data.custom).toEqual({ from_id: '5', msg_id: '9', silent: '1' })
        expect(payload.data.title).toBe('Alice')
    })

    it('rejects malformed keys and oversized arguments', () => {
        expect(() =>
            parseTelegramPushPayload({ data: { loc_key: 'message-text', loc_args: [] } }),
        ).toThrow()
        expect(() =>
            parseTelegramPushPayload({
                data: { loc_key: 'MESSAGE_TEXT', loc_args: ['x'.repeat(2049)] },
            }),
        ).toThrow()
    })
})

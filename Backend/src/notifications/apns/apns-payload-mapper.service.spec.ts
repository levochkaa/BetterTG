import { describe, expect, it } from 'bun:test'
import { ConfigService } from '@nestjs/config'

import type { Environment } from '@/config/environment'
import { SecretBoxService } from '@/security/secret-box.service'
import { parseTelegramPushPayload } from '@/telegram-web-push/telegram-push-payload'

import { ApnsPayloadMapperService } from './apns-payload-mapper.service'

function mapper(): ApnsPayloadMapperService {
    const secretBox = new SecretBoxService(
        new ConfigService<Environment, true>({
            ENCRYPTION_CURRENT_KEY_ID: 'test',
            ENCRYPTION_KEYS: 'test:AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
            MANAGEMENT_TOKEN_PEPPER: 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=',
        } as Environment),
    )
    return new ApnsPayloadMapperService(secretBox)
}

describe('ApnsPayloadMapperService', () => {
    it('maps a message to a localized, routable alert', () => {
        const command = mapper().map(
            'alert',
            parseTelegramPushPayload({
                data: {
                    loc_key: 'CHAT_MESSAGE_TEXT',
                    loc_args: ['Alice', 'Family', 'Hello'],
                    user_id: 42,
                    custom: { chat_id: 7, msg_id: 9 },
                },
            }),
            'delivery',
            new Date('2026-08-23T00:00:00Z'),
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        )

        expect(command?.pushType).toBe('alert')
        expect(command?.payload).toMatchObject({
            aps: {
                alert: {
                    'loc-key': 'CHAT_MESSAGE_TEXT',
                    'loc-args': ['Alice', 'Family', 'Hello'],
                },
                sound: 'default',
                'mutable-content': 1,
            },
            tg: {
                account: '42',
                peer_type: 'basicGroup',
                peer_id: '7',
                sender_type: 'basicGroup',
                sender_id: '7',
                sender_name: 'Alice',
                conversation_title: 'Family',
                message_id: '9',
                event: 'CHAT_MESSAGE_TEXT',
                notification_payload_token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
        })
        expect(command?.deliveryId).toMatch(/^[0-9a-f-]{36}$/)
    })

    it('routes a group author separately from the conversation', () => {
        const command = mapper().map(
            'alert',
            parseTelegramPushPayload({
                data: {
                    loc_key: 'CHAT_MESSAGE_PHOTO',
                    loc_args: ['Alice', 'Family'],
                    custom: { chat_id: 7, chat_from_id: 11, msg_id: 9 },
                },
            }),
            'group-author',
        )

        expect(command?.payload).toMatchObject({
            tg: {
                peer_type: 'basicGroup',
                peer_id: '7',
                sender_type: 'private',
                sender_id: '11',
                sender_name: 'Alice',
                conversation_title: 'Family',
            },
        })
    })

    it('uses the title and description preformatted by Telegram Web Push', () => {
        const command = mapper().map(
            'alert',
            parseTelegramPushPayload({
                loc_key: 'MESSAGE_TEXT',
                loc_args: ['Alice', 'Hello'],
                title: 'Alice',
                description: 'Hello',
                custom: { from_id: 1, msg_id: 2 },
            }),
            'preformatted',
        )

        expect(command?.payload).toMatchObject({
            aps: {
                alert: {
                    title: 'Alice',
                    body: 'Hello',
                },
            },
        })
    })

    it('omits sound for silent messages and trims oversized previews', () => {
        const command = mapper().map(
            'alert',
            parseTelegramPushPayload({
                data: {
                    loc_key: 'MESSAGE_TEXT',
                    loc_args: ['Alice', 'x'.repeat(2000), 'y'.repeat(2000)],
                    custom: { from_id: 1, msg_id: 2, silent: true },
                },
            }),
            'oversized',
        )
        const aps = command?.payload.aps as Record<string, unknown>

        expect(aps.sound).toBeUndefined()
        expect(Buffer.byteLength(JSON.stringify(command?.payload))).toBeLessThanOrEqual(4096)
    })

    it('maps read state to a coalesced background push', () => {
        const command = mapper().map(
            'background',
            parseTelegramPushPayload({
                data: {
                    loc_key: 'READ_HISTORY',
                    custom: { channel_id: 7, max_id: 99 },
                },
            }),
            'read',
        )

        expect(command).toMatchObject({
            pushType: 'background',
            priority: '5',
            payload: { aps: { 'content-available': 1 } },
        })
        expect(command?.collapseId?.length).toBeLessThanOrEqual(64)
    })

    it('does not create commands for dropped or unknown pushes', () => {
        const payload = parseTelegramPushPayload({
            data: { loc_key: 'MESSAGE_MUTED', custom: {} },
        })
        expect(mapper().map('drop', payload, 'drop')).toBeNull()
        expect(mapper().map('unknown', payload, 'unknown')).toBeNull()
    })
})

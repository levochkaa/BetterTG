import { Injectable } from '@nestjs/common'
import { createHash } from 'node:crypto'

import { SecretBoxService } from '@/security/secret-box.service'
import type { TelegramPushAction } from '@/telegram-web-push/classification/telegram-push-classifier'
import type { TelegramPushPayload } from '@/telegram-web-push/telegram-push-payload'

import type { ApnsCommand } from './apns.types'

const APNS_PAYLOAD_LIMIT = 4096

@Injectable()
export class ApnsPayloadMapperService {
    constructor(private readonly secretBox: SecretBoxService) {}

    map(
        action: TelegramPushAction,
        source: TelegramPushPayload,
        deliverySeed: string,
        now = new Date(),
    ): ApnsCommand | null {
        if (action === 'alert') return this.alert(source, deliverySeed, now)
        if (action === 'background') return this.background(source, deliverySeed, now)
        return null
    }

    private alert(source: TelegramPushPayload, deliverySeed: string, now: Date): ApnsCommand {
        const locArgs = source.data.loc_args.map((argument) => this.truncate(argument, 2048))
        const route = this.route(source)
        const payload: Record<string, unknown> = {
            aps: {
                alert: {
                    'loc-key': source.data.loc_key,
                    'loc-args': locArgs,
                },
                ...(source.data.custom.silent ? {} : { sound: 'default' }),
                'thread-id': route.threadId,
                category: 'TELEGRAM_MESSAGE',
            },
            tg: route.data,
        }
        this.fitPayload(payload, locArgs)

        return {
            deliveryId: this.deliveryId(deliverySeed),
            pushType: 'alert',
            priority: '10',
            expiration: String(Math.floor(now.getTime() / 1000) + 10 * 60),
            payload,
        }
    }

    private background(source: TelegramPushPayload, deliverySeed: string, now: Date): ApnsCommand {
        const route = this.route(source)
        return {
            deliveryId: this.deliveryId(deliverySeed),
            pushType: 'background',
            priority: '5',
            expiration: String(Math.floor(now.getTime() / 1000) + 60),
            collapseId: `state-${route.threadId}`.slice(0, 64),
            payload: {
                aps: { 'content-available': 1 },
                tg: {
                    ...route.data,
                    event: source.data.loc_key,
                    max_id: this.identifier(source.data.custom.max_id),
                    messages: source.data.custom.messages?.slice(0, 512),
                },
            },
        }
    }

    private route(source: TelegramPushPayload): {
        threadId: string
        data: Record<string, string>
    } {
        const custom = source.data.custom
        const peer = custom.channel_id
            ? { type: 'supergroup', id: this.identifier(custom.channel_id) }
            : custom.chat_id
              ? { type: 'basicGroup', id: this.identifier(custom.chat_id) }
              : { type: 'private', id: this.identifier(custom.from_id) }
        const account = this.identifier(source.data.user_id)
        const threadSeed = `${account}:${peer.type}:${peer.id}`

        return {
            threadId: this.secretBox.hashManagementToken(threadSeed).slice(0, 32),
            data: Object.fromEntries(
                Object.entries({
                    account,
                    peer_type: peer.type,
                    peer_id: peer.id,
                    message_id: this.identifier(custom.msg_id),
                    top_message_id: this.identifier(custom.top_msg_id),
                }).filter((entry): entry is [string, string] => Boolean(entry[1])),
            ),
        }
    }

    private fitPayload(payload: Record<string, unknown>, locArgs: string[]): void {
        while (Buffer.byteLength(JSON.stringify(payload)) > APNS_PAYLOAD_LIMIT) {
            let longestIndex = -1
            for (let index = 0; index < locArgs.length; index += 1) {
                if (
                    longestIndex < 0 ||
                    (locArgs[index]?.length ?? 0) > (locArgs[longestIndex]?.length ?? 0)
                ) {
                    longestIndex = index
                }
            }
            if (longestIndex < 0 || (locArgs[longestIndex]?.length ?? 0) === 0) {
                throw new Error('unable to fit APNs payload into 4096 bytes')
            }
            locArgs[longestIndex] = this.truncate(
                locArgs[longestIndex] ?? '',
                Math.max(0, (locArgs[longestIndex]?.length ?? 0) - 128),
            )
        }
    }

    private deliveryId(seed: string): string {
        const bytes = createHash('sha256').update(seed).digest().subarray(0, 16)
        bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x50
        bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80
        const hex = bytes.toString('hex')
        return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
    }

    private identifier(value: string | number | undefined): string {
        return value === undefined ? '' : String(value)
    }

    private truncate(value: string, maximumCharacters: number): string {
        const characters = Array.from(value)
        if (characters.length <= maximumCharacters) return value
        if (maximumCharacters <= 1) return characters.slice(0, maximumCharacters).join('')
        return `${characters.slice(0, maximumCharacters - 1).join('')}…`
    }
}

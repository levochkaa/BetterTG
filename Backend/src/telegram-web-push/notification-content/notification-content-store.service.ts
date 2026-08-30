import { Injectable } from '@nestjs/common'
import { randomBytes } from 'node:crypto'

import { RedisService } from '@/infrastructure/redis.service'
import type { TelegramPushPayload } from '@/telegram-web-push/telegram-push-payload'

const CONTENT_TTL_SECONDS = 15 * 60
const CONTENT_KEY_PREFIX = 'notification-content:'

@Injectable()
export class NotificationContentStoreService {
    constructor(private readonly redis: RedisService) {}

    async put(payload: TelegramPushPayload): Promise<string> {
        const token = randomBytes(32).toString('base64url')
        await this.redis.client.set(
            `${CONTENT_KEY_PREFIX}${token}`,
            JSON.stringify(payload),
            'EX',
            CONTENT_TTL_SECONDS,
        )
        return token
    }

    async take(token: string): Promise<TelegramPushPayload | null> {
        if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return null
        const value = (await this.redis.client.call('GETDEL', `${CONTENT_KEY_PREFIX}${token}`)) as
            string | null
        if (!value) return null
        return JSON.parse(value) as TelegramPushPayload
    }
}

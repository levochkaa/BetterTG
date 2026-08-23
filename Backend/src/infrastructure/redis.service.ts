import { HttpException, HttpStatus, Injectable, type OnModuleDestroy } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import Redis from 'ioredis'

import type { Environment } from '@/config/environment'

@Injectable()
export class RedisService implements OnModuleDestroy {
    readonly client: Redis

    constructor(config: ConfigService<Environment, true>) {
        this.client = new Redis(config.get('REDIS_URL', { infer: true }), {
            lazyConnect: true,
            maxRetriesPerRequest: 3,
            enableReadyCheck: true,
        })
    }

    async onModuleDestroy(): Promise<void> {
        if (this.client.status !== 'end') await this.client.quit()
    }

    async ping(): Promise<void> {
        if (this.client.status === 'wait') await this.client.connect()
        await this.client.ping()
    }

    async enforceRateLimit(key: string, limit: number, windowSeconds: number): Promise<void> {
        if (this.client.status === 'wait') await this.client.connect()
        const redisKey = `rate-limit:${key}`
        const results = await this.client
            .multi()
            .incr(redisKey)
            .expire(redisKey, windowSeconds)
            .exec()
        const count = Number(results?.[0]?.[1] ?? 0)
        if (count > limit) {
            throw new HttpException('rate limit exceeded', HttpStatus.TOO_MANY_REQUESTS)
        }
    }
}

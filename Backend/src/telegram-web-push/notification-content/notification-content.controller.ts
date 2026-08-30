import { Controller, Get, Header, Ip, NotFoundException, Param } from '@nestjs/common'
import { ApiExcludeController } from '@nestjs/swagger'

import { RedisService } from '@/infrastructure/redis.service'

import { NotificationContentStoreService } from './notification-content-store.service'

@ApiExcludeController()
@Controller('notification-content/v1')
export class NotificationContentController {
    constructor(
        private readonly store: NotificationContentStoreService,
        private readonly redis: RedisService,
    ) {}

    @Get(':token')
    @Header('Cache-Control', 'no-store')
    async take(@Param('token') token: string, @Ip() ipAddress: string): Promise<unknown> {
        await this.redis.enforceRateLimit(`notification-content:ip:${ipAddress}`, 120, 60)
        const payload = await this.store.take(token)
        if (!payload) throw new NotFoundException()
        return payload
    }
}

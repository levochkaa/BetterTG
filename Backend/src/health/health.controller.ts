import { Controller, Get, ServiceUnavailableException } from '@nestjs/common'
import { ApiExcludeController } from '@nestjs/swagger'
import { DataSource } from 'typeorm'

import { RedisService } from '@/infrastructure/redis.service'

@ApiExcludeController()
@Controller('health')
export class HealthController {
    constructor(
        private readonly dataSource: DataSource,
        private readonly redis: RedisService,
    ) {}

    @Get('live')
    live(): { status: 'ok' } {
        return { status: 'ok' }
    }

    @Get('ready')
    async ready(): Promise<{ status: 'ok' }> {
        try {
            await Promise.all([this.dataSource.query('SELECT 1'), this.redis.ping()])
            return { status: 'ok' }
        } catch {
            throw new ServiceUnavailableException('dependencies are unavailable')
        }
    }
}

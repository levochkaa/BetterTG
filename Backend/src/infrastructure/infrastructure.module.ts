import { BullModule } from '@nestjs/bullmq'
import { Global, Module } from '@nestjs/common'
import { ConfigModule, ConfigService } from '@nestjs/config'
import { TypeOrmModule } from '@nestjs/typeorm'

import type { Environment } from '@/config/environment'
import { validateEnvironment } from '@/config/environment'
import { redisOptionsFromUrl } from '@/config/redis-options'
import { ObservabilityModule } from '@/observability/observability.module'
import { SecurityModule } from '@/security/security.module'

import { RedisService } from './redis.service'

@Global()
@Module({
    imports: [
        ConfigModule.forRoot({
            isGlobal: true,
            cache: true,
            validate: validateEnvironment,
        }),
        TypeOrmModule.forRootAsync({
            inject: [ConfigService],
            useFactory: (config: ConfigService<Environment, true>) => ({
                type: 'postgres' as const,
                url: config.get('DATABASE_URL', { infer: true }),
                autoLoadEntities: true,
                synchronize: false,
                migrationsRun: false,
                logging: false,
            }),
        }),
        BullModule.forRootAsync({
            inject: [ConfigService],
            useFactory: (config: ConfigService<Environment, true>) => ({
                connection: redisOptionsFromUrl(config.get('REDIS_URL', { infer: true })),
            }),
        }),
        ObservabilityModule,
        SecurityModule,
    ],
    providers: [RedisService],
    exports: [RedisService, TypeOrmModule, BullModule, ObservabilityModule, SecurityModule],
})
export class InfrastructureModule {}

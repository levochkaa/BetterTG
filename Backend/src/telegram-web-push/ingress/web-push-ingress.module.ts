import { BullModule } from '@nestjs/bullmq'
import { Module } from '@nestjs/common'
import { TypeOrmModule } from '@nestjs/typeorm'

import { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'

import { TELEGRAM_WEB_PUSH_QUEUE } from '../web-push-job'
import { WebPushIngressController } from './web-push-ingress.controller'
import { WebPushIngressService } from './web-push-ingress.service'

@Module({
    imports: [
        TypeOrmModule.forFeature([TelegramPushSubscriptionEntity]),
        BullModule.registerQueue({ name: TELEGRAM_WEB_PUSH_QUEUE }),
    ],
    controllers: [WebPushIngressController],
    providers: [WebPushIngressService],
})
export class WebPushIngressModule {}

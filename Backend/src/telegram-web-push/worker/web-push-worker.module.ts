import { BullModule } from '@nestjs/bullmq'
import { Module } from '@nestjs/common'
import { TypeOrmModule } from '@nestjs/typeorm'

import { InstallationEntity } from '@/installations/installation.entity'
import { TelegramPushSubscriptionEntity } from '@/installations/telegram-push-subscription.entity'
import { NotificationsModule } from '@/notifications/notifications.module'

import { WebPushDecryptorService } from '../crypto/web-push-decryptor.service'
import { TELEGRAM_WEB_PUSH_QUEUE } from '../web-push-job'
import { WebPushProcessor } from './web-push.processor'

@Module({
    imports: [
        TypeOrmModule.forFeature([InstallationEntity, TelegramPushSubscriptionEntity]),
        BullModule.registerQueue({ name: TELEGRAM_WEB_PUSH_QUEUE }),
        NotificationsModule,
    ],
    providers: [WebPushDecryptorService, WebPushProcessor],
})
export class WebPushWorkerModule {}

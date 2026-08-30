import { Module } from '@nestjs/common'

import { NotificationContentController } from './notification-content.controller'

@Module({ controllers: [NotificationContentController] })
export class NotificationContentModule {}

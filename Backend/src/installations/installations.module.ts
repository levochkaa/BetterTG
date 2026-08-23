import { Module } from '@nestjs/common'
import { TypeOrmModule } from '@nestjs/typeorm'

import { AppAttestModule } from '@/app-attest/app-attest.module'

import { InstallationAuthGuard } from './installation-auth.guard'
import { InstallationEntity } from './installation.entity'
import { InstallationsController } from './installations.controller'
import { InstallationsService } from './installations.service'
import { TelegramPushSubscriptionEntity } from './telegram-push-subscription.entity'

@Module({
    imports: [
        TypeOrmModule.forFeature([InstallationEntity, TelegramPushSubscriptionEntity]),
        AppAttestModule,
    ],
    controllers: [InstallationsController],
    providers: [InstallationsService, InstallationAuthGuard],
    exports: [InstallationsService, TypeOrmModule],
})
export class InstallationsModule {}

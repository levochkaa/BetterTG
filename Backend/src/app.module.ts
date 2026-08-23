import { Module } from '@nestjs/common'

import { HealthModule } from '@/health/health.module'
import { InfrastructureModule } from '@/infrastructure/infrastructure.module'
import { InstallationsModule } from '@/installations/installations.module'
import { WebPushIngressModule } from '@/telegram-web-push/ingress/web-push-ingress.module'

@Module({
    imports: [InfrastructureModule, HealthModule, InstallationsModule, WebPushIngressModule],
})
export class AppModule {}

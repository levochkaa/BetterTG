import { Module } from '@nestjs/common'

import { InfrastructureModule } from '@/infrastructure/infrastructure.module'
import { WebPushWorkerModule } from '@/telegram-web-push/worker/web-push-worker.module'

@Module({ imports: [InfrastructureModule, WebPushWorkerModule] })
export class WorkerModule {}

import 'reflect-metadata'

import { NestFactory } from '@nestjs/core'

import { StructuredLogger } from '@/common/structured-logger'
import { validateEnvironment } from '@/config/environment'
import { createTelemetry } from '@/observability/telemetry'
import { WorkerModule } from '@/worker.module'

async function bootstrap(): Promise<void> {
    const environment = validateEnvironment(process.env)
    const telemetry = createTelemetry(environment)
    telemetry.start()
    const logger = new StructuredLogger(environment.LOG_LEVEL)

    try {
        const application = await NestFactory.createApplicationContext(WorkerModule, { logger })
        application.enableShutdownHooks()
        logger.log({ event: 'worker.started' })
    } catch (error) {
        logger.error({ event: 'worker.start_failed', error })
        await telemetry.shutdown()
        throw error
    }
}

void bootstrap()

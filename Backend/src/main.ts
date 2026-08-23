import 'reflect-metadata'

import { NestFactory } from '@nestjs/core'
import type { NestExpressApplication } from '@nestjs/platform-express'

import { AppModule } from '@/app.module'
import { configureApplication } from '@/bootstrap'
import { StructuredLogger } from '@/common/structured-logger'
import { validateEnvironment } from '@/config/environment'
import { createTelemetry } from '@/observability/telemetry'

async function bootstrap(): Promise<void> {
    const environment = validateEnvironment(process.env)
    const telemetry = createTelemetry(environment)
    telemetry.start()

    const logger = new StructuredLogger(environment.LOG_LEVEL)
    const app = await NestFactory.create<NestExpressApplication>(AppModule, {
        rawBody: true,
        bodyParser: false,
        logger,
    })
    configureApplication(app)
    app.enableShutdownHooks()

    try {
        await app.listen(environment.PORT, '0.0.0.0')
        logger.log({ event: 'api.started', port: environment.PORT })
    } catch (error) {
        logger.error({ event: 'api.start_failed', error })
        await telemetry.shutdown()
        throw error
    }
}

void bootstrap()

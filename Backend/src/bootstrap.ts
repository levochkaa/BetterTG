import { ValidationPipe } from '@nestjs/common'
import { ConfigService } from '@nestjs/config'
import type { NestExpressApplication } from '@nestjs/platform-express'
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger'
import { json, raw, type NextFunction, type Request, type Response } from 'express'
import helmet from 'helmet'

import type { Environment } from '@/config/environment'

export function configureApplication(app: NestExpressApplication): void {
    const config = app.get(ConfigService<Environment, true>)

    app.use(helmet())
    const webPushBodyParser = raw({ type: () => true, limit: '8kb', inflate: false })
    app.use('/webpush/v1', (request: Request, response: Response, next: NextFunction) => {
        // Express treats Web Push's `Content-Encoding: aes128gcm` as HTTP compression.
        // Hide it only while collecting opaque ciphertext, then restore it for the controller.
        const contentEncoding = request.headers['content-encoding']
        delete request.headers['content-encoding']
        webPushBodyParser(request, response, (error) => {
            if (contentEncoding !== undefined) request.headers['content-encoding'] = contentEncoding
            next(error)
        })
    })
    app.use(
        json({
            limit: '64kb',
            verify: (request, _response, body) => {
                const rawRequest = request as Request & { rawBody?: Buffer }
                rawRequest.rawBody = Buffer.from(body)
            },
        }),
    )
    app.useGlobalPipes(
        new ValidationPipe({
            transform: true,
            whitelist: true,
            forbidNonWhitelisted: true,
        }),
    )

    const httpAdapter = app.getHttpAdapter().getInstance() as {
        set: (name: string, value: unknown) => void
    }
    httpAdapter.set('trust proxy', true)
    httpAdapter.set('etag', false)

    if (config.get('SWAGGER_ENABLED', { infer: true })) {
        const document = SwaggerModule.createDocument(
            app,
            new DocumentBuilder()
                .setTitle('BetterTG Backend')
                .setVersion('1')
                .addBearerAuth()
                .build(),
        )
        SwaggerModule.setup('api/docs', app, document)
    }
}

import {
    Controller,
    Headers,
    HttpCode,
    Ip,
    Param,
    Post,
    type RawBodyRequest,
    Req,
    Res,
} from '@nestjs/common'
import { ApiExcludeController } from '@nestjs/swagger'
import type { Request, Response } from 'express'

import { WebPushIngressService } from './web-push-ingress.service'

@ApiExcludeController()
@Controller('webpush/v1')
export class WebPushIngressController {
    constructor(private readonly ingress: WebPushIngressService) {}

    @Post(':capabilityToken')
    @HttpCode(201)
    async accept(
        @Param('capabilityToken') capabilityToken: string,
        @Headers('content-encoding') contentEncoding: string | undefined,
        @Headers('encryption') encryption: string | undefined,
        @Headers('crypto-key') cryptoKey: string | undefined,
        @Ip() ipAddress: string,
        @Req() request: RawBodyRequest<Request>,
        @Res({ passthrough: true }) response: Response,
    ): Promise<void> {
        const body =
            request.rawBody ?? (Buffer.isBuffer(request.body) ? request.body : Buffer.alloc(0))
        const digest = await this.ingress.accept(
            capabilityToken,
            body,
            { contentEncoding, encryption, cryptoKey },
            ipAddress,
        )
        response.setHeader('Location', `/webpush/receipts/${digest}`)
    }
}

import {
    Body,
    Controller,
    Delete,
    Headers,
    HttpCode,
    Param,
    Post,
    Put,
    type RawBodyRequest,
    Req,
    UnauthorizedException,
    UseGuards,
} from '@nestjs/common'
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger'
import type { Request } from 'express'

import { AppAttestService } from '@/app-attest/app-attest.service'

import { CurrentInstallation } from './current-installation.decorator'
import { InstallationAuthGuard } from './installation-auth.guard'
import type { InstallationEntity } from './installation.entity'
import {
    CreateInstallationDto,
    type InstallationCreatedResponse,
    type TelegramSubscriptionResponse,
    UpdateApnsTokenDto,
} from './installations.dto'
import { InstallationsService } from './installations.service'

const IDEMPOTENCY_KEY_PATTERN =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

@ApiTags('Installations')
@Controller('api/v1/installations')
export class InstallationsController {
    constructor(
        private readonly service: InstallationsService,
        private readonly appAttest: AppAttestService,
    ) {}

    @Post()
    async create(
        @Body() dto: CreateInstallationDto,
        @Headers('idempotency-key') idempotencyKey: string | undefined,
        @Headers('x-app-attest-key-id') appAttestKeyId: string | undefined,
        @Headers('x-app-attest-assertion') assertion: string | undefined,
        @Req() request: RawBodyRequest<Request>,
    ): Promise<InstallationCreatedResponse> {
        if (!idempotencyKey || !IDEMPOTENCY_KEY_PATTERN.test(idempotencyKey)) {
            throw new UnauthorizedException('valid Idempotency-Key is required')
        }

        const cached = await this.service.cachedCreation(idempotencyKey)
        if (cached) return cached
        const verifiedKeyId = await this.appAttest.verifyRequest(
            request.rawBody,
            dto.attestChallenge,
            appAttestKeyId,
            assertion,
        )
        return this.service.create(dto, verifiedKeyId, idempotencyKey)
    }

    @Put(':id/apns-token')
    @UseGuards(InstallationAuthGuard)
    @ApiBearerAuth()
    @HttpCode(204)
    async updateApnsToken(
        @CurrentInstallation() installation: InstallationEntity,
        @Body() dto: UpdateApnsTokenDto,
    ): Promise<void> {
        await this.service.updateApnsToken(installation, dto)
    }

    @Post(':id/telegram-subscriptions')
    @UseGuards(InstallationAuthGuard)
    @ApiBearerAuth()
    rotateSubscription(
        @CurrentInstallation() installation: InstallationEntity,
    ): Promise<TelegramSubscriptionResponse> {
        return this.service.rotateSubscription(installation)
    }

    @Delete(':id/telegram-subscriptions/:subscriptionId')
    @UseGuards(InstallationAuthGuard)
    @ApiBearerAuth()
    @HttpCode(204)
    async deleteSubscription(
        @CurrentInstallation() installation: InstallationEntity,
        @Param('subscriptionId') subscriptionId: string,
    ): Promise<void> {
        await this.service.deleteSubscription(installation.id, subscriptionId)
    }

    @Delete(':id')
    @UseGuards(InstallationAuthGuard)
    @ApiBearerAuth()
    @HttpCode(204)
    async deleteInstallation(
        @CurrentInstallation() installation: InstallationEntity,
    ): Promise<void> {
        await this.service.deleteInstallation(installation.id)
    }
}

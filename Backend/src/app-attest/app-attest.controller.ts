import { Body, Controller, Get, HttpCode, Ip, Post } from '@nestjs/common'
import { ApiExcludeEndpoint, ApiTags } from '@nestjs/swagger'

import { VerifyAttestationDto } from './app-attest.dto'
import { AppAttestService } from './app-attest.service'

@ApiTags('App Attest')
@Controller('api/v1/app-attest')
export class AppAttestController {
    constructor(private readonly appAttest: AppAttestService) {}

    @Get('challenge')
    @ApiExcludeEndpoint()
    challenge(@Ip() ipAddress: string): Promise<{ challenge: string }> {
        return this.appAttest.issueChallenge(ipAddress)
    }

    @Post('attestations')
    @HttpCode(204)
    @ApiExcludeEndpoint()
    async verify(@Body() dto: VerifyAttestationDto): Promise<void> {
        await this.appAttest.registerAttestation(dto)
    }
}

import { IsIn, IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator'

import type { ApnsEnvironment } from './installation.entity'

export class CreateInstallationDto {
    @Matches(/^[0-9a-fA-F]{64,200}$/)
    apnsToken!: string

    @IsIn(['sandbox', 'production'])
    apnsEnvironment!: ApnsEnvironment

    @IsOptional()
    @IsString()
    @MaxLength(64)
    appVersion?: string

    @IsOptional()
    @IsString()
    @MaxLength(64)
    osVersion?: string

    @IsOptional()
    @IsString()
    @Length(20, 128)
    attestChallenge?: string
}

export class UpdateApnsTokenDto {
    @Matches(/^[0-9a-fA-F]{64,200}$/)
    apnsToken!: string

    @IsIn(['sandbox', 'production'])
    apnsEnvironment!: ApnsEnvironment

    @IsOptional()
    @IsString()
    @MaxLength(64)
    appVersion?: string

    @IsOptional()
    @IsString()
    @MaxLength(64)
    osVersion?: string
}

export interface InstallationCreatedResponse {
    installationId: string
    managementSecret: string
}

export interface TelegramSubscriptionResponse {
    subscriptionId: string
    endpoint: string
    p256dhBase64url: string
    authBase64url: string
}

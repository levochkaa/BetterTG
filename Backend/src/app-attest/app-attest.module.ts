import { Module } from '@nestjs/common'
import { TypeOrmModule } from '@nestjs/typeorm'

import { AppAttestController } from './app-attest.controller'
import { AppAttestKeyEntity } from './app-attest-key.entity'
import { AppAttestService } from './app-attest.service'

@Module({
    imports: [TypeOrmModule.forFeature([AppAttestKeyEntity])],
    controllers: [AppAttestController],
    providers: [AppAttestService],
    exports: [AppAttestService, TypeOrmModule],
})
export class AppAttestModule {}

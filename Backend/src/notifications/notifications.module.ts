import { Module } from '@nestjs/common'

import { ApnsClientService } from './apns/apns-client.service'
import { ApnsPayloadMapperService } from './apns/apns-payload-mapper.service'

@Module({
    providers: [ApnsClientService, ApnsPayloadMapperService],
    exports: [ApnsClientService, ApnsPayloadMapperService],
})
export class NotificationsModule {}

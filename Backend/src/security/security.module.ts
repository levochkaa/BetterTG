import { Global, Module } from '@nestjs/common'

import { SecretBoxService } from './secret-box.service'

@Global()
@Module({
    providers: [SecretBoxService],
    exports: [SecretBoxService],
})
export class SecurityModule {}

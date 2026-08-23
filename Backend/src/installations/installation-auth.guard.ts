import {
    type CanActivate,
    type ExecutionContext,
    Injectable,
    UnauthorizedException,
} from '@nestjs/common'
import { InjectRepository } from '@nestjs/typeorm'
import { Repository } from 'typeorm'

import { SecretBoxService } from '@/security/secret-box.service'

import { InstallationEntity } from './installation.entity'
import type { InstallationRequest } from './installation-request'

@Injectable()
export class InstallationAuthGuard implements CanActivate {
    constructor(
        @InjectRepository(InstallationEntity)
        private readonly installations: Repository<InstallationEntity>,
        private readonly secretBox: SecretBoxService,
    ) {}

    async canActivate(context: ExecutionContext): Promise<boolean> {
        const request = context.switchToHttp().getRequest<InstallationRequest>()
        const rawInstallationId = request.params.id
        const installationId = Array.isArray(rawInstallationId)
            ? rawInstallationId[0]
            : rawInstallationId
        const authorization = request.header('authorization')
        const token = authorization?.match(/^Bearer ([A-Za-z0-9_-]{40,})$/)?.[1]
        if (!installationId || !token) throw new UnauthorizedException()

        const installation = await this.installations.findOneBy({ id: installationId })
        if (!installation) throw new UnauthorizedException()
        const actualHash = this.secretBox.hashManagementToken(token)
        if (!this.secretBox.secureHashMatches(installation.managementSecretHash, actualHash)) {
            throw new UnauthorizedException()
        }

        request.installation = installation
        return true
    }
}

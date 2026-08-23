import { createParamDecorator, type ExecutionContext } from '@nestjs/common'

import type { InstallationRequest } from './installation-request'

export const CurrentInstallation = createParamDecorator(
    (_: unknown, context: ExecutionContext) =>
        context.switchToHttp().getRequest<InstallationRequest>().installation,
)

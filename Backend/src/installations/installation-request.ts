import type { Request } from 'express'

import type { InstallationEntity } from './installation.entity'

export interface InstallationRequest extends Request {
    installation: InstallationEntity
}

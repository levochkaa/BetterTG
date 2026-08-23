import type { ApnsEnvironment } from '@/installations/installation.entity'

export type ApnsPushType = 'alert' | 'background'

export interface ApnsRequest {
    deviceToken: string
    environment: ApnsEnvironment
    deliveryId: string
    topic: string
    pushType: ApnsPushType
    priority: '5' | '10'
    expiration: string
    collapseId?: string
    payload: Record<string, unknown>
}

export type ApnsResult =
    | { kind: 'success'; status: 200 }
    | { kind: 'retryable'; status?: number; reason?: string }
    | { kind: 'invalid-token'; status: number; reason: string }
    | { kind: 'permanent'; status?: number; reason?: string }

export type ApnsCommand = Omit<ApnsRequest, 'deviceToken' | 'environment' | 'topic'>

export const TELEGRAM_WEB_PUSH_QUEUE = 'telegram-web-push'

export type WebPushContentEncoding = 'aes128gcm' | 'aesgcm'

export interface WebPushEncryptionMetadata {
    contentEncoding: WebPushContentEncoding
    saltBase64url?: string
    senderPublicKeyBase64url?: string
    recordSize?: number
}

export interface TelegramWebPushJob {
    subscriptionId: string
    ciphertextBase64: string
    encryption: WebPushEncryptionMetadata
    receivedAt: string
}

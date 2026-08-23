export const TELEGRAM_WEB_PUSH_QUEUE = 'telegram-web-push'

export interface TelegramWebPushJob {
    subscriptionId: string
    ciphertextBase64: string
    receivedAt: string
}

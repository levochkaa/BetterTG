import { TELEGRAM_VISIBLE_PUSH_KEYS } from './telegram-push-catalog.generated'

export type TelegramPushAction = 'alert' | 'background' | 'drop' | 'call' | 'unknown'

const backgroundKeys = new Set([
    'MESSAGE_DELETED',
    'READ_HISTORY',
    'READ_REACTION',
    'READ_STORIES',
    'STORY_DELETED',
])

const droppedKeys = new Set(['DC_UPDATE', 'GEO_LIVE_PENDING', 'MESSAGE_MUTED', 'SESSION_REVOKE'])

const callKeys = new Set(['PHONE_CALL_REQUEST'])

export function classifyTelegramPush(locKey: string): TelegramPushAction {
    if (backgroundKeys.has(locKey)) return 'background'
    if (droppedKeys.has(locKey)) return 'drop'
    if (callKeys.has(locKey)) return 'call'
    if (TELEGRAM_VISIBLE_PUSH_KEYS.has(locKey)) return 'alert'
    return 'unknown'
}

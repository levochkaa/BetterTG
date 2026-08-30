import { z } from 'zod'

const identifier = z.union([z.string().max(32), z.number().int().safe()])
const telegramFlag = z
    .union([z.boolean(), z.enum(['0', '1']), z.literal(0), z.literal(1)])
    .transform((value): '0' | '1' => (value === true || value === 1 || value === '1' ? '1' : '0'))
const customSchema = z
    .object({
        msg_id: identifier.optional(),
        channel_id: identifier.optional(),
        chat_id: identifier.optional(),
        from_id: identifier.optional(),
        chat_from_broadcast_id: identifier.optional(),
        chat_from_group_id: identifier.optional(),
        chat_from_id: identifier.optional(),
        top_msg_id: identifier.optional(),
        silent: telegramFlag.optional(),
        mention: telegramFlag.optional(),
        max_id: identifier.optional(),
        messages: z.string().max(1024).optional(),
    })
    .passthrough()

const dataSchema = z
    .object({
        loc_key: z.string().regex(/^[A-Z0-9_]+$/),
        loc_args: z.array(z.string().max(2048)).max(12).default([]),
        user_id: identifier.optional(),
        sound: z.string().max(128).optional(),
        message: z.string().max(3072).optional(),
        title: z.string().max(512).optional(),
        description: z.string().max(3072).optional(),
        custom: customSchema.default({}),
    })
    .passthrough()

const payloadSchema = z.object({ data: dataSchema }).passthrough()

export type TelegramPushPayload = z.infer<typeof payloadSchema>

export function parseTelegramPushPayload(value: unknown): TelegramPushPayload {
    if (value !== null && typeof value === 'object' && Object.hasOwn(value, 'data')) {
        return payloadSchema.parse(value)
    }
    return { data: dataSchema.parse(value) }
}

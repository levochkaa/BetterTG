import { z } from 'zod'

const booleanString = z.enum(['true', 'false']).transform((value) => value === 'true')

const environmentSchema = z
    .object({
        NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
        PORT: z.coerce.number().int().min(1).max(65_535).default(3000),
        PUBLIC_BASE_URL: z.string().url().default('http://localhost:8080'),
        DATABASE_URL: z
            .string()
            .url()
            .default('postgresql://bettertg:bettertg@localhost:5433/bettertg'),
        REDIS_URL: z.string().url().default('redis://localhost:6380/0'),
        BUNDLE_ID: z.string().min(3).default('com.levochkaaa.BetterTG'),
        APPLE_TEAM_ID: z.string().min(1).default('7Z2WHPKU8W'),
        APPLE_KEY_ID: z.string().default(''),
        APPLE_AUTH_KEY: z.string().default(''),
        APNS_DRY_RUN: booleanString.default(true),
        APNS_SANDBOX_URL: z.string().url().default('https://api.sandbox.push.apple.com'),
        APNS_PRODUCTION_URL: z.string().url().default('https://api.push.apple.com'),
        APNS_REQUEST_TIMEOUT_MS: z.coerce.number().int().min(100).max(60_000).default(10_000),
        ENCRYPTION_CURRENT_KEY_ID: z.string().min(1).default('dev'),
        ENCRYPTION_KEYS: z
            .string()
            .min(1)
            .default('dev:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
        MANAGEMENT_TOKEN_PEPPER: z
            .string()
            .min(1)
            .default('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
        APP_ATTEST_MODE: z.enum(['enforce', 'bypass']).default('bypass'),
        APP_ATTEST_ALLOW_DEVELOPMENT: booleanString.default(true),
        OTEL_EXPORTER_OTLP_ENDPOINT: z.string().default(''),
        LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
        SWAGGER_ENABLED: booleanString.default(true),
    })
    .superRefine((environment, context) => {
        if (environment.NODE_ENV !== 'production') return

        if (!environment.PUBLIC_BASE_URL.startsWith('https://')) {
            context.addIssue({
                code: 'custom',
                path: ['PUBLIC_BASE_URL'],
                message: 'production PUBLIC_BASE_URL must use HTTPS',
            })
        }
        if (environment.APP_ATTEST_MODE !== 'enforce') {
            context.addIssue({
                code: 'custom',
                path: ['APP_ATTEST_MODE'],
                message: 'production requires App Attest enforcement',
            })
        }
        if (environment.ENCRYPTION_CURRENT_KEY_ID === 'dev') {
            context.addIssue({
                code: 'custom',
                path: ['ENCRYPTION_CURRENT_KEY_ID'],
                message: 'production must not use the development encryption key',
            })
        }
        if (
            !environment.APNS_DRY_RUN &&
            (!environment.APPLE_KEY_ID || !environment.APPLE_AUTH_KEY)
        ) {
            context.addIssue({
                code: 'custom',
                path: ['APPLE_AUTH_KEY'],
                message: 'APNs credentials are required when dry-run mode is disabled',
            })
        }
        if (
            environment.APNS_SANDBOX_URL !== 'https://api.sandbox.push.apple.com' ||
            environment.APNS_PRODUCTION_URL !== 'https://api.push.apple.com'
        ) {
            context.addIssue({
                code: 'custom',
                path: ['APNS_PRODUCTION_URL'],
                message: 'production APNs endpoints must use Apple hosts',
            })
        }
    })

export type Environment = z.infer<typeof environmentSchema>

export function validateEnvironment(input: Record<string, unknown>): Environment {
    return environmentSchema.parse(input)
}

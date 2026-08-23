import type { LoggerService, LogLevel } from '@nestjs/common'

import type { Environment } from '@/config/environment'

const levels: Record<Environment['LOG_LEVEL'], number> = {
    debug: 10,
    info: 20,
    warn: 30,
    error: 40,
}

const secretKeyPattern =
    /(token|secret|password|authorization|payload|loc_?args|ciphertext|private_?key)/i

export function redactForLog(value: unknown, seen = new WeakSet<object>()): unknown {
    if (value instanceof Error) {
        return { name: value.name, message: value.message, stack: value.stack }
    }
    if (Array.isArray(value)) return value.map((item) => redactForLog(item, seen))
    if (!value || typeof value !== 'object') return value
    if (seen.has(value)) return '[Circular]'
    seen.add(value)

    return Object.fromEntries(
        Object.entries(value).map(([key, child]) => [
            key,
            secretKeyPattern.test(key) ? '[REDACTED]' : redactForLog(child, seen),
        ]),
    )
}

export class StructuredLogger implements LoggerService {
    constructor(private readonly minimumLevel: Environment['LOG_LEVEL']) {}

    log(message: unknown, ...optionalParameters: unknown[]): void {
        this.write('info', message, optionalParameters)
    }

    error(message: unknown, ...optionalParameters: unknown[]): void {
        this.write('error', message, optionalParameters)
    }

    warn(message: unknown, ...optionalParameters: unknown[]): void {
        this.write('warn', message, optionalParameters)
    }

    debug(message: unknown, ...optionalParameters: unknown[]): void {
        this.write('debug', message, optionalParameters)
    }

    verbose(message: unknown, ...optionalParameters: unknown[]): void {
        this.write('debug', message, optionalParameters)
    }

    fatal(message: unknown, ...optionalParameters: unknown[]): void {
        this.write('error', message, optionalParameters)
    }

    setLogLevels(_: LogLevel[]): void {}

    private write(
        level: Environment['LOG_LEVEL'],
        message: unknown,
        optionalParameters: unknown[],
    ): void {
        if (levels[level] < levels[this.minimumLevel]) return

        const entry = {
            timestamp: new Date().toISOString(),
            level,
            ...(typeof message === 'object' && message !== null
                ? (redactForLog(message) as Record<string, unknown>)
                : { message: String(message) }),
            ...(optionalParameters.length > 0
                ? { context: redactForLog(optionalParameters) }
                : undefined),
        }
        process.stdout.write(`${JSON.stringify(entry)}\n`)
    }
}

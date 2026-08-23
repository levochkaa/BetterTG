import type { ConnectionOptions } from 'bullmq'

export function redisOptionsFromUrl(redisUrl: string): ConnectionOptions {
    const url = new URL(redisUrl)
    const database = url.pathname.length > 1 ? Number(url.pathname.slice(1)) : 0

    return {
        host: url.hostname,
        port: url.port ? Number(url.port) : 6379,
        username: url.username || undefined,
        password: url.password || undefined,
        db: Number.isFinite(database) ? database : 0,
        tls: url.protocol === 'rediss:' ? {} : undefined,
        maxRetriesPerRequest: null,
        enableReadyCheck: true,
    }
}

import { afterEach, describe, expect, it } from 'bun:test'
import { ConfigService } from '@nestjs/config'
import { generateKeyPairSync } from 'node:crypto'
import http2, { type Http2Server, type ServerHttp2Stream } from 'node:http2'

import type { Environment } from '@/config/environment'
import type { MetricsService } from '@/observability/metrics.service'

import { ApnsClientService } from './apns-client.service'

const servers: Http2Server[] = []
const clients: ApnsClientService[] = []

afterEach(async () => {
    for (const client of clients.splice(0)) client.onModuleDestroy()
    await Promise.all(
        servers
            .splice(0)
            .map((server) => new Promise<void>((resolve) => server.close(() => resolve()))),
    )
})

describe('ApnsClientService', () => {
    it('sends APNs headers and reuses a Bun HTTP/2 client session', async () => {
        const server = http2.createServer()
        servers.push(server)
        let sessions = 0
        let requests = 0
        let lastHeaders: http2.IncomingHttpHeaders = {}
        let lastBody = ''
        server.on('session', () => {
            sessions += 1
        })
        server.on('stream', (stream: ServerHttp2Stream, headers) => {
            requests += 1
            lastHeaders = headers
            lastBody = ''
            stream.setEncoding('utf8')
            stream.on('data', (chunk: string) => {
                lastBody += chunk
            })
            stream.on('end', () => {
                stream.respond({ ':status': 200 })
                stream.end()
            })
        })
        await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
        const address = server.address()
        if (!address || typeof address === 'string') throw new Error('test server has no port')

        const { privateKey } = generateKeyPairSync('ec', {
            namedCurve: 'P-256',
            privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
            publicKeyEncoding: { type: 'spki', format: 'pem' },
        })
        const endpoint = `http://127.0.0.1:${address.port}`
        const service = new ApnsClientService(
            new ConfigService<Environment, true>({
                APNS_DRY_RUN: false,
                APNS_SANDBOX_URL: endpoint,
                APNS_PRODUCTION_URL: endpoint,
                APNS_REQUEST_TIMEOUT_MS: 1000,
                APPLE_KEY_ID: 'ABCDEFGHIJ',
                APPLE_TEAM_ID: 'KLMNOPQRST',
                APPLE_AUTH_KEY: privateKey,
            } as Environment),
            { apnsConnectionEvents: { add: () => undefined } } as unknown as MetricsService,
        )
        clients.push(service)
        const request = {
            deviceToken: 'a'.repeat(64),
            environment: 'sandbox' as const,
            deliveryId: '123e4567-e89b-52d3-a456-426614174000',
            topic: 'com.example.App',
            pushType: 'alert' as const,
            priority: '10' as const,
            expiration: '0',
            payload: { aps: { alert: 'Hello' } },
        }

        expect(await service.send(request)).toEqual({ kind: 'success', status: 200 })
        expect(await service.send(request)).toEqual({ kind: 'success', status: 200 })
        expect(sessions).toBe(1)
        expect(requests).toBe(2)
        expect(lastHeaders['apns-topic']).toBe('com.example.App')
        expect(lastHeaders['apns-push-type']).toBe('alert')
        expect(String(lastHeaders.authorization)).toStartWith('bearer ')
        expect(JSON.parse(lastBody)).toEqual(request.payload)
    })

    it('classifies retryable and invalid-token responses', async () => {
        const server = http2.createServer()
        servers.push(server)
        const responses = [
            { status: 503, reason: 'Shutdown' },
            { status: 403, reason: 'ExpiredProviderToken' },
            { status: 410, reason: 'Unregistered' },
        ]
        server.on('stream', (stream: ServerHttp2Stream) => {
            const response = responses.shift()
            stream.on('data', () => undefined)
            stream.on('end', () => {
                stream.respond({ ':status': response?.status ?? 500 })
                stream.end(JSON.stringify({ reason: response?.reason }))
            })
        })
        await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve))
        const address = server.address()
        if (!address || typeof address === 'string') throw new Error('test server has no port')
        const { privateKey } = generateKeyPairSync('ec', {
            namedCurve: 'P-256',
            privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
            publicKeyEncoding: { type: 'spki', format: 'pem' },
        })
        const endpoint = `http://127.0.0.1:${address.port}`
        const service = new ApnsClientService(
            new ConfigService<Environment, true>({
                APNS_DRY_RUN: false,
                APNS_SANDBOX_URL: endpoint,
                APNS_PRODUCTION_URL: endpoint,
                APNS_REQUEST_TIMEOUT_MS: 1000,
                APPLE_KEY_ID: 'ABCDEFGHIJ',
                APPLE_TEAM_ID: 'KLMNOPQRST',
                APPLE_AUTH_KEY: privateKey,
            } as Environment),
            { apnsConnectionEvents: { add: () => undefined } } as unknown as MetricsService,
        )
        clients.push(service)
        const request = {
            deviceToken: 'a'.repeat(64),
            environment: 'production' as const,
            deliveryId: '123e4567-e89b-52d3-a456-426614174000',
            topic: 'com.example.App',
            pushType: 'alert' as const,
            priority: '10' as const,
            expiration: '0',
            payload: { aps: { alert: 'Hello' } },
        }

        expect(await service.send(request)).toEqual({
            kind: 'retryable',
            status: 503,
            reason: 'Shutdown',
        })
        expect(await service.send(request)).toEqual({
            kind: 'retryable',
            status: 403,
            reason: 'ExpiredProviderToken',
        })
        expect(await service.send(request)).toEqual({
            kind: 'invalid-token',
            status: 410,
            reason: 'Unregistered',
        })
    })
})

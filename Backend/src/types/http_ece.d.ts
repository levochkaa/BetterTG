declare module 'http_ece' {
    import type { ECDH } from 'node:crypto'

    interface EncryptionParameters {
        version?: 'aes128gcm' | 'aesgcm'
        privateKey: ECDH
        dh?: Buffer
        authSecret: Buffer
        salt?: Buffer
        rs?: number
        pad?: number
    }

    export function decrypt(buffer: Buffer, parameters: EncryptionParameters): Buffer
    export function encrypt(buffer: Buffer, parameters: EncryptionParameters): Buffer
}

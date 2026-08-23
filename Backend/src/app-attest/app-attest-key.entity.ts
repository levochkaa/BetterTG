import { Column, CreateDateColumn, Entity, PrimaryColumn, UpdateDateColumn } from 'typeorm'

@Entity({ name: 'app_attest_keys' })
export class AppAttestKeyEntity {
    @PrimaryColumn({ name: 'key_id', type: 'varchar', length: 255 })
    keyId!: string

    @Column({ name: 'public_key_pem', type: 'text' })
    publicKeyPem!: string

    @Column({ name: 'receipt_encrypted', type: 'text' })
    receiptEncrypted!: string

    @Column({ name: 'sign_count', type: 'integer', default: 0 })
    signCount!: number

    @Column({ type: 'boolean', default: false })
    revoked!: boolean

    @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
    createdAt!: Date

    @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
    updatedAt!: Date
}

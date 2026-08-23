import {
    Column,
    CreateDateColumn,
    Entity,
    Index,
    JoinColumn,
    ManyToOne,
    PrimaryColumn,
    type Relation,
    UpdateDateColumn,
} from 'typeorm'

import { InstallationEntity } from './installation.entity'

@Entity({ name: 'telegram_push_subscriptions' })
export class TelegramPushSubscriptionEntity {
    @PrimaryColumn('uuid')
    id!: string

    @Index({ unique: true })
    @Column({ name: 'endpoint_token_hash', type: 'char', length: 64 })
    endpointTokenHash!: string

    @Column({ name: 'p256dh_public_key', type: 'varchar', length: 128 })
    p256dhPublicKey!: string

    @Column({ name: 'p256dh_private_key_encrypted', type: 'text' })
    p256dhPrivateKeyEncrypted!: string

    @Column({ name: 'auth_secret_encrypted', type: 'text' })
    authSecretEncrypted!: string

    @Column({ name: 'last_received_at', type: 'timestamptz', nullable: true })
    lastReceivedAt!: Date | null

    @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
    createdAt!: Date

    @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
    updatedAt!: Date

    @Column({ name: 'installation_id', type: 'uuid' })
    installationId!: string

    @ManyToOne(() => InstallationEntity, (installation) => installation.subscriptions, {
        onDelete: 'CASCADE',
    })
    @JoinColumn({ name: 'installation_id' })
    installation!: Relation<InstallationEntity>
}

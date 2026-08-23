import {
    Column,
    CreateDateColumn,
    Entity,
    Index,
    OneToMany,
    PrimaryColumn,
    type Relation,
    UpdateDateColumn,
} from 'typeorm'

import { TelegramPushSubscriptionEntity } from './telegram-push-subscription.entity'

export type ApnsEnvironment = 'sandbox' | 'production'
export type InstallationStatus = 'active' | 'disabled'

@Entity({ name: 'installations' })
export class InstallationEntity {
    @PrimaryColumn('uuid')
    id!: string

    @Column({ name: 'management_secret_hash', type: 'char', length: 64 })
    managementSecretHash!: string

    @Column({ name: 'apns_token_encrypted', type: 'text' })
    apnsTokenEncrypted!: string

    @Column({ name: 'apns_environment', type: 'varchar', length: 16 })
    apnsEnvironment!: ApnsEnvironment

    @Column({ name: 'bundle_id', type: 'varchar', length: 255 })
    bundleId!: string

    @Column({ name: 'app_attest_key_id', type: 'varchar', length: 255, nullable: true })
    appAttestKeyId!: string | null

    @Column({ name: 'app_version', type: 'varchar', length: 64, nullable: true })
    appVersion!: string | null

    @Column({ name: 'os_version', type: 'varchar', length: 64, nullable: true })
    osVersion!: string | null

    @Index()
    @Column({ type: 'varchar', length: 16, default: 'active' })
    status!: InstallationStatus

    @Column({ name: 'last_seen_at', type: 'timestamptz' })
    lastSeenAt!: Date

    @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
    createdAt!: Date

    @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
    updatedAt!: Date

    @OneToMany(() => TelegramPushSubscriptionEntity, (subscription) => subscription.installation)
    subscriptions!: Relation<TelegramPushSubscriptionEntity[]>
}

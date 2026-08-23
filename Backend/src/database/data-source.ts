import 'dotenv/config'
import 'reflect-metadata'

import { DataSource } from 'typeorm'

import { validateEnvironment } from '@/config/environment'

const environment = validateEnvironment(process.env)

export default new DataSource({
    type: 'postgres',
    url: environment.DATABASE_URL,
    entities: [`${__dirname}/../**/*.entity.{js,ts}`],
    migrations: [`${__dirname}/migrations/*.{js,ts}`],
    synchronize: false,
})

import { Injectable } from '@nestjs/common'
import { metrics } from '@opentelemetry/api'

@Injectable()
export class MetricsService {
    private readonly meter = metrics.getMeter('bettertg-backend')

    readonly ingress = this.meter.createCounter('webpush.ingress.requests')
    readonly classification = this.meter.createCounter('webpush.classification')
    readonly decryptionFailures = this.meter.createCounter('webpush.decryption.failures')
    readonly apnsRequests = this.meter.createCounter('apns.requests')
    readonly apnsConnectionEvents = this.meter.createCounter('apns.connection.events')
    readonly processingDuration = this.meter.createHistogram('webpush.processing.duration', {
        unit: 'ms',
    })
}

import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics'
import { NodeSDK } from '@opentelemetry/sdk-node'

import type { Environment } from '@/config/environment'

function endpoint(base: string, path: string): string {
    return `${base.replace(/\/$/, '')}${path}`
}

export function createTelemetry(environment: Environment): NodeSDK {
    const exporterBase = environment.OTEL_EXPORTER_OTLP_ENDPOINT

    return new NodeSDK({
        serviceName: 'bettertg-backend',
        traceExporter: exporterBase
            ? new OTLPTraceExporter({ url: endpoint(exporterBase, '/v1/traces') })
            : undefined,
        metricReader: exporterBase
            ? new PeriodicExportingMetricReader({
                  exporter: new OTLPMetricExporter({
                      url: endpoint(exporterBase, '/v1/metrics'),
                  }),
                  exportIntervalMillis: 15_000,
              })
            : undefined,
        instrumentations: [
            getNodeAutoInstrumentations({
                '@opentelemetry/instrumentation-fs': { enabled: false },
            }),
        ],
    })
}

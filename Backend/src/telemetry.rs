//! Logging, OpenTelemetry export and the relay's metrics. Nothing here records tokens, ciphertext, routing
//! identifiers or message text.

use std::time::Duration;

use opentelemetry::global;
use opentelemetry::metrics::{Counter, Histogram};
use opentelemetry::trace::TracerProvider as _;
use opentelemetry_otlp::{MetricExporter, Protocol, SpanExporter, WithExportConfig};
use opentelemetry_sdk::Resource;
use opentelemetry_sdk::metrics::{PeriodicReader, SdkMeterProvider};
use opentelemetry_sdk::trace::SdkTracerProvider;
use tracing_subscriber::Layer;
use tracing_subscriber::filter::Targets;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

use crate::config::Environment;
use crate::logging::{JsonLogLayer, level_filter};

const SERVICE_NAME: &str = "bettertg-backend";

/// Exporters to flush on shutdown; empty unless `OTEL_EXPORTER_OTLP_ENDPOINT` is set.
pub struct Telemetry {
    tracer_provider: Option<SdkTracerProvider>,
    meter_provider: Option<SdkMeterProvider>,
}

impl Telemetry {
    /// Installs the JSON logger and, with an OTLP endpoint, trace and metric export over HTTP. Call it before the
    /// Tokio runtime starts: the OTLP exporters use a blocking HTTP client.
    pub fn init(environment: &Environment) -> anyhow::Result<Self> {
        let base = environment.otel_exporter_otlp_endpoint.trim_end_matches('/');
        let (tracer_provider, meter_provider) = if base.is_empty() {
            (None, None)
        } else {
            let resource = Resource::builder().with_service_name(SERVICE_NAME).build();
            let spans = SpanExporter::builder()
                .with_http()
                .with_protocol(Protocol::HttpBinary)
                .with_endpoint(format!("{base}/v1/traces"))
                .build()?;
            let tracer_provider =
                SdkTracerProvider::builder().with_batch_exporter(spans).with_resource(resource.clone()).build();
            global::set_tracer_provider(tracer_provider.clone());

            let metrics = MetricExporter::builder()
                .with_http()
                .with_protocol(Protocol::HttpBinary)
                .with_endpoint(format!("{base}/v1/metrics"))
                .build()?;
            let reader = PeriodicReader::builder(metrics).with_interval(Duration::from_secs(15)).build();
            let meter_provider = SdkMeterProvider::builder().with_reader(reader).with_resource(resource).build();
            global::set_meter_provider(meter_provider.clone());
            (Some(tracer_provider), Some(meter_provider))
        };

        let level = level_filter(environment.log_level);
        let logs = JsonLogLayer.with_filter(
            Targets::new()
                .with_target("bettertg_backend", level)
                .with_default(tracing::level_filters::LevelFilter::WARN.min(level)),
        );
        let traces = tracer_provider.as_ref().map(|provider| {
            tracing_opentelemetry::layer()
                .with_tracer(provider.tracer(SERVICE_NAME))
                .with_filter(Targets::new().with_default(tracing::level_filters::LevelFilter::INFO))
        });
        tracing_subscriber::registry().with(logs).with(traces).try_init()?;
        Ok(Self { tracer_provider, meter_provider })
    }

    pub fn shutdown(self) {
        if let Some(provider) = self.tracer_provider {
            let _ = provider.shutdown();
        }
        if let Some(provider) = self.meter_provider {
            let _ = provider.shutdown();
        }
    }
}

/// The relay's counters and histograms, named as before the Rust port so dashboards keep working.
#[derive(Clone)]
pub struct Metrics {
    pub ingress: Counter<u64>,
    pub classification: Counter<u64>,
    pub decryption_failures: Counter<u64>,
    pub apns_requests: Counter<u64>,
    pub apns_connection_events: Counter<u64>,
    pub processing_duration: Histogram<f64>,
}

impl Metrics {
    pub fn new() -> Self {
        let meter = global::meter(SERVICE_NAME);
        Self {
            ingress: meter.u64_counter("webpush.ingress.requests").build(),
            classification: meter.u64_counter("webpush.classification").build(),
            decryption_failures: meter.u64_counter("webpush.decryption.failures").build(),
            apns_requests: meter.u64_counter("apns.requests").build(),
            apns_connection_events: meter.u64_counter("apns.connection.events").build(),
            processing_duration: meter.f64_histogram("webpush.processing.duration").with_unit("ms").build(),
        }
    }
}

impl Default for Metrics {
    fn default() -> Self {
        Self::new()
    }
}

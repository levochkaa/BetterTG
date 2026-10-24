//! Process configuration from the environment, validated once at startup.

use std::collections::HashMap;
use std::fmt;

use url::Url;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RuntimeEnvironment {
    Development,
    Test,
    Production,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppAttestMode {
    Enforce,
    Bypass,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Clone, Debug)]
pub struct Environment {
    pub node_env: RuntimeEnvironment,
    pub port: u16,
    pub public_base_url: String,
    pub database_url: String,
    pub redis_url: String,
    pub bundle_id: String,
    pub apple_team_id: String,
    pub apns_sandbox_key_id: String,
    pub apns_sandbox_auth_key: String,
    pub apns_sandbox_auth_key_file: String,
    pub apns_production_key_id: String,
    pub apns_production_auth_key: String,
    pub apns_production_auth_key_file: String,
    pub apns_dry_run: bool,
    pub apns_sandbox_url: String,
    pub apns_production_url: String,
    pub apns_request_timeout_ms: u64,
    pub encryption_current_key_id: String,
    pub encryption_keys: String,
    pub management_token_pepper: String,
    pub app_attest_mode: AppAttestMode,
    pub app_attest_allow_development: bool,
    pub otel_exporter_otlp_endpoint: String,
    pub log_level: LogLevel,
    pub swagger_enabled: bool,
}

/// Every problem found in the environment, reported together as the process refuses to start.
#[derive(Debug)]
pub struct ConfigError(pub Vec<String>);

impl fmt::Display for ConfigError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "invalid environment: {}", self.0.join("; "))
    }
}

impl std::error::Error for ConfigError {}

const APPLE_SANDBOX_URL: &str = "https://api.sandbox.push.apple.com";
const APPLE_PRODUCTION_URL: &str = "https://api.push.apple.com";

struct Reader<'a> {
    variables: &'a HashMap<String, String>,
    issues: Vec<String>,
}

impl Reader<'_> {
    fn raw(&self, name: &str) -> Option<&str> {
        self.variables.get(name).map(String::as_str)
    }

    fn string(&mut self, name: &str, default: &str, minimum_length: usize) -> String {
        let value = self.raw(name).unwrap_or(default).to_owned();
        if value.chars().count() < minimum_length {
            self.issues.push(format!("{name} must contain at least {minimum_length} characters"));
        }
        value
    }

    fn url(&mut self, name: &str, default: &str) -> String {
        let value = self.raw(name).unwrap_or(default).to_owned();
        if Url::parse(&value).is_err() {
            self.issues.push(format!("{name} must be a URL"));
        }
        value
    }

    fn boolean(&mut self, name: &str, default: bool) -> bool {
        match self.raw(name) {
            None => default,
            Some("true") => true,
            Some("false") => false,
            Some(_) => {
                self.issues.push(format!("{name} must be \"true\" or \"false\""));
                default
            }
        }
    }

    fn integer(&mut self, name: &str, default: u64, minimum: u64, maximum: u64) -> u64 {
        let Some(raw) = self.raw(name) else { return default };
        match raw.trim().parse::<u64>() {
            Ok(value) if (minimum..=maximum).contains(&value) => value,
            _ => {
                self.issues.push(format!("{name} must be an integer from {minimum} to {maximum}"));
                default
            }
        }
    }

    fn choice<T: Copy>(&mut self, name: &str, default: T, choices: &[(&str, T)]) -> T {
        let Some(raw) = self.raw(name) else { return default };
        if let Some((_, value)) = choices.iter().find(|(label, _)| *label == raw) {
            return *value;
        }
        let labels: Vec<_> = choices.iter().map(|(label, _)| *label).collect();
        self.issues.push(format!("{name} must be one of {}", labels.join(", ")));
        default
    }
}

impl Environment {
    /// Reads the process environment after loading a local `.env` file, which never overrides variables that are
    /// already set.
    pub fn from_process() -> Result<Self, ConfigError> {
        let _ = dotenvy::dotenv();
        Self::from_map(&std::env::vars().collect())
    }

    pub fn from_map(variables: &HashMap<String, String>) -> Result<Self, ConfigError> {
        let mut reader = Reader { variables, issues: Vec::new() };
        let environment = Environment {
            node_env: reader.choice(
                "NODE_ENV",
                RuntimeEnvironment::Development,
                &[
                    ("development", RuntimeEnvironment::Development),
                    ("test", RuntimeEnvironment::Test),
                    ("production", RuntimeEnvironment::Production),
                ],
            ),
            port: reader.integer("PORT", 3000, 1, 65_535) as u16,
            public_base_url: reader.url("PUBLIC_BASE_URL", "http://localhost:8080"),
            database_url: reader.url("DATABASE_URL", "postgresql://bettertg:bettertg@localhost:5433/bettertg"),
            redis_url: reader.url("REDIS_URL", "redis://localhost:6380/0"),
            bundle_id: reader.string("BUNDLE_ID", "com.levochkaaa.BetterTG", 3),
            apple_team_id: reader.string("APPLE_TEAM_ID", "7Z2WHPKU8W", 1),
            apns_sandbox_key_id: reader.string("APNS_SANDBOX_KEY_ID", "", 0),
            apns_sandbox_auth_key: reader.string("APNS_SANDBOX_AUTH_KEY", "", 0),
            apns_sandbox_auth_key_file: reader.string("APNS_SANDBOX_AUTH_KEY_FILE", "", 0),
            apns_production_key_id: reader.string("APNS_PRODUCTION_KEY_ID", "", 0),
            apns_production_auth_key: reader.string("APNS_PRODUCTION_AUTH_KEY", "", 0),
            apns_production_auth_key_file: reader.string("APNS_PRODUCTION_AUTH_KEY_FILE", "", 0),
            apns_dry_run: reader.boolean("APNS_DRY_RUN", true),
            apns_sandbox_url: reader.url("APNS_SANDBOX_URL", APPLE_SANDBOX_URL),
            apns_production_url: reader.url("APNS_PRODUCTION_URL", APPLE_PRODUCTION_URL),
            apns_request_timeout_ms: reader.integer("APNS_REQUEST_TIMEOUT_MS", 10_000, 100, 60_000),
            encryption_current_key_id: reader.string("ENCRYPTION_CURRENT_KEY_ID", "dev", 1),
            encryption_keys: reader.string("ENCRYPTION_KEYS", "dev:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", 1),
            management_token_pepper: reader.string(
                "MANAGEMENT_TOKEN_PEPPER",
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                1,
            ),
            app_attest_mode: reader.choice(
                "APP_ATTEST_MODE",
                AppAttestMode::Bypass,
                &[("enforce", AppAttestMode::Enforce), ("bypass", AppAttestMode::Bypass)],
            ),
            app_attest_allow_development: reader.boolean("APP_ATTEST_ALLOW_DEVELOPMENT", true),
            otel_exporter_otlp_endpoint: reader.string("OTEL_EXPORTER_OTLP_ENDPOINT", "", 0),
            log_level: reader.choice(
                "LOG_LEVEL",
                LogLevel::Info,
                &[
                    ("debug", LogLevel::Debug),
                    ("info", LogLevel::Info),
                    ("warn", LogLevel::Warn),
                    ("error", LogLevel::Error),
                ],
            ),
            swagger_enabled: reader.boolean("SWAGGER_ENABLED", true),
        };
        let mut issues = reader.issues;
        if environment.node_env == RuntimeEnvironment::Production {
            issues.extend(environment.production_issues());
        }
        if issues.is_empty() { Ok(environment) } else { Err(ConfigError(issues)) }
    }

    /// Production refuses plain-HTTP public URLs, the App Attest bypass, the development encryption key, missing
    /// APNs credentials for real delivery, and APNs hosts other than Apple's.
    fn production_issues(&self) -> Vec<String> {
        let mut issues = Vec::new();
        if !self.public_base_url.starts_with("https://") {
            issues.push("production PUBLIC_BASE_URL must use HTTPS".to_owned());
        }
        if self.app_attest_mode != AppAttestMode::Enforce {
            issues.push("production requires App Attest enforcement".to_owned());
        }
        if self.encryption_current_key_id == "dev" {
            issues.push("production must not use the development encryption key".to_owned());
        }
        if !self.apns_dry_run
            && (self.apns_sandbox_key_id.is_empty()
                || (self.apns_sandbox_auth_key.is_empty() && self.apns_sandbox_auth_key_file.is_empty()))
        {
            issues.push("sandbox APNs credentials are required when dry-run mode is disabled".to_owned());
        }
        if !self.apns_dry_run
            && (self.apns_production_key_id.is_empty()
                || (self.apns_production_auth_key.is_empty() && self.apns_production_auth_key_file.is_empty()))
        {
            issues.push("production APNs credentials are required when dry-run mode is disabled".to_owned());
        }
        if self.apns_sandbox_url != APPLE_SANDBOX_URL || self.apns_production_url != APPLE_PRODUCTION_URL {
            issues.push("production APNs endpoints must use Apple hosts".to_owned());
        }
        issues
    }

    pub fn is_production(&self) -> bool {
        self.node_env == RuntimeEnvironment::Production
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn environment(pairs: &[(&str, &str)]) -> Result<Environment, ConfigError> {
        Environment::from_map(&pairs.iter().map(|(key, value)| ((*key).to_owned(), (*value).to_owned())).collect())
    }

    const PRODUCTION: &[(&str, &str)] = &[
        ("NODE_ENV", "production"),
        ("PUBLIC_BASE_URL", "https://push.example.com"),
        ("APP_ATTEST_MODE", "enforce"),
        ("ENCRYPTION_CURRENT_KEY_ID", "v1"),
        ("ENCRYPTION_KEYS", "v1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
    ];

    #[test]
    fn provides_safe_local_defaults() {
        let environment = environment(&[]).unwrap();
        assert_eq!(environment.node_env, RuntimeEnvironment::Development);
        assert!(environment.apns_dry_run);
        assert_eq!(environment.app_attest_mode, AppAttestMode::Bypass);
        assert_eq!(environment.port, 3000);
    }

    #[test]
    fn rejects_insecure_production_configuration() {
        assert!(environment(&[("NODE_ENV", "production"), ("PUBLIC_BASE_URL", "http://push.example.com")]).is_err());
    }

    #[test]
    fn accepts_production_with_https_and_enforced_attestation() {
        let mut pairs = PRODUCTION.to_vec();
        pairs.push(("APNS_DRY_RUN", "true"));
        assert_eq!(environment(&pairs).unwrap().app_attest_mode, AppAttestMode::Enforce);
    }

    #[test]
    fn requires_credentials_for_both_apns_environments_in_real_delivery() {
        let mut pairs = PRODUCTION.to_vec();
        pairs.extend([
            ("APNS_DRY_RUN", "false"),
            ("APNS_SANDBOX_KEY_ID", "SBXKEY0001"),
            ("APNS_SANDBOX_AUTH_KEY", "sandbox-key"),
        ]);
        assert!(environment(&pairs).is_err());
        pairs.extend([("APNS_PRODUCTION_KEY_ID", "PRDKEY0001"), ("APNS_PRODUCTION_AUTH_KEY", "production-key")]);
        assert!(!environment(&pairs).unwrap().apns_dry_run);
    }

    #[test]
    fn rejects_malformed_values() {
        assert!(environment(&[("PORT", "0")]).is_err());
        assert!(environment(&[("APNS_DRY_RUN", "yes")]).is_err());
        assert!(environment(&[("LOG_LEVEL", "trace")]).is_err());
        assert!(environment(&[("REDIS_URL", "")]).is_err());
    }
}

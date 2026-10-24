use clap::{Parser, Subcommand};

use bettertg_backend::config::Environment;
use bettertg_backend::telemetry::Telemetry;
use bettertg_backend::{app, db};

#[derive(Parser)]
#[command(version, about = "BetterTG rich push relay")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Serve the HTTP API.
    Api,
    /// Deliver queued pushes to APNs.
    Worker,
    /// Manage the database schema.
    Migrate {
        #[command(subcommand)]
        action: MigrateAction,
    },
}

#[derive(Subcommand)]
enum MigrateAction {
    /// Apply pending migrations.
    Run,
    /// Revert the latest applied migration.
    Revert,
    /// List migrations and whether each is applied.
    Show,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let _ = rustls::crypto::ring::default_provider().install_default();
    let environment = Environment::from_process()?;
    let telemetry = Telemetry::init(&environment)?;
    let runtime = tokio::runtime::Builder::new_multi_thread().enable_all().build()?;
    let result = runtime.block_on(async move {
        match cli.command {
            Command::Api => app::run_api(environment).await,
            Command::Worker => app::run_worker(environment).await,
            Command::Migrate { action } => migrate(&environment, action).await,
        }
    });
    drop(runtime);
    telemetry.shutdown();
    result
}

async fn migrate(environment: &Environment, action: MigrateAction) -> anyhow::Result<()> {
    let pool = db::connect(&environment.database_url)?;
    match action {
        MigrateAction::Run => {
            let applied = db::migrations::run(&pool).await?;
            if applied.is_empty() {
                println!("No migrations are pending");
            }
            for name in applied {
                println!("Migration {name} has been executed successfully");
            }
        }
        MigrateAction::Revert => match db::migrations::revert(&pool).await? {
            Some(name) => println!("Migration {name} has been reverted successfully"),
            None => println!("No migrations to revert"),
        },
        MigrateAction::Show => {
            for (name, applied) in db::migrations::status(&pool).await? {
                println!("[{}] {name}", if applied { "X" } else { " " });
            }
        }
    }
    Ok(())
}

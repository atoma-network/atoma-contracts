mod add_model;
mod add_model_echelon;
mod add_node_to_model;
mod register_node;
mod set_required_registration_collateral;
mod submit_example_text_prompt;

use std::path::PathBuf;

use clap::{Parser, Subcommand};
use sui_sdk::{
    rpc_types::{
        ObjectChange, Page, SuiObjectDataFilter, SuiObjectDataOptions, SuiObjectResponseQuery,
        SuiTransactionBlockResponseOptions, SuiTransactionBlockResponseQuery, TransactionFilter,
    },
    types::{
        base_types::{ObjectID, ObjectType, SuiAddress},
        object::Owner,
    },
    wallet_context::WalletContext,
    SuiClient,
};

const GATE_MODULE_NAME: &str = "gate";
const DB_MODULE_NAME: &str = "db";
const DB_MANAGER_TYPE_NAME: &str = "AtomaManagerBadge";
const DB_NODE_TYPE_NAME: &str = "NodeBadge";
const DB_TYPE_NAME: &str = "AtomaDb";

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Some operations require a budget to be set.
    /// We also provide sensible default values for this.
    #[arg(short, long)]
    gas_budget: Option<u64>,

    /// Where to find the config for the wallet keystore.
    #[arg(short, long)]
    wallet: PathBuf,

    #[command(subcommand)]
    command: Option<Cmds>,
}

#[derive(Subcommand)]
enum Cmds {
    #[command(subcommand)]
    Db(DbCmds),
    #[command(subcommand)]
    Gate(GateCmds),
}

#[derive(Subcommand)]
enum DbCmds {
    AddModel {
        #[arg(short, long)]
        package: String,
        #[arg(short, long)]
        model_name: String,
    },
    AddModelEchelon {
        #[arg(short, long)]
        package: String,
        #[arg(short, long)]
        model_name: String,
        #[arg(short, long)]
        echelon: u64,
        #[arg(short, long)]
        fee_in_protocol_token: u64,
        #[arg(short, long)]
        relative_performance: u64,
    },
    SetRequiredRegistrationTomaCollateral {
        #[arg(short, long)]
        package: String,
        #[arg(short, long)]
        new_amount: u64,
    },
    RegisterNode {
        #[arg(short, long)]
        package: String,
    },
    AddNodeToModel {
        #[arg(short, long)]
        package: String,
        #[arg(short, long)]
        model_name: String,
        #[arg(short, long)]
        echelon: u64,
    },
}

#[derive(Subcommand)]
enum GateCmds {
    SubmitExampleTextPrompt {
        #[arg(short, long)]
        package: String,
        #[arg(short, long)]
        model_name: String,
        #[arg(long)]
        prompt_path: PathBuf,
        #[arg(short, long)]
        nodes_to_sample: u64,
    },
}

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let cli = Cli::parse();

    if !cli.wallet.exists() {
        return Err(anyhow::anyhow!("Wallet path does not exist"));
    }

    let mut wallet = WalletContext::new(&cli.wallet, None, None)?;
    let active_address = wallet.active_address()?;
    println!("Active address: {active_address}");

    match cli.command {
        Some(Cmds::Db(DbCmds::AddModel {
            package,
            model_name,
        })) => {
            let digest = add_model::command(
                &mut wallet,
                &package,
                &model_name,
                cli.gas_budget.unwrap_or(1_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::AddModelEchelon {
            package,
            model_name,
            echelon,
            fee_in_protocol_token,
            relative_performance,
        })) => {
            let digest = add_model_echelon::command(
                &mut wallet,
                &package,
                &model_name,
                echelon,
                fee_in_protocol_token,
                relative_performance,
                cli.gas_budget.unwrap_or(1_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::SetRequiredRegistrationTomaCollateral {
            package,
            new_amount,
        })) => {
            let digest = set_required_registration_collateral::command(
                &mut wallet,
                &package,
                new_amount,
                cli.gas_budget.unwrap_or(1_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::RegisterNode { package })) => {
            let digest = register_node::command(
                &mut wallet,
                &package,
                cli.gas_budget.unwrap_or(1_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::AddNodeToModel {
            package,
            model_name,
            echelon,
        })) => {
            let digest = add_node_to_model::command(
                &mut wallet,
                &package,
                &model_name,
                echelon,
                cli.gas_budget.unwrap_or(1_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Gate(GateCmds::SubmitExampleTextPrompt {
            package,
            model_name,
            prompt_path,
            nodes_to_sample,
        })) => {
            let digest = submit_example_text_prompt::command(
                &mut wallet,
                &package,
                &model_name,
                &prompt_path,
                nodes_to_sample,
                cli.gas_budget.unwrap_or(1_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        None => {}
    }

    Ok(())
}

async fn get_atoma_db(client: &SuiClient, package: ObjectID) -> Result<ObjectID, anyhow::Error> {
    let Page {
        data,
        has_next_page,
        ..
    } = client
        .read_api()
        .query_transaction_blocks(
            SuiTransactionBlockResponseQuery {
                filter: Some(TransactionFilter::ChangedObject(package)),
                options: Some(SuiTransactionBlockResponseOptions {
                    show_object_changes: true,
                    ..Default::default()
                }),
            },
            None,
            Some(1),
            false,
        )
        .await?;
    assert_eq!(1, data.len());
    assert!(!has_next_page);

    let changes = data.into_iter().next().unwrap().object_changes.unwrap();

    changes
        .into_iter()
        .find_map(|change| {
            if let ObjectChange::Created {
                owner: Owner::Shared { .. },
                object_type,
                object_id,
                ..
            } = change
            {
                if object_type.module.as_str() == DB_MODULE_NAME
                    && object_type.name.as_str() == DB_TYPE_NAME
                {
                    Some(object_id)
                } else {
                    None
                }
            } else {
                None
            }
        })
        .ok_or_else(|| anyhow::anyhow!("No {DB_TYPE_NAME} found for the package"))
}

async fn get_db_manager_badge(
    client: &SuiClient,
    package: ObjectID,
    active_address: SuiAddress,
) -> Result<ObjectID, anyhow::Error> {
    let Page {
        data,
        has_next_page,
        ..
    } = client
        .read_api()
        .get_owned_objects(
            active_address,
            Some(SuiObjectResponseQuery {
                filter: Some(SuiObjectDataFilter::Package(package)),
                options: Some(SuiObjectDataOptions {
                    show_type: true,
                    ..Default::default()
                }),
            }),
            None,
            None,
        )
        .await?;
    assert!(!has_next_page, "We don't support pagination yet");

    data.into_iter()
        .find_map(|resp| {
            let object = resp.data?;

            let ObjectType::Struct(type_) = object.type_? else {
                return None;
            };

            if type_.module().as_str() == DB_MODULE_NAME
                && type_.name().as_str() == DB_MANAGER_TYPE_NAME
            {
                Some(object.object_id)
            } else {
                None
            }
        })
        .ok_or_else(|| anyhow::anyhow!("No {DB_MANAGER_TYPE_NAME} found for the package"))
}

async fn get_node_badge(
    client: &SuiClient,
    package: ObjectID,
    active_address: SuiAddress,
) -> Result<ObjectID, anyhow::Error> {
    let Page {
        data,
        has_next_page,
        ..
    } = client
        .read_api()
        .get_owned_objects(
            active_address,
            Some(SuiObjectResponseQuery {
                filter: Some(SuiObjectDataFilter::Package(package)),
                options: Some(SuiObjectDataOptions {
                    show_type: true,
                    ..Default::default()
                }),
            }),
            None,
            None,
        )
        .await?;
    assert!(!has_next_page, "We don't support pagination yet");

    data.into_iter()
        .find_map(|resp| {
            let object = resp.data?;

            let ObjectType::Struct(type_) = object.type_? else {
                return None;
            };

            if type_.module().as_str() == DB_MODULE_NAME
                && type_.name().as_str() == DB_NODE_TYPE_NAME
            {
                Some(object.object_id)
            } else {
                None
            }
        })
        .ok_or_else(|| anyhow::anyhow!("No {DB_NODE_TYPE_NAME} found for the package"))
}

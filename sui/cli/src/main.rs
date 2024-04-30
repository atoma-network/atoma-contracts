mod db;
mod gate;
mod prelude;
mod settle;

use std::{collections::BTreeMap, io::Read, path::PathBuf, str::FromStr};

use clap::{Parser, Subcommand};
use move_core_types::language_storage::StructTag;
use sui_sdk::{
    rpc_types::{
        ObjectChange, Page, SuiData, SuiMoveStruct, SuiMoveValue,
        SuiObjectDataFilter, SuiObjectDataOptions, SuiObjectResponseQuery,
        SuiParsedData, SuiTransactionBlockResponseOptions,
        SuiTransactionBlockResponseQuery, TransactionFilter,
    },
    types::{
        base_types::{ObjectID, ObjectType, SuiAddress},
        TypeTag,
    },
    SuiClient,
};

use crate::prelude::*;

const DB_MODULE_NAME: &str = "db";
const PROMPTS_MODULE_NAME: &str = "prompts";
const PROMPTS_TYPE_NAME: &str = "AtomaPrompts";
const DB_MANAGER_TYPE_NAME: &str = "AtomaManagerBadge";
const DB_NODE_TYPE_NAME: &str = "NodeBadge";
const DB_TYPE_NAME: &str = "AtomaDb";
const SETTLEMENT_MODULE_NAME: &str = "settlement";
const SETTLEMENT_TICKET_TYPE_NAME: &str = "SettlementTicket";

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
    #[command(subcommand)]
    Settle(SettlementCmds),
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
        /// Max fee per character in protocol token.
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
    SubmitTellMeAJokePrompt {
        #[arg(short, long)]
        package: String,
        #[arg(short, long)]
        model_name: String,
        #[arg(long, default_value_t = 1_000)]
        max_fee_per_token: u64,
    },
}

#[derive(Subcommand)]
enum SettlementCmds {
    ListTickets {
        #[arg(short, long)]
        package: String,
    },
    SubmitCommitment {
        #[arg(short, long)]
        ticket_id: String,
        #[arg(short, long)]
        output: String,
    },
    TryToSettle {
        #[arg(short, long)]
        ticket_id: String,
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
            let digest = db::add_model(
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
            let digest = db::add_model_echelon(
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
            let digest = db::set_required_registration_collateral(
                &mut wallet,
                &package,
                new_amount,
                cli.gas_budget.unwrap_or(1_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::RegisterNode { package })) => {
            let digest = db::register_node(
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
            let digest = db::add_node_to_model(
                &mut wallet,
                &package,
                &model_name,
                echelon,
                cli.gas_budget.unwrap_or(1_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Gate(GateCmds::SubmitTellMeAJokePrompt {
            package,
            model_name,
            max_fee_per_token,
        })) => {
            let digest = gate::submit_tell_me_a_joke_prompt(
                &mut wallet,
                &package,
                &model_name,
                max_fee_per_token,
                cli.gas_budget.unwrap_or(2_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Settle(SettlementCmds::ListTickets { package })) => {
            settle::list_tickets(&mut wallet, &package).await?;
        }
        Some(Cmds::Settle(SettlementCmds::SubmitCommitment {
            ticket_id,
            output,
        })) => {
            let digest = settle::submit_commitment(
                &mut wallet,
                &ticket_id,
                &output,
                cli.gas_budget.unwrap_or(2_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Settle(SettlementCmds::TryToSettle { ticket_id })) => {
            let digest = settle::try_to_settle(
                &mut wallet,
                &ticket_id,
                cli.gas_budget.unwrap_or(2_000_000_000),
            )
            .await?;

            println!("{digest}");
        }
        None => {}
    }

    Ok(())
}

async fn get_atoma_db(
    client: &SuiClient,
    package: ObjectID,
) -> Result<ObjectID, anyhow::Error> {
    get_publish_tx_created_object(client, package, DB_MODULE_NAME, DB_TYPE_NAME)
        .await
}

async fn get_atoma_db_id_and_fields(
    client: &SuiClient,
    package: ObjectID,
) -> Result<(ObjectID, BTreeMap<String, SuiMoveValue>), anyhow::Error> {
    let atoma_id = get_atoma_db(&client, package).await?;

    let SuiParsedData::MoveObject(atoma) = client
        .read_api()
        .get_object_with_options(
            atoma_id,
            SuiObjectDataOptions {
                show_content: true,
                ..Default::default()
            },
        )
        .await?
        .data
        .ok_or_else(|| anyhow!("Cannot fetch AtomaDb data"))?
        .content
        .ok_or_else(|| anyhow!("AtomaDb has no content"))?
    else {
        return Err(anyhow!("AtomaDb must be a Move object"));
    };

    if atoma.type_.module.as_str() != DB_MODULE_NAME
        || atoma.type_.name.as_str() != DB_TYPE_NAME
    {
        return Err(anyhow!(
            "AtomaDb must be of type {DB_MODULE_NAME}.{DB_TYPE_NAME}",
        ));
    }

    let SuiMoveStruct::WithFields(fields) = atoma.fields else {
        return Err(anyhow!("AtomaDb must have fields"));
    };

    Ok((atoma_id, fields))
}

/// This object is a necessary input for atoma prompt standards.
async fn get_prompts(
    client: &SuiClient,
    package: ObjectID,
) -> Result<ObjectID, anyhow::Error> {
    get_publish_tx_created_object(
        client,
        package,
        PROMPTS_MODULE_NAME,
        PROMPTS_TYPE_NAME,
    )
    .await
}

async fn get_publish_tx_created_object(
    client: &SuiClient,
    package: ObjectID,
    module: &str,
    name: &str,
) -> Result<ObjectID, anyhow::Error> {
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
    assert_eq!(1, data.len(), "Did you select right package ID?");
    assert!(!has_next_page);

    let changes = data.into_iter().next().unwrap().object_changes.unwrap();

    changes
        .into_iter()
        .find_map(|change| {
            if let ObjectChange::Created {
                object_type,
                object_id,
                ..
            } = change
            {
                if object_type.module.as_str() == module
                    && object_type.name.as_str() == name
                {
                    Some(object_id)
                } else {
                    None
                }
            } else {
                None
            }
        })
        .ok_or_else(|| {
            anyhow::anyhow!("No {module}::{name} found for the package")
        })
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
        .ok_or_else(|| {
            anyhow::anyhow!("No {DB_MANAGER_TYPE_NAME} found for the package")
        })
}

/// Returns the ID of the node badge and the small ID of the node.
async fn get_node_badge(
    client: &SuiClient,
    package: ObjectID,
    active_address: SuiAddress,
) -> Result<(ObjectID, u64), anyhow::Error> {
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
                    show_content: true,
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
                let id = object
                    .content?
                    .try_as_move()?
                    .clone()
                    .fields
                    .to_json_value();

                Some((
                    object.object_id,
                    id["small_id"]["inner"].as_str()?.parse().ok()?,
                ))
            } else {
                None
            }
        })
        .ok_or_else(|| {
            anyhow::anyhow!("No {DB_NODE_TYPE_NAME} found for the package")
        })
}

async fn find_toma_token_wallets(
    client: &SuiClient,
    package: ObjectID,
    active_address: SuiAddress,
) -> Result<impl Iterator<Item = ObjectID>, anyhow::Error> {
    let type_ = StructTag {
        address: SuiAddress::from_str(
            "0x0000000000000000000000000000000000000000000000000000000000000002",
        )
        .unwrap()
        .into(),
        module: FromStr::from_str("coin")?,
        name: FromStr::from_str("Coin")?,
        type_params: vec![TypeTag::Struct(Box::new(StructTag {
            address: package.into(),
            module: FromStr::from_str("toma")?,
            name: FromStr::from_str("TOMA")?,
            type_params: vec![],
        }))],
    };

    let Page { data, .. } = client
        .read_api()
        .get_owned_objects(
            active_address,
            Some(SuiObjectResponseQuery {
                filter: Some(SuiObjectDataFilter::StructType(type_)),
                options: None,
            }),
            None,
            None,
        )
        .await?;

    Ok(data
        .into_iter()
        .filter_map(|resp| Some(resp.data?.object_id)))
}

/// Waits for the user to confirm an action.
fn wait_for_user_confirm() -> bool {
    loop {
        let mut input = [0];
        let _ = std::io::stdin().read(&mut input);
        match input[0] as char {
            'y' | 'Y' => return true,
            'n' | 'N' => return false,
            _ => println!("y/n only please."),
        }
    }
}

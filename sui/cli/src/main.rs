mod db;
mod dotenv_conf;
mod gate;
mod prelude;
mod settle;

use std::{io::Read, path::PathBuf, str::FromStr};

use clap::{Parser, Subcommand};
use dotenvy::dotenv;
use move_core_types::{
    account_address::AccountAddress, language_storage::StructTag,
};
use sui_sdk::{
    rpc_types::{
        ObjectChange, Page, SuiData, SuiObjectDataFilter, SuiObjectDataOptions,
        SuiObjectResponseQuery, SuiTransactionBlockResponseOptions,
        SuiTransactionBlockResponseQuery, TransactionFilter,
    },
    types::{
        base_types::{ObjectID, ObjectType, SuiAddress},
        dynamic_field::DynamicFieldName,
        TypeTag,
    },
    SuiClient,
};

use crate::{dotenv_conf::DotenvConf, prelude::*};

const DB_MODULE_NAME: &str = "db";
const PROMPTS_MODULE_NAME: &str = "prompts";
const DB_MANAGER_TYPE_NAME: &str = "AtomaManagerBadge";
const DB_NODE_TYPE_NAME: &str = "NodeBadge";
const DB_TYPE_NAME: &str = "AtomaDb";
const SETTLEMENT_MODULE_NAME: &str = "settlement";
const SETTLEMENT_TICKET_TYPE_NAME: &str = "SettlementTicket";

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Cmds>,

    /// Some operations require a budget to be set.
    /// We also provide sensible default values for this.
    #[arg(short, long)]
    gas_budget: Option<u64>,
    /// Where to find the config for the wallet keystore.
    /// Loaded from WALLET_PATH env var if not provided.
    #[arg(short, long)]
    wallet: Option<PathBuf>,
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
        package: Option<String>,
        #[arg(short, long)]
        name: String,
    },
    AddModelEchelon {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(short, long)]
        echelon: u64,
        #[arg(short, long)]
        input_fee_per_token: u64,
        /// Defaults to input_fee_per_token.
        #[arg(short, long)]
        output_fee_per_token: Option<u64>,
        #[arg(short, long)]
        relative_performance: u64,
    },
    SetRequiredRegistrationTomaCollateral {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        new_amount: u64,
    },
    RegisterNode {
        #[arg(short, long)]
        package: Option<String>,
    },
    AddNodeToModel {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(short, long)]
        echelon: u64,
    },
    /// Prints env vars in .env format that contain some important IDs for
    /// the network.
    PrintEnv {
        #[arg(short, long)]
        package: Option<String>,
    },
    RemoveNodeFromModel {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
    },
    PermanentlyDisableNode {
        #[arg(short, long)]
        package: Option<String>,
    },
    DestroyDisabledNode {
        #[arg(short, long)]
        package: Option<String>,
    },
}

#[derive(Subcommand)]
enum GateCmds {
    SubmitTellMeAJokePrompt {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(long, default_value_t = 1_000)]
        max_fee_per_token: u64,
    },
    SubmitGenerateNftPrompt {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(long, default_value_t = 1_000)]
        max_fee_per_token: u64,
    },
}

#[derive(Subcommand)]
enum SettlementCmds {
    ListTickets {
        #[arg(short, long)]
        package: Option<String>,
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
async fn main() -> Result<()> {
    dotenv().ok();
    env_logger::init();

    let mut dotenv_conf = DotenvConf::from_env();

    let cli = Cli::parse();

    if cli.wallet.is_some() {
        dotenv_conf.wallet_path = cli.wallet;
    }

    if cli.gas_budget.is_some() {
        dotenv_conf.gas_budget = cli.gas_budget;
    }

    let wallet = {
        let p = dotenv_conf.wallet_path.as_ref().unwrap();
        if !dotenv_conf.wallet_path.as_ref().unwrap().exists() {
            return Err(anyhow::anyhow!("Wallet path does not exist"));
        }

        let mut wallet = WalletContext::new(p, None, None)?;
        let active_address = wallet.active_address()?;
        info!("Active address: {active_address}");
        wallet
    };

    let mut context = Context {
        conf: dotenv_conf,
        wallet,
    };

    match cli.command {
        Some(Cmds::Db(DbCmds::PrintEnv { package })) => {
            db::print_env(&mut context.with_optional_package_id(package))
                .await?;
        }
        Some(Cmds::Db(DbCmds::AddModel { package, name })) => {
            let digest = db::add_model(
                &mut context.with_optional_package_id(package),
                &name,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::AddModelEchelon {
            package,
            model,
            echelon,
            input_fee_per_token,
            output_fee_per_token,
            relative_performance,
        })) => {
            let digest = db::add_model_echelon(
                &mut context.with_optional_package_id(package),
                &model,
                echelon,
                input_fee_per_token,
                output_fee_per_token.unwrap_or(input_fee_per_token),
                relative_performance,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::SetRequiredRegistrationTomaCollateral {
            package,
            new_amount,
        })) => {
            let digest = db::set_required_registration_collateral(
                &mut context.with_optional_package_id(package),
                new_amount,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::RegisterNode { package })) => {
            let digest = db::register_node(
                &mut context.with_optional_package_id(package),
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::AddNodeToModel {
            package,
            model,
            echelon,
        })) => {
            let digest = db::add_node_to_model(
                &mut context.with_optional_package_id(package),
                &model,
                echelon,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::RemoveNodeFromModel { package, model })) => {
            let digest = db::remove_node_from_model(
                &mut context.with_optional_package_id(package),
                &model,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::PermanentlyDisableNode { package })) => {
            db::permanently_disable_node(
                &mut context.with_optional_package_id(package),
            )
            .await?;
        }
        Some(Cmds::Db(DbCmds::DestroyDisabledNode { package })) => {
            db::destroy_disabled_node(
                &mut context.with_optional_package_id(package),
            )
            .await?;
        }
        Some(Cmds::Gate(GateCmds::SubmitTellMeAJokePrompt {
            package,
            model,
            max_fee_per_token,
        })) => {
            let digest = gate::submit_tell_me_a_joke_prompt(
                &mut context.with_optional_package_id(package),
                &model,
                max_fee_per_token,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Gate(GateCmds::SubmitGenerateNftPrompt {
            package,
            model,
            max_fee_per_token,
        })) => {
            let digest = gate::submit_generate_nft_prompt(
                &mut context.with_optional_package_id(package),
                &model,
                max_fee_per_token,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Settle(SettlementCmds::ListTickets { package })) => {
            settle::list_tickets(
                &mut context.with_optional_package_id(package),
            )
            .await?;
        }
        Some(Cmds::Settle(SettlementCmds::SubmitCommitment {
            ticket_id,
            output,
        })) => {
            let digest =
                settle::submit_commitment(&mut context, &ticket_id, &output)
                    .await?;

            println!("{digest}");
        }
        Some(Cmds::Settle(SettlementCmds::TryToSettle { ticket_id })) => {
            let digest =
                settle::try_to_settle(&mut context, &ticket_id).await?;

            println!("{digest}");
        }
        None => {}
    }

    Ok(())
}

async fn get_atoma_db(
    client: &SuiClient,
    package: ObjectID,
) -> Result<ObjectID> {
    get_publish_tx_created_object(client, package, DB_MODULE_NAME, DB_TYPE_NAME)
        .await
}

async fn get_publish_tx_created_object(
    client: &SuiClient,
    package: ObjectID,
    module: &str,
    name: &str,
) -> Result<ObjectID> {
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
) -> Result<ObjectID> {
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
) -> Result<(ObjectID, u64)> {
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
) -> Result<impl Iterator<Item = ObjectID>> {
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

trait DynamicFieldNameExt {
    fn ascii(s: &str) -> Self;
}

impl DynamicFieldNameExt for DynamicFieldName {
    fn ascii(value: &str) -> Self {
        DynamicFieldName {
            type_: TypeTag::Struct(Box::new(StructTag {
                address: AccountAddress::ONE,
                module: FromStr::from_str("ascii").unwrap(),
                name: FromStr::from_str("String").unwrap(),
                type_params: vec![],
            })),
            value: serde_json::Value::String(value.to_owned()),
        }
    }
}

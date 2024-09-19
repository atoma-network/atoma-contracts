mod db;
mod dotenv_conf;
mod gate;
mod prelude;
mod settle;
mod toma;

use std::{io::Read, path::PathBuf, str::FromStr};

use clap::{Parser, Subcommand};
use dotenv_conf::WALLET_PATH;
use dotenvy::dotenv;
use env_home::env_home_dir;
use move_core_types::{
    account_address::AccountAddress, language_storage::StructTag,
};
use sui_sdk::types::{dynamic_field::DynamicFieldName, TypeTag};

use crate::{dotenv_conf::DotenvConf, prelude::*};

const DB_MANAGER_TYPE_NAME: &str = "AtomaManagerBadge";
const DB_MODULE_NAME: &str = "db";
const DB_NODE_TYPE_NAME: &str = "NodeBadge";
const DB_TYPE_NAME: &str = "AtomaDb";
const FAUCET_TYPE_NAME: &str = "Faucet";
const PROMPTS_MODULE_NAME: &str = "prompts";
const SETTLEMENT_MODULE_NAME: &str = "settlement";
const SETTLEMENT_TICKET_TYPE_NAME: &str = "SettlementTicket";
const TOMA_COIN_MODULE_NAME: &str = "toma";

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Cmds>,

    /// Some operations require a budget to be set.
    /// We provide sensible default value.
    #[arg(short, long)]
    gas_budget: Option<u64>,
    /// Where to find the config for the wallet keystore.
    /// Loaded from WALLET_PATH env var if not provided.
    /// If neither is provided, the CLI will fail.
    #[arg(short, long)]
    wallet: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Cmds {
    /// Queries and operations related to the database.
    #[command(subcommand)]
    Db(DbCmds),
    /// Queries and operations related to submitting a prompt.
    #[command(subcommand)]
    Gate(GateCmds),
    /// Queries and operations related to settling tickets.
    #[command(subcommand)]
    Settle(SettlementCmds),
    /// TOMA coin package related commands.
    #[command(subcommand)]
    Toma(TomaCmds),
}

#[derive(Subcommand)]
enum DbCmds {
    /// Admin command to add a new model to the database.
    AddModel {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        name: String,
        /// Provide if the model is text2text such as llama.
        /// Exclusive with text2image.
        #[arg(long, action)]
        text2text: bool,
        /// Provide if the model is text2image such as stable diffusion.
        /// Exclusive with text2text.
        #[arg(long, action)]
        text2image: bool,
    },
    /// Admin command to add a new echelon to a model.
    AddModelEchelon {
        #[arg(short, long)]
        package: Option<String>,
        /// Must match an existing model name.
        #[arg(short, long)]
        model: String,
        /// The echelon is an ID that is agreed upon by the protocol.
        #[arg(short, long)]
        echelon: u64,
        /// The fee per token that the model charges for input tokens.
        #[arg(short, long)]
        input_fee_per_token: u64,
        /// Defaults to input_fee_per_token, which is ideal for text to text
        /// models.
        #[arg(short, long)]
        output_fee_per_token: Option<u64>,
        /// The relative performance of the model to other models.
        /// This is relevant for load balancing.
        #[arg(short, long)]
        relative_performance: u64,
    },
    /// Admin command to set the required registration collateral for TOMA.
    /// Nodes will lock this many TOMA tokens.
    SetRequiredRegistrationTomaCollateral {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        new_amount: u64,
    },
    /// First thing to do as a node.
    /// It will create a `NodeBadge` object for the node.
    RegisterNode {
        #[arg(short, long)]
        package: Option<String>,
    },
    /// Node can join a model to receive prompts.
    AddNodeToModel {
        #[arg(short, long)]
        package: Option<String>,
        /// Must match an existing model name.
        #[arg(short, long)]
        model: String,
        /// Must match an existing echelon ID.
        /// Echelons group nodes with similar HW and SW.
        /// See the protocol documentation for the list of echelons.
        #[arg(short, long)]
        echelon: u64,
    },
    /// Prints env vars in .env format that contain some important IDs for
    /// the network.
    PrintEnv {
        #[arg(short, long)]
        package: Option<String>,
    },
    /// A node can stop receiving prompts from a model.
    /// There exist a rare scenario where this transaction must be retried due
    /// to concurrent modification.
    /// You will be informed if this happens and asked for retry.
    RemoveNodeFromModel {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
    },
    /// Stop participating in the network.
    /// This cannot be undone and if a node wants to join again, they must
    /// generate a new `NodeBadge`.
    PermanentlyDisableNode {
        #[arg(short, long)]
        package: Option<String>,
    },
    /// On the second epoch from now (tops 2 days), the node can be destroyed
    /// and the collateral will be returned.
    DestroyDisabledNode {
        #[arg(short, long)]
        package: Option<String>,
    },
}

#[derive(Subcommand)]
enum GateCmds {
    /// Sends a text prompt to the network to a user specified output destination
    SendPrompt {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(short, long)]
        prompt: String,
        #[arg(short, long)]
        max_tokens: u64,
        #[arg(short, long)]
        temperature: u32,
        #[arg(short, long)]
        output_destination: Vec<u8>,
        #[arg(short, long)]
        max_fee_per_token: u64,
        #[arg(short, long)]
        nodes_to_sample: Option<u64>,
    },

    /// Sends a text prompt to the network and stores the output on IPFS
    SendPromptToIpfs {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(short, long)]
        prompt: String,
        #[arg(short, long)]
        max_tokens: u64,
        #[arg(short, long)]
        temperature: u32,
        #[arg(short, long)]
        max_fee_per_token: u64,
        #[arg(short, long)]
        nodes_to_sample: Option<u64>,
    },

    /// Sends a text prompt to the network and stores the output on Gateway
    SendPromptToGateway {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(short, long)]
        prompt: String,
        #[arg(short, long)]
        max_tokens: u64,
        #[arg(short, long)]
        temperature: u32,
        #[arg(short, long)]
        gateway_user_id: String,
        #[arg(short, long)]
        max_fee_per_token: u64,
        #[arg(short, long)]
        nodes_to_sample: Option<u64>,
    },

    /// Sends a image generation text prompt to the network with specified output destination
    SendImagePrompt {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(short, long)]
        prompt: String,
        #[arg(short, long)]
        height: u64,
        #[arg(short, long)]
        width: u64,
        #[arg(short, long)]
        max_fee_per_input_token: u64,
        #[arg(short, long)]
        max_fee_per_output_token: u64,
        #[arg(short, long)]
        output_destination: Vec<u8>,
        #[arg(short, long)]
        nodes_to_sample: Option<u64>,
    },

    /// Sends a image generation text prompt to the network to be stored on IPFS
    SendImagePromptToIpfs {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(short, long)]
        prompt: String,
        #[arg(short, long)]
        height: u64,
        #[arg(short, long)]
        width: u64,
        #[arg(short, long)]
        max_fee_per_input_token: u64,
        #[arg(short, long)]
        max_fee_per_output_token: u64,
        #[arg(short, long)]
        nodes_to_sample: Option<u64>,
    },

    /// Sends a image generation text prompt to the network and stores the output on Gateway
    SendImagePromptToGateway {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(short, long)]
        prompt: String,
        #[arg(short, long)]
        height: u64,
        #[arg(short, long)]
        width: u64,
        #[arg(short, long)]
        gateway_user_id: String,
        #[arg(short, long)]
        max_fee_per_input_token: u64,
        #[arg(short, long)]
        max_fee_per_output_token: u64,
        #[arg(short, long)]
        nodes_to_sample: Option<u64>,
    },
}

#[derive(Subcommand)]
enum SettlementCmds {
    /// Lists all open tickets.
    ListTickets {
        #[arg(short, long)]
        package: Option<String>,
    },
    /// Submit a commitment to settle a ticket.
    /// This can be only used for text to text models.
    SubmitCommitment {
        #[arg(short, long)]
        ticket_id: String,
        #[arg(short, long)]
        output: String,
    },
    /// Try to settle a ticket.
    /// This might be necessary to handle node timeouts.
    TryToSettle {
        #[arg(short, long)]
        ticket_id: String,
    },
}

#[derive(Subcommand)]
enum TomaCmds {
    /// Admin command to mint TOMA tokens.
    Faucet {
        /// If not provided, we take the value from the env vars.
        #[arg(long)]
        toma_package: Option<String>,
        #[arg(short, long)]
        amount: u64,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv().ok();
    env_logger::init();

    let cli = Cli::parse();

    let wallet_path = cli
        .wallet
        .clone()
        .or_else(|| std::env::var(WALLET_PATH).ok().map(PathBuf::from))
        .or_else(|| {
            // let's try the default path
            //
            // TODO: will work badly on windows so if anyone is using windows
            // insert a match statement here and provide the default path
            Some(PathBuf::from(format!(
                "{}/.sui/sui_config/client.yaml",
                env_home_dir()?.display()
            )))
        })
        .expect("Wallet path must be provided");

    let wallet = {
        if !wallet_path.exists() {
            return Err(anyhow::anyhow!(
                "Wallet does not exist at {wallet_path:?}"
            ));
        }

        let mut wallet = WalletContext::new(&wallet_path, None, None)?;
        let active_address = wallet.active_address()?;
        info!("Active address: {active_address}");
        wallet
    };

    if let Some(active_env) = wallet.config.active_env.as_ref() {
        // loads env specific for the current active environment
        dotenvy::from_filename_override(format!(".env.{active_env}")).ok();
    }

    let mut dotenv_conf = DotenvConf::from_env();
    dotenv_conf.wallet_path = Some(wallet_path);

    if cli.gas_budget.is_some() {
        dotenv_conf.gas_budget = cli.gas_budget;
    }

    let mut context = Context {
        conf: dotenv_conf,
        wallet,
    };

    match cli.command {
        Some(Cmds::Db(DbCmds::PrintEnv { package })) => {
            db::print_env(&mut context.with_optional_atoma_package_id(package))
                .await?;
        }
        Some(Cmds::Db(DbCmds::AddModel {
            package,
            name,
            text2text,
            text2image,
        })) => {
            let digest = db::add_model(
                &mut context.with_optional_atoma_package_id(package),
                &name,
                match (text2text, text2image) {
                    // this is defined in the gate module
                    (true, false) => 0,
                    (false, true) => 1,
                    _ => {
                        return Err(anyhow::anyhow!(
                        "Exactly one of --text2text or --text2image must be set"
                    ))
                    }
                },
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
                &mut context.with_optional_atoma_package_id(package),
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
                &mut context.with_optional_atoma_package_id(package),
                new_amount,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::RegisterNode { package })) => {
            let digest = db::register_node(
                &mut context.with_optional_atoma_package_id(package),
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
                &mut context.with_optional_atoma_package_id(package),
                &model,
                echelon,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::RemoveNodeFromModel { package, model })) => {
            let digest = db::remove_node_from_model(
                &mut context.with_optional_atoma_package_id(package),
                &model,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::PermanentlyDisableNode { package })) => {
            db::permanently_disable_node(
                &mut context.with_optional_atoma_package_id(package),
            )
            .await?;
        }
        Some(Cmds::Db(DbCmds::DestroyDisabledNode { package })) => {
            db::destroy_disabled_node(
                &mut context.with_optional_atoma_package_id(package),
            )
            .await?;
        }
        Some(Cmds::Gate(GateCmds::SendPrompt {
            package,
            model,
            max_fee_per_token,
            max_tokens,
            prompt,
            temperature,
            output_destination,
            nodes_to_sample,
        })) => {
            let digest = gate::send_prompt(
                &mut context.with_optional_atoma_package_id(package),
                &model,
                &prompt,
                max_tokens,
                temperature,
                max_fee_per_token,
                output_destination,
                nodes_to_sample,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Gate(GateCmds::SendPromptToIpfs {
            package,
            model,
            max_fee_per_token,
            max_tokens,
            prompt,
            temperature,
            nodes_to_sample,
        })) => {
            let digest = gate::send_prompt_to_ipfs(
                &mut context.with_optional_atoma_package_id(package),
                &model,
                &prompt,
                max_tokens,
                temperature,
                max_fee_per_token,
                nodes_to_sample,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Gate(GateCmds::SendPromptToGateway {
            package,
            model,
            prompt,
            max_tokens,
            temperature,
            gateway_user_id,
            max_fee_per_token,
            nodes_to_sample,
        })) => {
            let digest = gate::send_prompt_to_gateway(
                &mut context.with_optional_atoma_package_id(package),
                &model,
                &prompt,
                max_tokens,
                temperature,
                max_fee_per_token,
                &gateway_user_id,
                nodes_to_sample,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Gate(GateCmds::SendImagePrompt {
            package,
            model,
            prompt,
            height,
            width,
            max_fee_per_input_token,
            max_fee_per_output_token,
            output_destination,
            nodes_to_sample,
        })) => {
            let digest = gate::send_image_prompt(
                &mut context.with_optional_atoma_package_id(package),
                &model,
                &prompt,
                height,
                width,
                max_fee_per_input_token,
                max_fee_per_output_token,
                output_destination,
                nodes_to_sample,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Gate(GateCmds::SendImagePromptToIpfs {
            package,
            model,
            prompt,
            height,
            width,
            max_fee_per_input_token,
            max_fee_per_output_token,
            nodes_to_sample,
        })) => {
            let digest = gate::send_image_prompt_to_ipfs(
                &mut context.with_optional_atoma_package_id(package),
                &model,
                &prompt,
                height,
                width,
                max_fee_per_input_token,
                max_fee_per_output_token,
                nodes_to_sample,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Gate(GateCmds::SendImagePromptToGateway {
            package,
            model,
            prompt,
            height,
            width,
            max_fee_per_input_token,
            max_fee_per_output_token,
            gateway_user_id,
            nodes_to_sample,
        })) => {
            let digest = gate::send_image_prompt_to_gateway(
                &mut context.with_optional_atoma_package_id(package),
                &model,
                &prompt,
                height,
                width,
                &gateway_user_id,
                max_fee_per_input_token,
                max_fee_per_output_token,
                nodes_to_sample,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Settle(SettlementCmds::ListTickets { package })) => {
            settle::list_tickets(
                &mut context.with_optional_atoma_package_id(package),
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
        Some(Cmds::Toma(TomaCmds::Faucet {
            toma_package,
            amount,
        })) => {
            let digest = toma::faucet(
                &mut context.with_optional_toma_package_id(toma_package),
                amount,
            )
            .await?;

            println!("{digest}");
        }
        None => {}
    }

    Ok(())
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

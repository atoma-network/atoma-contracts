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
use sui_sdk::types::{
    base_types::ObjectID, dynamic_field::DynamicFieldName, TypeTag,
};

use crate::{dotenv_conf::DotenvConf, prelude::*};

const DB_MANAGER_TYPE_NAME: &str = "AtomaManagerBadge";
const DB_MODULE_NAME: &str = "db";
const DB_NODE_TYPE_NAME: &str = "NodeBadge";
const DB_TASK_TYPE_NAME: &str = "TaskBadge";
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
    /// Create a new task entry in the database
    CreateTaskEntry {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The role ID for this task
        #[arg(short, long)]
        role: u16,
        /// Optional model name for this task
        #[arg(short, long)]
        model_name: Option<String>,
        /// Optional security level for this task
        #[arg(short, long)]
        security_level: Option<u16>,
        /// Optional minimum reputation score required for this task
        #[arg(short = 'r', long)]
        minimum_reputation_score: Option<u8>,
    },
    /// Deprecates a task in the database.
    /// This command marks a task as deprecated, preventing new subscriptions.
    /// Existing subscriptions and ongoing work are not affected.
    DeprecateTask {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The ObjectID of the TaskBadge for the task to be deprecated.
        #[arg(short, long)]
        task_badge: String,
    },
    /// Removes a deprecated task from the database.
    /// This command completely removes a task that has been previously deprecated.
    /// It should only be used when you're certain the task is no longer needed.
    RemoveDeprecatedTask {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The ObjectID of the TaskBadge for the deprecated task to be removed.
        #[arg(short, long)]
        task_badge: String,
    },
    /// Command to subscribe a node to a specific task in the Atoma network.
    SubscribeNodeToTask {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The small ID of the task to subscribe to. This is a unique identifier for the task.
        #[arg(short, long)]
        task_small_id: u64,
        /// The price per compute unit that the node is willing to charge for this task.
        /// This value is in the smallest unit of the network's native currency.
        #[arg(short, long)]
        price_per_compute_unit: u64,
        /// The maximum number of compute units that the node is willing to provide for this task.
        /// This limits the node's commitment to the task.
        #[arg(short, long)]
        max_num_compute_units: u64,
    },
    /// Unsubscribe a node from a specific task in the Atoma network.
    /// This command removes a node's subscription to a task, preventing it from receiving further work for that task.
    UnsubscribeNodeFromTask {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The small ID of the task to unsubscribe from. This is a unique identifier for the task.
        #[arg(short, long)]
        task_small_id: u64,
    },
    /// Acquires a new stack entry for a specific task.
    /// This command allows a node to request a new stack entry, which represents
    /// a unit of work to be performed for a given task.
    AcquireNewStackEntry {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The small ID of the task for which to acquire a new stack entry.
        /// This ID uniquely identifies the task within the Atoma network.
        #[arg(short, long)]
        task_small_id: u64,
        /// The number of compute units requested for this stack entry.
        /// This represents the amount of computational work the node is willing to perform.
        #[arg(short, long)]
        num_compute_units: u64,
        /// The price (in smallest unit of the network's native currency) that the node
        /// is charging for the requested compute units.
        /// This should be calculated based on the task's requirements and the node's pricing strategy.
        #[arg(short, long)]
        price: u64,
    },
    /// Attempts to settle a stack entry in the Atoma network.
    /// This command is used by nodes to finalize their work on a stack entry
    /// and claim the associated rewards.
    TrySettleStack {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The small ID of the stack entry to be settled.
        /// This is a unique identifier for the stack within the Atoma network.
        #[arg(short, long)]
        stack_small_id: u64,
        /// The number of compute units claimed by the node for this stack entry.
        /// This should reflect the actual work performed by the node.
        #[arg(short, long)]
        num_claimed_compute_units: u64,
        /// The committed stack proof, which is used to verify the node's work.
        /// This is typically a cryptographic proof or hash of the work performed.
        #[arg(short, long)]
        committed_stack_proof: Vec<u8>,
        /// The Merkle leaf for this stack entry.
        /// This is part of the Merkle tree structure used for efficient verification
        /// of the stack's state within the larger Atoma database.
        #[arg(short, long)]
        stack_merkle_leaf: Vec<u8>,
    },
    /// Submits a stack settlement attestation for a completed task.
    /// This command is used by nodes to provide proof of work completion
    /// and initiate the settlement process for a stack entry.
    SubmitStackSettlementAttestation {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The small ID of the stack entry for which the attestation is being submitted.
        /// This is a unique identifier for the stack within the Atoma network.
        #[arg(short, long)]
        stack_small_id: u64,
        /// The committed stack proof, which is used to verify the node's work.
        /// This is typically a cryptographic proof or hash of the work performed.
        #[arg(short, long)]
        committed_stack_proof: Vec<u8>,
        /// The Merkle leaf for this stack entry.
        /// This is part of the Merkle tree structure used for efficient verification
        /// of the stack's state within the larger Atoma database.
        #[arg(short, long)]
        stack_merkle_leaf: Vec<u8>,
    },
    /// Claims funds for settled tickets in the Atoma network.
    /// This command allows a node to claim the rewards for successfully completed and settled tasks.
    ClaimFunds {
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// A list of settled stack small IDs for which the node can claim funds.
        /// Each ID represents a completed and settled stack that the node has performed.
        #[arg(short, long)]
        settled_ticket_ids: Vec<u64>,
    },
    /// Start an attestation dispute for a stack entry.
    /// This can only be done by a selected attestation node,
    /// and should only be done when the attestation node disagrees with the committed stack proof,
    /// by the original selected node.
    StartAttestationDispute { 
        /// Optional package ID. If not provided, the default from the environment will be used.
        #[arg(short, long)]
        package: Option<String>,
        /// The small ID of the stack entry for which the attestation is being disputed.
        /// This is a unique identifier for the stack within the Atoma network.
        #[arg(short, long)]
        stack_small_id: u64,
        /// The commitment to the stack entry that is being disputed.
        /// This is typically a cryptographic proof or hash of the work performed.  
        #[arg(short, long)]
        attestation_commitment: Vec<u8>,
    }
}

#[derive(Subcommand)]
enum GateCmds {
    /// Submits an example prompt to the network.
    SubmitTellMeAJokePrompt {
        #[arg(short, long)]
        package: Option<String>,
        #[arg(short, long)]
        model: String,
        #[arg(long, default_value_t = 1_000)]
        max_fee_per_token: u64,
    },
    /// Submits an example prompt to the network.
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
        Some(Cmds::Db(DbCmds::CreateTaskEntry {
            package,
            role,
            model_name,
            security_level,
            minimum_reputation_score,
        })) => {
            let digest = db::create_task_entry(
                &mut context.with_optional_atoma_package_id(package),
                role,
                model_name,
                security_level,
                minimum_reputation_score,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::DeprecateTask {
            package,
            task_badge,
        })) => {
            let digest = db::deprecate_task(
                &mut context.with_optional_atoma_package_id(package),
                ObjectID::from_str(&task_badge)?,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::RemoveDeprecatedTask {
            package,
            task_badge,
        })) => {
            let digest = db::remove_deprecated_task(
                &mut context.with_optional_atoma_package_id(package),
                ObjectID::from_str(&task_badge)?,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::SubscribeNodeToTask {
            package,
            task_small_id,
            price_per_compute_unit,
            max_num_compute_units,
        })) => {
            let digest = db::subscribe_node_to_task(
                &mut context.with_optional_atoma_package_id(package),
                task_small_id,
                price_per_compute_unit,
                max_num_compute_units,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::UnsubscribeNodeFromTask {
            package,
            task_small_id,
        })) => {
            let digest = db::unsubscribe_node_from_task(
                &mut context.with_optional_atoma_package_id(package),
                task_small_id,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::AcquireNewStackEntry {
            package,
            task_small_id,
            num_compute_units,
            price,
        })) => {
            let digest = db::acquire_new_stack_entry(
                &mut context.with_optional_atoma_package_id(package),
                task_small_id,
                num_compute_units,
                price,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::TrySettleStack {
            package,
            stack_small_id,
            num_claimed_compute_units,
            committed_stack_proof,
            stack_merkle_leaf,
        })) => {
            let digest = db::try_settle_stack(
                &mut context.with_optional_atoma_package_id(package),
                stack_small_id,
                num_claimed_compute_units,
                committed_stack_proof,
                stack_merkle_leaf,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::ClaimFunds {
            package,
            settled_ticket_ids,
        })) => {
            let digest = db::claim_funds(
                &mut context.with_optional_atoma_package_id(package),
                settled_ticket_ids,
            )
            .await?;
            
            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::SubmitStackSettlementAttestation {
            package,
            stack_small_id,
            committed_stack_proof,
            stack_merkle_leaf,
        })) => {
            let digest = db::submit_stack_settlement_attestation(
                &mut context.with_optional_atoma_package_id(package),
                stack_small_id,
                committed_stack_proof,
                stack_merkle_leaf,
            )
            .await?;

            println!("{digest}");
        }
        Some(Cmds::Db(DbCmds::StartAttestationDispute {
            package,
            stack_small_id,
            attestation_commitment,
        })) => {
            let digest = db::start_attestation_dispute(
                &mut context.with_optional_atoma_package_id(package),
                stack_small_id,
                attestation_commitment,
            )
            .await?;

            println!("{digest}");
        }
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
        Some(Cmds::Gate(GateCmds::SubmitTellMeAJokePrompt {
            package,
            model,
            max_fee_per_token,
        })) => {
            let digest = gate::submit_tell_me_a_joke_prompt(
                &mut context.with_optional_atoma_package_id(package),
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
                &mut context.with_optional_atoma_package_id(package),
                &model,
                max_fee_per_token,
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

use std::{path::Path, str::FromStr};

use sui_sdk::{
    json::SuiJsonValue, types::digests::TransactionDigest, wallet_context::WalletContext,
};

use crate::{get_atoma_db, GATE_MODULE_NAME};

const ENDPOINT_NAME: &str = "submit_example_text_prompt";

pub(crate) async fn command(
    wallet: &mut WalletContext,
    package: &str,
    model_name: &str,
    prompt_path: &Path,
    nodes_to_sample: u64,
    gas_budget: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    if !prompt_path.exists() {
        return Err(anyhow::anyhow!("Prompt file does not exist"));
    }

    let prompt = std::fs::read_to_string(prompt_path)?;
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = FromStr::from_str(package)?;
    let atoma_db = get_atoma_db(&client, package).await?;

    let tx = client
        .transaction_builder()
        .move_call(
            active_address,
            package,
            GATE_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::new(model_name.into())?,
                SuiJsonValue::new(prompt.into())?,
                SuiJsonValue::new(nodes_to_sample.to_string().into())?,
            ],
            None,
            gas_budget,
        )
        .await?;

    let tx = wallet.sign_transaction(&tx);
    let resp = wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

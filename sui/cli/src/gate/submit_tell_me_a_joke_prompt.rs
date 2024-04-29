use std::str::FromStr;

use crate::{
    find_toma_token_wallets, get_atoma_db, get_prompts, prelude::*,
    PROMPTS_MODULE_NAME,
};

const ENDPOINT_NAME: &str = "tell_me_a_joke";

pub(crate) async fn command(
    wallet: &mut WalletContext,
    package: &str,
    model_name: &str,
    max_fee_per_token: u64,
    gas_budget: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = FromStr::from_str(package)?;
    let atoma_db = get_atoma_db(&client, package).await?;
    let prompts = get_prompts(&client, package).await?;

    let toma_wallet = find_toma_token_wallets(&client, package, active_address)
        .await?
        .next()
        .ok_or_else(|| {
            anyhow::anyhow!("No TOMA wallet found for the package")
        })?;

    let tx = client
        .transaction_builder()
        .move_call(
            active_address,
            package,
            PROMPTS_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::from_object_id(prompts),
                SuiJsonValue::from_object_id(toma_wallet),
                SuiJsonValue::new(model_name.into())?,
                SuiJsonValue::new(max_fee_per_token.to_string().into())?,
            ],
            None,
            gas_budget,
        )
        .await?;

    let tx = wallet.sign_transaction(&tx);
    let resp = wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

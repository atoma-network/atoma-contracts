use crate::{prelude::*, PROMPTS_MODULE_NAME};

const ENDPOINT_NAME: &str = "tell_me_a_joke";

pub(crate) async fn command(
    context: &mut Context,
    model_name: &str,
    max_fee_per_token: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = context.wallet.get_client().await?;
    let active_address = context.wallet.active_address()?;
    let package = context.unwrap_package_id();
    let atoma_db = context.get_or_load_atoma_db(&client).await?;
    let prompts = context.get_or_load_prompts(&client).await?;
    let toma_wallet = context.get_or_load_toma_wallet(&client).await?;

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
            context.gas_budget(),
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

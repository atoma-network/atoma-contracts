use sui_sdk::types::SUI_RANDOMNESS_STATE_OBJECT_ID;

use crate::{prelude::*, PROMPTS_MODULE_NAME};

const ENDPOINT_NAME: &str = "generate_nft";

pub(crate) async fn command(
    context: &mut Context,
    model_name: &str,
    max_fee_per_token: u64,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let atoma_package = context.unwrap_atoma_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let toma_wallet = context.get_or_load_toma_wallet().await?;

    // TODO: agree with nodes on some output destination format
    let output_destination: Vec<u8> = vec![];

    let tx = context
        .get_client()
        .await?
        .transaction_builder()
        .move_call(
            active_address,
            atoma_package,
            PROMPTS_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::from_object_id(toma_wallet),
                SuiJsonValue::new(model_name.into())?,
                SuiJsonValue::new(output_destination.into())?,
                SuiJsonValue::new(max_fee_per_token.to_string().into())?,
                SuiJsonValue::from_object_id(SUI_RANDOMNESS_STATE_OBJECT_ID),
            ],
            None,
            context.gas_budget(),
            None,
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

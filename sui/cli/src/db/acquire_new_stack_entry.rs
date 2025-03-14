use sui_sdk::types::SUI_RANDOMNESS_STATE_OBJECT_ID;

use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "acquire_new_stack_entry";

pub(crate) async fn command(
    context: &mut Context,
    task_small_id: u64,
    num_compute_units: u64,
    price: u64,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let atoma_package = context.unwrap_atoma_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let toma_wallet = context.get_or_load_toma_wallet().await?;

    let tx = context
        .get_client()
        .await?
        .transaction_builder()
        .move_call(
            active_address,
            atoma_package,
            DB_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::from_object_id(toma_wallet),
                SuiJsonValue::new(task_small_id.to_string().into())?,
                SuiJsonValue::new(num_compute_units.to_string().into())?,
                SuiJsonValue::new(price.to_string().into())?,
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

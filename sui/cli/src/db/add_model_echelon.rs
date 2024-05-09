use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "add_model_echelon_entry";

pub(crate) async fn command(
    context: &mut Context,
    model_name: &str,
    echelon: u64,
    fee_in_protocol_token: u64,
    relative_performance: u64,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let package = context.unwrap_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let manager_badge = context.get_or_load_db_manager_badge().await?;

    let tx = context
        .get_client()
        .await?
        .transaction_builder()
        .move_call(
            active_address,
            package,
            DB_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::from_object_id(manager_badge),
                SuiJsonValue::new(model_name.into())?,
                SuiJsonValue::new(echelon.to_string().into())?,
                SuiJsonValue::new(fee_in_protocol_token.to_string().into())?,
                SuiJsonValue::new(relative_performance.to_string().into())?,
            ],
            None,
            context.gas_budget(),
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}
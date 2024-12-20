use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "update_node_subscription";

pub(crate) async fn command(
    context: &mut Context,
    task_small_id: u64,
    price_per_one_million_compute_units: u64,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let atoma_package = context.unwrap_atoma_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let (node_badge, _) = context.get_or_load_node_badge().await?;

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
                SuiJsonValue::from_object_id(node_badge),
                SuiJsonValue::new(task_small_id.to_string().into())?,
                SuiJsonValue::new(
                    price_per_one_million_compute_units.to_string().into(),
                )?,
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

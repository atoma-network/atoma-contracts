use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "new_network_key_rotation";

pub(crate) async fn command(
    context: &mut Context,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let atoma_package = context.unwrap_atoma_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let manager_badge = context.get_or_load_db_manager_badge().await?;

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
                SuiJsonValue::from_object_id(manager_badge),
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

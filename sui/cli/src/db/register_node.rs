use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "register_node_entry";

pub(crate) async fn command(
    context: &mut Context,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = context.wallet.get_client().await?;
    let active_address = context.wallet.active_address()?;
    let package = context.unwrap_package_id();
    let atoma_db = context.get_or_load_atoma_db(&client).await?;
    let toma_wallet = context.get_or_load_toma_wallet(&client).await?;

    // we could also filter by the required collateral amount to even more
    // specific before needing to implement pagination

    let tx = client
        .transaction_builder()
        .move_call(
            active_address,
            package,
            DB_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::from_object_id(toma_wallet),
            ],
            None,
            context.gas_budget(),
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

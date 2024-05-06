use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "add_node_to_model";

pub(crate) async fn command(
    context: &mut Context,
    model_name: &str,
    echelon: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    let active_address = context.wallet.active_address()?;
    let package = context.unwrap_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let (node_badge, _) = context.get_or_load_node_badge().await?;

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
                SuiJsonValue::new(model_name.into())?,
                SuiJsonValue::new(echelon.to_string().into())?,
                SuiJsonValue::from_object_id(node_badge),
            ],
            None,
            context.gas_budget(),
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

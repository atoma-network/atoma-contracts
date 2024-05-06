use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "set_required_registration_toma_collateral";

pub(crate) async fn command(
    context: &mut Context,
    new_required_collateral_amount: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = context.wallet.get_client().await?;
    let active_address = context.wallet.active_address()?;
    let package = context.unwrap_package_id();
    let atoma_db = context.get_or_load_atoma_db(&client).await?;
    let manager_badge = context.get_or_load_db_manager_badge(&client).await?;

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
                SuiJsonValue::new(
                    new_required_collateral_amount.to_string().into(),
                )?,
                SuiJsonValue::from_object_id(manager_badge),
            ],
            None,
            context.gas_budget(),
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "create_task_entry";

pub(crate) async fn command(
    context: &mut Context,
    role: u16,
    model_name: Option<String>,
    security_level: Option<u16>,
    minimum_reputation_score: Option<u8>,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let atoma_package = context.unwrap_atoma_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;

    let model_name = model_name.map(|v| vec![v]).unwrap_or_default();
    let security_level = security_level
        .map(|v| vec![v.to_string()])
        .unwrap_or_default();
    let minimum_reputation_score = minimum_reputation_score
        .map(|v| vec![v.to_string()])
        .unwrap_or_default();

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
                SuiJsonValue::new(role.to_string().into())?,
                SuiJsonValue::new(model_name.into())?,
                SuiJsonValue::new(security_level.into())?,
                SuiJsonValue::new(minimum_reputation_score.into())?,
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

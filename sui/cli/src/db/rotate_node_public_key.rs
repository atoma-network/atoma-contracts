use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "rotate_node_public_key";

pub(crate) async fn command(
    context: &mut Context,
    new_public_key_commitment: Vec<u8>,
    evidence_bytes: Vec<u8>,
    key_rotation_counter: u64,
    device_type: u16,
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
                SuiJsonValue::new(new_public_key_commitment.into())?,
                SuiJsonValue::new(evidence_bytes.into())?,
                SuiJsonValue::new(key_rotation_counter.to_string().into())?,
                SuiJsonValue::new(device_type.into())?,
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

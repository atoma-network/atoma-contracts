use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "try_settle_stack";

pub(crate) async fn command(
    context: &mut Context,
    stack_small_id: u64,
    num_claimed_compute_units: u64,
    committed_stack_proof: Vec<u8>,
    stack_merkle_leaf: Vec<u8>,
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
                SuiJsonValue::new(stack_small_id.into())?,
                SuiJsonValue::new(num_claimed_compute_units.into())?,
                SuiJsonValue::new(committed_stack_proof.into())?,
                SuiJsonValue::new(stack_merkle_leaf.into())?,
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

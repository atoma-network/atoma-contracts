use sui_sdk::types::SUI_RANDOMNESS_STATE_OBJECT_ID;

use crate::{prelude::*, SETTLEMENT_MODULE_NAME};

const ENDPOINT_NAME: &str = "try_to_settle";

pub(crate) async fn command(
    context: &mut Context,
    ticket_id: &str,
) -> Result<TransactionDigest> {
    let ticket_id = FromStr::from_str(ticket_id)?;
    let (package, _) = context.ticket_package_and_fields(ticket_id).await?;
    let active_address = context.wallet.active_address()?;

    let atoma_db = context.get_or_load_atoma_db().await?;
    let tx = context
        .get_client()
        .await?
        .transaction_builder()
        .move_call(
            active_address,
            package,
            SETTLEMENT_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::from_object_id(ticket_id),
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

use sui_sdk::types::base_types::ObjectID;

use crate::{prelude::*, TOMA_COIN_MODULE_NAME};

const ENDPOINT_NAME: &str = "faucet";
const FAUCET_OBJECT_ID: &str =
    "0xfdddd6fb95509ea36f44f06d0d0a2f5868dac2bda1423d204bdc9f458115ff75";

/// If Toma package ID is not provided, we use the env vars.
pub(crate) async fn command(
    context: &mut Context,
    amount: u64,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let sui = context.get_client().await?;
    let toma_package = context.get_or_load_toma_package_id().await?;
    // let faucet = context.get_or_load_faucet_id().await?;

    let tx = sui
        .transaction_builder()
        .move_call(
            active_address,
            toma_package,
            TOMA_COIN_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(ObjectID::from_str(
                    FAUCET_OBJECT_ID,
                )?),
                SuiJsonValue::new(amount.to_string().into())?,
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

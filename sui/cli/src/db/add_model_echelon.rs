use std::str::FromStr;

use crate::{get_atoma_db, get_db_manager_badge, prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "add_model_echelon_entry";

pub(crate) async fn command(
    wallet: &mut WalletContext,
    package: &str,
    model_name: &str,
    echelon: u64,
    fee_in_protocol_token: u64,
    relative_performance: u64,
    gas_budget: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = FromStr::from_str(package)?;
    let atoma_db = get_atoma_db(&client, package).await?;
    let manager_badge =
        get_db_manager_badge(&client, package, active_address).await?;

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
                SuiJsonValue::new(model_name.into())?,
                SuiJsonValue::new(echelon.to_string().into())?,
                SuiJsonValue::new(fee_in_protocol_token.to_string().into())?,
                SuiJsonValue::new(relative_performance.to_string().into())?,
                SuiJsonValue::from_object_id(manager_badge),
            ],
            None,
            gas_budget,
        )
        .await?;

    let tx = wallet.sign_transaction(&tx);
    let resp = wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

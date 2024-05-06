use crate::{get_node_badge, prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "add_node_to_model";

pub(crate) async fn command(
    conf: &DotenvConf,
    wallet: &mut WalletContext,
    model_name: &str,
    echelon: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = conf.unwrap_package_id();
    let atoma_db = conf.get_or_load_atoma_db(&client).await?;
    let (node_badge, _) =
        get_node_badge(&client, package, active_address).await?;

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
                SuiJsonValue::from_object_id(node_badge),
            ],
            None,
            conf.gas_budget(),
        )
        .await?;

    let tx = wallet.sign_transaction(&tx);
    let resp = wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

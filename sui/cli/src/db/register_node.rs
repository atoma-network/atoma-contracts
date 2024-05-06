use crate::{find_toma_token_wallets, prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "register_node_entry";

pub(crate) async fn command(
    conf: &DotenvConf,
    wallet: &mut WalletContext,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = conf.unwrap_package_id();
    let atoma_db = conf.get_or_load_atoma_db(&client).await?;

    let toma_wallet = find_toma_token_wallets(&client, package, active_address)
        .await?
        .next()
        .ok_or_else(|| {
            anyhow::anyhow!("No TOMA wallet found for the package")
        })?;

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
            conf.gas_budget(),
        )
        .await?;

    let tx = wallet.sign_transaction(&tx);
    let resp = wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

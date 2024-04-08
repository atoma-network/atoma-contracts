use std::str::FromStr;

use move_core_types::language_storage::StructTag;
use sui_sdk::{
    json::SuiJsonValue,
    rpc_types::{Page, SuiObjectDataFilter, SuiObjectResponseQuery},
    types::{
        base_types::{ObjectID, SuiAddress},
        digests::TransactionDigest,
        TypeTag,
    },
    wallet_context::WalletContext,
    SuiClient,
};

use crate::{get_atoma_db, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "register_node_entry";

pub(crate) async fn command(
    wallet: &mut WalletContext,
    package: &str,
    gas_budget: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = FromStr::from_str(package)?;
    let atoma_db = get_atoma_db(&client, package).await?;

    let toma_wallet = find_toma_token_wallets(&client, package, active_address)
        .await?
        .next()
        .ok_or_else(|| anyhow::anyhow!("No TOMA wallet found for the package"))?;

    // TODO: we could also filter by the required collateral amount

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
            gas_budget,
        )
        .await?;

    let tx = wallet.sign_transaction(&tx);
    let resp = wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

async fn find_toma_token_wallets(
    client: &SuiClient,
    package: ObjectID,
    active_address: SuiAddress,
) -> Result<impl Iterator<Item = ObjectID>, anyhow::Error> {
    let type_ = StructTag {
        address: SuiAddress::from_str(
            "0x0000000000000000000000000000000000000000000000000000000000000002",
        )
        .unwrap()
        .into(),
        module: FromStr::from_str("coin")?,
        name: FromStr::from_str("Coin")?,
        type_params: vec![TypeTag::Struct(Box::new(StructTag {
            address: package.into(),
            module: FromStr::from_str("toma")?,
            name: FromStr::from_str("TOMA")?,
            type_params: vec![],
        }))],
    };

    let Page { data, .. } = client
        .read_api()
        .get_owned_objects(
            active_address,
            Some(SuiObjectResponseQuery {
                filter: Some(SuiObjectDataFilter::StructType(type_)),
                options: None,
            }),
            None,
            None,
        )
        .await?;

    Ok(data
        .into_iter()
        .filter_map(|resp| Some(resp.data?.object_id)))
}

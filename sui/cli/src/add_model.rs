use std::str::FromStr;

use sui_sdk::{
    json::SuiJsonValue,
    rpc_types::{Page, SuiObjectDataFilter, SuiObjectDataOptions, SuiObjectResponseQuery},
    types::{base_types::ObjectType, digests::TransactionDigest},
    wallet_context::WalletContext,
};

use crate::{get_atoma_db, DB_MANAGER_TYPE_NAME, DB_MODULE_NAME};

const ADD_MODEL_ENDPOINT_NAME: &str = "add_model_entry";

pub(crate) async fn command(
    wallet: &mut WalletContext,
    package: &str,
    model_name: &str,
    gas_budget: u64,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = FromStr::from_str(&package)?;
    let atoma_db = get_atoma_db(&client, package).await?;

    let Page {
        data,
        has_next_page,
        ..
    } = client
        .read_api()
        .get_owned_objects(
            active_address,
            Some(SuiObjectResponseQuery {
                filter: Some(SuiObjectDataFilter::Package(package)),
                options: Some(SuiObjectDataOptions {
                    show_type: true,
                    ..Default::default()
                }),
            }),
            None,
            None,
        )
        .await?;
    assert!(!has_next_page, "We don't support pagination yet");

    let manager_badge = data
        .into_iter()
        .find_map(|resp| {
            let object = resp.data?;

            let ObjectType::Struct(type_) = object.type_? else {
                return None;
            };

            if type_.module().as_str() == DB_MODULE_NAME
                && type_.name().as_str() == DB_MANAGER_TYPE_NAME
            {
                Some(object.object_id)
            } else {
                None
            }
        })
        .expect("No AtomaManagerBadge found for the package");

    let tx = client
        .transaction_builder()
        .move_call(
            active_address,
            package,
            DB_MODULE_NAME,
            ADD_MODEL_ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::new(model_name.into())?,
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

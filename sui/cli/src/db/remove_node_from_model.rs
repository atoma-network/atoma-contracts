use move_core_types::{
    account_address::AccountAddress, language_storage::StructTag,
};
use sui_sdk::{
    rpc_types::SuiData,
    types::{dynamic_field::DynamicFieldName, TypeTag},
};

use crate::{prelude::*, DB_MODULE_NAME};

const ENDPOINT_NAME: &str = "remove_node_from_model";

/// 1. Find out what echelon is the node in by querying the node badge
/// 2. Find the node index within the model echelon
/// 3. Call the remove_node_from_model endpoint, ask to retry if fails due to
///    concurrent modification
pub(crate) async fn command(
    context: &mut Context,
    model_name: &str,
) -> Result<TransactionDigest> {
    let (node_badge, _) = context.get_or_load_node_badge().await?;

    // 1.
    let echelon_id = context
        .get_client()
        .await?
        .read_api()
        .get_dynamic_field_object(
            node_badge,
            DynamicFieldName {
                type_: TypeTag::Struct(Box::new(StructTag {
                    address: AccountAddress::ONE,
                    module: FromStr::from_str("ascii")?,
                    name: FromStr::from_str("String")?,
                    type_params: vec![],
                })),
                value: serde_json::Value::String(model_name.to_owned()),
            },
        )
        .await
        .inspect(|data| {
            if let Some(err) = data.error.as_ref() {
                println!("{err:?}");
            }
        })?
        .data
        .ok_or_else(|| anyhow!("Node not subscribed to {model_name}"))?
        .content
        .unwrap()
        .try_into_move()
        .unwrap()
        .fields
        .to_json_value()["value"]["id"]
        .as_str()
        .unwrap()
        .parse::<u64>()?;
    debug!("Echelon ID is {echelon_id}");

    // 2.
    let atoma_db_fields = context.load_atoma_db_fields().await?;
    println!("{atoma_db_fields:?}");
    let node_index = 2u64;

    // 3.
    let active_address = context.wallet.active_address()?;
    let package = context.unwrap_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let tx = context
        .get_client()
        .await?
        .transaction_builder()
        .move_call(
            active_address,
            package,
            DB_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::from_object_id(node_badge),
                SuiJsonValue::new(model_name.into())?,
                SuiJsonValue::new(node_index.to_string().into())?,
            ],
            None,
            context.gas_budget(),
        )
        .await?; // TODO: error to retry

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

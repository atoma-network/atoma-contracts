use sui_sdk::{
    rpc_types::{
        Page, SuiData, SuiExecutionStatus, SuiObjectDataOptions,
        SuiTransactionBlockEffectsAPI,
    },
    types::{base_types::ObjectID, dynamic_field::DynamicFieldName},
};

use crate::{
    prelude::*, wait_for_user_confirm, DynamicFieldNameExt, DB_MODULE_NAME,
};

const ENDPOINT_NAME: &str = "remove_node_from_model";

/// 1. Find out what echelon is the node in by querying the node badge
/// 2. Find out the object that holds vector of nodes for the echelon
/// 3. Find the node index within the model echelon
/// 4. Call the remove_node_from_model endpoint, ask to retry from 3. if this
///    fails due to concurrent modification
pub(crate) async fn command(
    context: &mut Context,
    model_name: &str,
) -> Result<TransactionDigest> {
    let (node_badge, node_id) = context.get_or_load_node_badge().await?;
    let client = context.get_client().await?;

    // 1.
    let echelon_id = client
        .read_api()
        .get_dynamic_field_object(
            node_badge,
            DynamicFieldName::ascii(model_name),
        )
        .await
        .inspect(|data| {
            if let Some(err) = data.error.as_ref() {
                println!("{err:?}");
            }
        })?
        .data
        .ok_or_else(|| anyhow!("Node not subscribed to model {model_name}"))?
        .content
        .unwrap()
        .try_into_move()
        .unwrap()
        .fields
        .to_json_value()["value"]["id"]
        .as_str()
        .unwrap()
        .to_string();
    info!(
        "Echelon ID is {echelon_id} for node {node_id} in model {model_name}"
    );

    // 2.
    let models_id = ObjectID::from_str(
        context.load_atoma_db_fields().await?["models"]["id"]["id"]
            .as_str()
            .unwrap(),
    )?;
    let model_data = client
        .read_api()
        .get_dynamic_field_object(
            models_id,
            DynamicFieldName::ascii(model_name),
        )
        .await?
        .data
        .ok_or_else(|| anyhow!("Model {model_name} not found on Atoma"))?
        .content
        .unwrap()
        .try_into_move()
        .unwrap()
        .fields
        .to_json_value();
    let model_echelon_nodes_id = model_data["echelons"]
        .as_array()
        .unwrap()
        .iter()
        .find(|echelon| echelon["id"]["id"].as_str().unwrap() == echelon_id)
        .ok_or_else(|| {
            anyhow!(
                "Echelon {echelon_id} not found in model {model_name} echelons"
            )
        })?["nodes"]["contents"]["id"]["id"]
        .as_str()
        .map(|id| ObjectID::from_str(id).unwrap())
        .unwrap();
    trace!("Model echelon nodes ID is {model_echelon_nodes_id}");

    loop {
        // 3.
        let mut cursor = None;
        let node_index: u64 = loop {
            let Page {
                has_next_page,
                next_cursor,
                data,
            } = client
                .read_api()
                .get_dynamic_fields(model_echelon_nodes_id, cursor, None)
                .await?;
            cursor = next_cursor;

            let page_ids = data.iter().map(|info| info.object_id).collect();
            let node_index = client
                .read_api()
                .multi_get_object_with_options(
                    page_ids,
                    SuiObjectDataOptions {
                        show_content: true,
                        ..Default::default()
                    },
                )
                .await?
                .into_iter()
                .find_map(|info| {
                    let info = info
                        .data?
                        .content?
                        .try_into_move()?
                        .fields
                        .to_json_value();
                    if node_id
                        == info["value"]["inner"]
                            .as_str()
                            .unwrap()
                            .parse::<u64>()
                            .ok()?
                    {
                        Some(
                            info["name"]
                                .as_str()
                                .unwrap()
                                .parse::<u64>()
                                .ok()?,
                        )
                    } else {
                        None
                    }
                });

            if let Some(node_index) = node_index {
                break node_index;
            }

            if !has_next_page {
                anyhow::bail!("Node not found in {model_name} echelon");
            }

            debug!("Searching for node in db...");
        };

        // 4.
        let active_address = context.wallet.active_address()?;
        let atoma_package = context.unwrap_atoma_package_id();
        let atoma_db = context.get_or_load_atoma_db().await?;
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
                    SuiJsonValue::new(model_name.into())?,
                    SuiJsonValue::new((node_index).to_string().into())?,
                ],
                None,
                context.gas_budget(),
                None,
            )
            .await?;

        let tx = context.wallet.sign_transaction(&tx);
        let resp = context.wallet.execute_transaction_may_fail(tx).await?;
        if let SuiExecutionStatus::Failure { error } =
            resp.effects.as_ref().unwrap().status()
        {
            // 312012_000 + 11 is the error code as per the contract
            if error.contains(
                "function_name: Some(\"remove_node_from_model\") }, 312012011)",
            ) {
                error!(
                    "Concurrent modification of blockchain detected. \
                    This can infrequently happen. \
                    Please retry the operation. \
                    \n\nShould we retry the operation? (Y/n)"
                );

                if !wait_for_user_confirm() {
                    break Err(anyhow!("User cancelled"));
                }
            } else {
                break Err(anyhow!("Tx failed: {resp:?}"));
            }
        } else {
            break Ok(resp.digest);
        }
    }
}

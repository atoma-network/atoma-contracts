use fastcrypto::hash::{Blake2b256, HashFunction};
use sui_sdk::{rpc_types::SuiData, types::dynamic_field::DynamicFieldName};

use crate::{prelude::*, DynamicFieldNameExt, SETTLEMENT_MODULE_NAME};

const ENDPOINT_NAME: &str = "submit_commitment";

pub(crate) async fn command(
    context: &mut Context,
    ticket_id: &str,
    prompt_output: &str,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let (node_badge, node_id) = context.get_or_load_node_badge().await?;

    let ticket_id = FromStr::from_str(ticket_id)?;
    let (package, ticket) =
        context.ticket_package_and_fields(ticket_id).await?;

    let all = ticket["all"].as_array().unwrap();
    let chunk_position = all
        .iter()
        .position(|id| {
            node_id == id["inner"].as_str().unwrap().parse::<u64>().unwrap()
        })
        .ok_or_else(|| anyhow!("This node was not sampled for the ticket"))?;
    let sampled_nodes_count = all.len();
    let chunk_size = prompt_output.as_bytes().len() / sampled_nodes_count;
    assert!(chunk_size > 0);

    // TODO: use the same implementation as the node (if sampled nodes don't
    // divide the output evenly, the last chunk must be smaller)

    let merkle_leaves: Vec<u8> = prompt_output
        .as_bytes()
        .chunks(chunk_size)
        .flat_map(|chunk| Blake2b256::digest(chunk).digest.into_iter())
        .collect();
    let merkle_root = Blake2b256::digest(&merkle_leaves).digest;
    let chunk_hash =
        merkle_leaves[chunk_position * 32..(chunk_position + 1) * 32].to_vec();

    // TODO: use tokenizer or whatever implementation will the Atoma node use

    let output_tokens_count = prompt_output.len();
    let input_tokens_count = {
        let object_content = context
            .get_client()
            .await?
            .read_api()
            .get_dynamic_field_object(
                ticket_id,
                DynamicFieldName::ascii("params"),
            )
            .await?
            .data
            .ok_or_else(|| anyhow!("Ticket params not found"))?
            .content
            .unwrap();
        let json = object_content
            .try_into_move()
            .unwrap()
            .fields
            .to_json_value();
        let prompt_str = json["value"]["prompt"].as_str().unwrap();
        prompt_str.len()
    };

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
                SuiJsonValue::from_object_id(node_badge),
                SuiJsonValue::from_object_id(ticket_id),
                SuiJsonValue::new(input_tokens_count.to_string().into())?,
                SuiJsonValue::new(output_tokens_count.to_string().into())?,
                SuiJsonValue::new(merkle_root.to_vec().into())?,
                SuiJsonValue::new(chunk_hash.to_vec().into())?,
            ],
            None,
            context.gas_budget(),
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

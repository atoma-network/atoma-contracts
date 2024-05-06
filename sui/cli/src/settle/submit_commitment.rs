use fastcrypto::hash::{Blake2b256, HashFunction};
use sui_sdk::{
    rpc_types::{SuiObjectDataOptions, SuiParsedData},
    types::base_types::{ObjectID, ObjectType},
};

use crate::{
    get_node_badge, prelude::*, SETTLEMENT_MODULE_NAME,
    SETTLEMENT_TICKET_TYPE_NAME,
};

const ENDPOINT_NAME: &str = "submit_commitment";

pub(crate) async fn command(
    conf: &DotenvConf,
    wallet: &mut WalletContext,
    ticket_id: &str,
    prompt_output: &str,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = wallet.get_client().await?;

    let ticket_id = FromStr::from_str(ticket_id)?;
    let ticket = client
        .read_api()
        .get_object_with_options(
            ticket_id,
            SuiObjectDataOptions {
                show_type: true,
                show_content: true,
                ..Default::default()
            },
        )
        .await?
        .data
        .ok_or_else(|| anyhow!("Ticket not found"))?;

    let ObjectType::Struct(ticket_type) = ticket.type_.unwrap() else {
        return Err(anyhow!("Ticket type must be Struct"));
    };
    if ticket_type.module().as_str() != SETTLEMENT_MODULE_NAME
        || ticket_type.name().as_str() != SETTLEMENT_TICKET_TYPE_NAME
    {
        return Err(anyhow!(
            "Expected type \
            {SETTLEMENT_MODULE_NAME}::{SETTLEMENT_TICKET_TYPE_NAME}, \
            got {ticket_type:?}"
        ));
    };
    let package: ObjectID = ticket_type.address().into();
    if let Some(conf_package) = conf.package_id() {
        assert!(
            package == conf_package,
            "Ticket package {package} mismatches \
            configured package {conf_package}"
        );
    }

    let active_address = wallet.active_address()?;
    let (node_badge, node_id) =
        get_node_badge(&client, package, active_address).await?;

    let SuiParsedData::MoveObject(ticket) = ticket.content.unwrap() else {
        return Err(anyhow!("Ticket content must be MoveObject"));
    };
    let ticket = ticket.fields.to_json_value();
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
        .map(|chunk| Blake2b256::digest(chunk).digest.into_iter())
        .flatten()
        .collect();
    let merkle_root = Blake2b256::digest(&merkle_leaves).digest;
    let chunk_hash =
        merkle_leaves[chunk_position * 32..(chunk_position + 1) * 32].to_vec();

    let atoma_db = conf.get_or_load_atoma_db(&client).await?;
    let tx = client
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
                SuiJsonValue::new(merkle_root.to_vec().into())?,
                SuiJsonValue::new(chunk_hash.to_vec().into())?,
            ],
            None,
            conf.gas_budget(),
        )
        .await?;

    let tx = wallet.sign_transaction(&tx);
    let resp = wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

use sui_sdk::{
    rpc_types::SuiObjectDataOptions,
    types::base_types::{ObjectID, ObjectType},
};

use crate::{
    get_atoma_db, prelude::*, SETTLEMENT_MODULE_NAME,
    SETTLEMENT_TICKET_TYPE_NAME,
};

const ENDPOINT_NAME: &str = "try_to_settle";

pub(crate) async fn command(
    wallet: &mut WalletContext,
    ticket_id: &str,
    gas_budget: u64,
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
    let active_address = wallet.active_address()?;

    let atoma_db = get_atoma_db(&client, package).await?;
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
                SuiJsonValue::from_object_id(ticket_id),
            ],
            None,
            gas_budget,
        )
        .await?;

    let tx = wallet.sign_transaction(&tx);
    let resp = wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

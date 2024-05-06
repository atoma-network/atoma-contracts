use sui_sdk::{
    rpc_types::SuiObjectDataOptions,
    types::base_types::{ObjectID, ObjectType},
};

use crate::{prelude::*, SETTLEMENT_MODULE_NAME, SETTLEMENT_TICKET_TYPE_NAME};

const ENDPOINT_NAME: &str = "try_to_settle";

pub(crate) async fn command(
    context: &mut Context,
    ticket_id: &str,
) -> Result<TransactionDigest, anyhow::Error> {
    let client = context.wallet.get_client().await?;

    let ticket_id = FromStr::from_str(ticket_id)?;
    // TODO: dedup
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
    context.assert_or_store_package_id(package);
    let active_address = context.wallet.active_address()?;

    let atoma_db = context.get_or_load_atoma_db(&client).await?;
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
            context.gas_budget(),
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

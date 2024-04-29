use sui_sdk::rpc_types::{Page, SuiData, SuiMoveValue, SuiObjectDataOptions};

use crate::{get_atoma_db_id_and_fields, prelude::*, wait_for_user_confirm};

pub(crate) async fn command(
    wallet: &mut WalletContext,
    package: &str,
) -> Result<(), anyhow::Error> {
    let package = FromStr::from_str(package)?;

    let client = wallet.get_client().await?;
    let (_, fields) = get_atoma_db_id_and_fields(&client, package).await?;
    let SuiMoveValue::UID { id: tickets_root } = fields
        .get("tickets")
        .ok_or_else(|| anyhow!("No tickets field found"))?
    else {
        return Err(anyhow!("Tickets field must be UID"));
    };

    let mut cursor = None;

    loop {
        let Page {
            data,
            has_next_page,
            next_cursor,
        } = client
            .read_api()
            .get_dynamic_fields(*tickets_root, cursor, None)
            .await?;
        cursor = next_cursor;

        let tickets_page = data.iter().map(|info| info.object_id).collect();
        let tickets = client
            .read_api()
            .multi_get_object_with_options(
                tickets_page,
                SuiObjectDataOptions {
                    show_content: true,
                    ..Default::default()
                },
            )
            .await?
            .into_iter()
            // ignore tickets that have been deleted between the calls
            .filter_map(|ticket| {
                Some(
                    ticket
                        .data?
                        .content?
                        .try_as_move()
                        .cloned()?
                        .fields
                        .to_json_value(),
                )
            });

        for ticket in tickets {
            let id = ticket["id"]["id"].as_str().unwrap();
            let is_being_disputed =
                ticket["is_being_disputed"].as_bool().unwrap();
            let total_nodes_count = ticket["all"].as_array().unwrap().len();
            let completed_nodes_count =
                ticket["completed"].as_array().unwrap().len();
            let model = ticket["model_name"].as_str().unwrap();
            let echelon = ticket["echelon_id"]["id"].as_str().unwrap();
            println!("----------------------------");
            if is_being_disputed {
                print!("[DISPUTED] ");
            }
            println!("Ticket ID: {id}");
            println!("Model: {model} (echelon {echelon})");
            println!("Commitment: {completed_nodes_count}/{total_nodes_count}");
        }

        if has_next_page {
            println!();
            println!("Load next page? (Y/n)");
            if !wait_for_user_confirm() {
                break;
            }
            println!();
        } else {
            break;
        }
    }

    Ok(())
}

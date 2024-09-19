use sui_sdk::types::SUI_RANDOMNESS_STATE_OBJECT_ID;

use crate::{prelude::*, PROMPTS_MODULE_NAME};

const ENDPOINT_NAME: &str = "send_prompt";

pub(crate) async fn command(
    context: &mut Context,
    model: &str,
    prompt: &str,
    max_tokens: u64,
    temperature: f32,
    max_fee_per_token: u64,
    nodes_to_sample: Option<u64>,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let atoma_package = context.unwrap_atoma_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let toma_wallet = context.get_or_load_toma_wallet().await?;

    let pre_prompt_tokens: Vec<u32> = vec![];
    let prepend_output_with_input = true;
    let should_stream_output = false;
    let repeat_last_n = 0;
    let repeat_penalty = 1065353216; // 1.0 in f32 representation
    let top_k = 0;
    let top_p = 1065353216; // 1.0 in f32 representation
    let temperature = u32::from_le_bytes(temperature.to_le_bytes());

    let output_destination = serde_json::json!({"Ipfs": ""}); // transaction id is just if we need to retrieve the image for a frontend UI
    let mut output_destination_encoding = Vec::new();
    rmp_serde::encode::write(
        &mut output_destination_encoding,
        &output_destination,
    )
    .expect("Failed to rmp encode output destination");

    let raw_prompt_json = serde_json::json!({"Raw": prompt});
    let mut prompt_encoding = Vec::new();
    rmp_serde::encode::write(&mut prompt_encoding, &raw_prompt_json)
        .expect("Failed to rmp encode raw prompt");

    let call_args = if let Some(nodes_to_sample) = nodes_to_sample {
        vec![
            SuiJsonValue::from_object_id(atoma_db),
            SuiJsonValue::from_object_id(toma_wallet),
            SuiJsonValue::new(model.into())?,
            SuiJsonValue::new(output_destination_encoding.into())?,
            SuiJsonValue::new(pre_prompt_tokens.into())?,
            SuiJsonValue::new(prepend_output_with_input.into())?,
            SuiJsonValue::new(max_fee_per_token.to_string().into())?,
            SuiJsonValue::new(prompt_encoding.into())?,
            SuiJsonValue::new(should_stream_output.into())?,
            SuiJsonValue::new(max_tokens.to_string().into())?,
            SuiJsonValue::new(repeat_last_n.to_string().into())?,
            SuiJsonValue::new(repeat_penalty.to_string().into())?,
            SuiJsonValue::new(temperature.to_string().into())?,
            SuiJsonValue::new(top_k.to_string().into())?,
            SuiJsonValue::new(top_p.to_string().into())?,
            SuiJsonValue::new(nodes_to_sample.to_string().into())?,
            SuiJsonValue::from_object_id(SUI_RANDOMNESS_STATE_OBJECT_ID),
        ]
    } else {
        vec![
            SuiJsonValue::from_object_id(atoma_db),
            SuiJsonValue::from_object_id(toma_wallet),
            SuiJsonValue::new(model.into())?,
            SuiJsonValue::new(output_destination_encoding.into())?,
            SuiJsonValue::new(pre_prompt_tokens.into())?,
            SuiJsonValue::new(prepend_output_with_input.into())?,
            SuiJsonValue::new(max_fee_per_token.to_string().into())?,
            SuiJsonValue::new(prompt_encoding.into())?,
            SuiJsonValue::new(should_stream_output.into())?,
            SuiJsonValue::new(max_tokens.to_string().into())?,
            SuiJsonValue::new(repeat_last_n.to_string().into())?,
            SuiJsonValue::new(repeat_penalty.to_string().into())?,
            SuiJsonValue::new(temperature.to_string().into())?,
            SuiJsonValue::new(top_k.to_string().into())?,
            SuiJsonValue::new(top_p.to_string().into())?,
            SuiJsonValue::from_object_id(SUI_RANDOMNESS_STATE_OBJECT_ID),
        ]
    };
    let tx = context
        .get_client()
        .await?
        .transaction_builder()
        .move_call(
            active_address,
            atoma_package,
            PROMPTS_MODULE_NAME,
            ENDPOINT_NAME,
            vec![],
            call_args,
            None,
            context.gas_budget(),
            None,
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

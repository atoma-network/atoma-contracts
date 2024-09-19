use sui_sdk::types::SUI_RANDOMNESS_STATE_OBJECT_ID;

use crate::{prelude::*, PROMPTS_MODULE_NAME};

const ENDPOINT_NAME: &str = "send_text_prompt_to_gateway";

pub(crate) async fn command(
    context: &mut Context,
    model: &str,
    prompt: &str,
    max_tokens: u64,
    temperature: u32,
    max_fee_per_token: u64,
    gateway_user_id: &str,
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

    let output_destination = serde_json::from_value::<Vec<u8>>(
        serde_json::json!({"gateway_user_id": gateway_user_id}),
    )
    .unwrap();

    let prompt =
        serde_json::from_value::<Vec<u8>>(serde_json::json!({"raw": prompt}))
            .expect(
                "Failed to serialize the submitted prompt to binary format",
            );

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
            vec![
                SuiJsonValue::from_object_id(atoma_db),
                SuiJsonValue::from_object_id(toma_wallet),
                SuiJsonValue::new(model.into())?,
                SuiJsonValue::new(output_destination.into())?,
                SuiJsonValue::new(pre_prompt_tokens.into())?,
                SuiJsonValue::new(prepend_output_with_input.into())?,
                SuiJsonValue::new(max_fee_per_token.to_string().into())?,
                SuiJsonValue::new(prompt.into())?,
                SuiJsonValue::new(should_stream_output.into())?,
                SuiJsonValue::new(max_tokens.to_string().into())?,
                SuiJsonValue::new(repeat_last_n.to_string().into())?,
                SuiJsonValue::new(repeat_penalty.to_string().into())?,
                SuiJsonValue::new(temperature.to_string().into())?,
                SuiJsonValue::new(top_k.to_string().into())?,
                SuiJsonValue::new(top_p.to_string().into())?,
                SuiJsonValue::new(nodes_to_sample.into())?,
                SuiJsonValue::from_object_id(SUI_RANDOMNESS_STATE_OBJECT_ID),
            ],
            None,
            context.gas_budget(),
            None,
        )
        .await?;

    let tx = context.wallet.sign_transaction(&tx);
    let resp = context.wallet.execute_transaction_must_succeed(tx).await;
    Ok(resp.digest)
}

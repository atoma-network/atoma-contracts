use sui_sdk::types::SUI_RANDOMNESS_STATE_OBJECT_ID;

use crate::{prelude::*, PROMPTS_MODULE_NAME};

const ENDPOINT_NAME: &str = "send_image_generation_prompt";

pub(crate) async fn command(
    context: &mut Context,
    model: &str,
    prompt: &str,
    height: u64,
    width: u64,
    gateway_user_id: &str,
    max_fee_per_input_token: u64,
    max_fee_per_output_token: u64,
    nodes_to_sample: Option<u64>,
) -> Result<TransactionDigest> {
    let active_address = context.wallet.active_address()?;
    let atoma_package = context.unwrap_atoma_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let toma_wallet = context.get_or_load_toma_wallet().await?;

    let output_destination = serde_json::json!({"Gateway": gateway_user_id}); // transaction id is just if we need to retrieve the image for a frontend UI
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

    let output_destination = serde_json::json!({"Ipfs": ""}); // transaction id is just if we need to retrieve the image for a frontend UI
    let mut output_destination_encoding = Vec::new();
    rmp_serde::encode::write(
        &mut output_destination_encoding,
        &output_destination,
    )
    .expect("Failed to rmp encode output destination");

    let guidance_scale = 1065353216; // 1.0
    let img2img_strength = 0;
    let num_samples = 1;
    let n_steps = 32;

    let call_args = if let Some(nodes_to_sample) = nodes_to_sample {
        vec![
            SuiJsonValue::from_object_id(atoma_db),
            SuiJsonValue::from_object_id(toma_wallet),
            SuiJsonValue::new(model.into())?,
            SuiJsonValue::new(guidance_scale.to_string().into())?,
            SuiJsonValue::new(prompt.into())?,
            SuiJsonValue::new("".into())?,
            SuiJsonValue::new(height.to_string().into())?,
            SuiJsonValue::new(img2img_strength.to_string().into())?,
            SuiJsonValue::new(num_samples.to_string().into())?,
            SuiJsonValue::new(n_steps.to_string().into())?,
            SuiJsonValue::new(output_destination.into())?,
            SuiJsonValue::new(width.to_string().into())?,
            SuiJsonValue::new(max_fee_per_input_token.to_string().into())?,
            SuiJsonValue::new(max_fee_per_output_token.to_string().into())?,
            SuiJsonValue::new(nodes_to_sample.into())?,
            SuiJsonValue::from_object_id(SUI_RANDOMNESS_STATE_OBJECT_ID),
        ]
    } else {
        vec![
            SuiJsonValue::from_object_id(atoma_db),
            SuiJsonValue::from_object_id(toma_wallet),
            SuiJsonValue::new(model.into())?,
            SuiJsonValue::new(guidance_scale.to_string().into())?,
            SuiJsonValue::new(prompt.into())?,
            SuiJsonValue::new("".into())?,
            SuiJsonValue::new(height.to_string().into())?,
            SuiJsonValue::new(img2img_strength.to_string().into())?,
            SuiJsonValue::new(num_samples.to_string().into())?,
            SuiJsonValue::new(n_steps.to_string().into())?,
            SuiJsonValue::new(output_destination.into())?,
            SuiJsonValue::new(width.to_string().into())?,
            SuiJsonValue::new(max_fee_per_input_token.to_string().into())?,
            SuiJsonValue::new(max_fee_per_output_token.to_string().into())?,
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

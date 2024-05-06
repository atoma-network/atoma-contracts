use crate::prelude::*;

pub(crate) async fn command(
    context: &mut Context,
) -> Result<(), anyhow::Error> {
    let client = context.wallet.get_client().await?;
    let package = context.unwrap_package_id();
    let atoma_db = context.get_or_load_atoma_db(&client).await?;
    let manager_badge = context.get_or_load_db_manager_badge(&client).await?;
    let (node_badge, node_id) = context.get_or_load_node_badge(&client).await?;
    let toma_wallet = context.get_or_load_toma_wallet(&client).await.ok();
    let prompt_standards = context.get_or_load_prompts(&client).await?;

    println!("WALLET_PATH={}", context.unwrap_wallet_path().display());
    println!("PACKAGE_ID={package}");
    println!("ATOMA_DB_ID={atoma_db}");
    println!("MANAGER_BADGE_ID={manager_badge}");
    println!("NODE_BADGE_ID={node_badge}");
    println!("NODE_ID={node_id}");
    println!("PROMPT_STANDARDS_ID={prompt_standards}");
    if let Some(toma_wallet) = toma_wallet {
        println!("TOMA_WALLET_ID={toma_wallet}");
    } else {
        println!("TOMA_WALLET_ID=");
    }

    Ok(())
}

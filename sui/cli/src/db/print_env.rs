use crate::prelude::*;

pub(crate) async fn command(context: &mut Context) -> Result<()> {
    let package = context.unwrap_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let manager_badge = context.get_or_load_db_manager_badge().await?;
    let node_info = context.get_or_load_node_badge().await.ok();
    let toma_wallet = context.get_or_load_toma_wallet().await.ok();
    let prompt_standards = context.get_or_load_prompts().await?;

    println!("WALLET_PATH={}", context.unwrap_wallet_path().display());
    println!("PACKAGE_ID={package}");
    println!("ATOMA_DB_ID={atoma_db}");
    println!("MANAGER_BADGE_ID={manager_badge}");
    println!("PROMPT_STANDARDS_ID={prompt_standards}");
    if let Some((node_badge, node_id)) = node_info {
        println!("NODE_BADGE_ID={node_badge}");
        println!("NODE_ID={node_id}");
    } else {
        println!("NODE_BADGE_ID=");
        println!("NODE_ID=");
    }
    if let Some(toma_wallet) = toma_wallet {
        println!("TOMA_WALLET_ID={toma_wallet}");
    } else {
        println!("TOMA_WALLET_ID=");
    }

    Ok(())
}
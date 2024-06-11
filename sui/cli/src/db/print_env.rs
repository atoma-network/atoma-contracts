use crate::prelude::*;

pub(crate) async fn command(context: &mut Context) -> Result<()> {
    let atoma_package = context.unwrap_atoma_package_id();
    let toma_package = context.unwrap_toma_package_id();
    let atoma_db = context.get_or_load_atoma_db().await?;
    let manager_badge = context.get_or_load_db_manager_badge().await?;
    let node_info = context.get_or_load_node_badge().await.ok();
    let toma_wallet = context.get_or_load_toma_wallet().await.ok();

    println!("WALLET_PATH={}", context.unwrap_wallet_path().display());
    println!("ATOMA_PACKAGE_ID={atoma_package}");
    println!("TOMA_PACKAGE_ID={toma_package}");
    println!("ATOMA_DB_ID={atoma_db}");
    println!("MANAGER_BADGE_ID={manager_badge}");
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
    if let Some(active_env) = context.wallet.config.active_env.as_ref() {
        println!("CHAIN_ENV={}", active_env);
    } else {
        println!("CHAIN_ENV=");
    }

    // TODO: FAUCET_ID=

    Ok(())
}

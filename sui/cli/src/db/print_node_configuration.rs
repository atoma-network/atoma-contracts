use std::path::Path;

use crate::{
    find_toma_token_wallets, get_atoma_db, get_db_manager_badge,
    get_node_badge, get_prompts, prelude::*,
};

pub(crate) async fn command(
    wallet: &mut WalletContext,
    wallet_path: &Path,
    package: &str,
) -> Result<(), anyhow::Error> {
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = FromStr::from_str(package)?;
    let atoma_db = get_atoma_db(&client, package).await?;
    let manager_badge =
        get_db_manager_badge(&client, package, active_address).await?;
    let (node_badge, node_id) =
        get_node_badge(&client, package, active_address).await?;
    let toma_wallet = find_toma_token_wallets(&client, package, active_address)
        .await?
        .next();
    let prompt_standards = get_prompts(&client, package).await?;

    println!("WALLET_PATH={}", wallet_path.display());
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

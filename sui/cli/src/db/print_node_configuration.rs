use crate::{
    find_toma_token_wallets, get_db_manager_badge, get_node_badge, get_prompts,
    prelude::*,
};

pub(crate) async fn command(
    conf: &DotenvConf,
    wallet: &mut WalletContext,
) -> Result<(), anyhow::Error> {
    let client = wallet.get_client().await?;
    let active_address = wallet.active_address()?;
    let package = conf.unwrap_package_id();
    let atoma_db = conf.get_or_load_atoma_db(&client).await?;
    let manager_badge =
        get_db_manager_badge(&client, package, active_address).await?;
    let (node_badge, node_id) =
        get_node_badge(&client, package, active_address).await?;
    let toma_wallet = find_toma_token_wallets(&client, package, active_address)
        .await?
        .next();
    let prompt_standards = get_prompts(&client, package).await?;

    println!("WALLET_PATH={}", conf.unwrap_wallet_path().display());
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

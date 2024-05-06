use std::path::{Path, PathBuf};

use sui_sdk::{
    rpc_types::{SuiObjectDataOptions, SuiParsedData},
    types::base_types::{ObjectID, ObjectType},
    SuiClient,
};

use crate::{
    find_toma_token_wallets, get_atoma_db, get_db_manager_badge,
    get_node_badge, get_prompts, prelude::*, SETTLEMENT_MODULE_NAME,
    SETTLEMENT_TICKET_TYPE_NAME,
};

pub(crate) const WALLET_PATH: &str = "WALLET_PATH";
pub(crate) const PACKAGE_ID: &str = "PACKAGE_ID";
pub(crate) const ATOMA_DB_ID: &str = "ATOMA_DB_ID";
pub(crate) const MANAGER_BADGE_ID: &str = "MANAGER_BADGE_ID";
pub(crate) const NODE_BADGE_ID: &str = "NODE_BADGE_ID";
pub(crate) const NODE_ID: &str = "NODE_ID";
pub(crate) const PROMPT_STANDARDS_ID: &str = "PROMPT_STANDARDS_ID";
pub(crate) const TOMA_WALLET_ID: &str = "TOMA_WALLET_ID";

pub(crate) struct Context {
    pub(crate) conf: DotenvConf,
    pub(crate) wallet: WalletContext,
}

pub(crate) struct DotenvConf {
    pub(crate) wallet_path: Option<PathBuf>,
    pub(crate) package_id: Option<ObjectID>,
    pub(crate) atoma_db_id: Option<ObjectID>,
    pub(crate) manager_badge_id: Option<ObjectID>,
    pub(crate) node_badge_id: Option<ObjectID>,
    pub(crate) node_id: Option<u64>,
    pub(crate) prompt_standards_id: Option<ObjectID>,
    pub(crate) toma_wallet_id: Option<ObjectID>,
    pub(crate) gas_budget: Option<u64>,
}

impl DotenvConf {
    pub(crate) fn from_env() -> Self {
        todo!()
    }
}

impl Context {
    pub(crate) async fn get_client(&self) -> Result<SuiClient, anyhow::Error> {
        Ok(self.wallet.get_client().await?)
    }

    pub(crate) fn with_optional_package_id(
        mut self,
        package_id: Option<String>,
    ) -> Self {
        if let Some(s) = package_id {
            let new_package_id = ObjectID::from_str(&s).unwrap();
            if Some(new_package_id) != self.conf.package_id {
                debug!("Using package {new_package_id}, ignoring .env");
                self.conf.package_id = Some(new_package_id);
                // since the package id has changed, we need to reset all the
                // other ids
                self.conf.atoma_db_id = None;
                self.conf.manager_badge_id = None;
                self.conf.node_badge_id = None;
                self.conf.node_id = None;
                self.conf.prompt_standards_id = None;
                self.conf.toma_wallet_id = None;
            }
        }

        self
    }

    pub(crate) fn unwrap_package_id(&self) -> ObjectID {
        self.conf
            .package_id
            .clone()
            .unwrap_or_else(|| panic!("{} is not set", PACKAGE_ID))
    }

    /// Some CLI calls don't require a package ID to be provided, because it can
    /// be found from the context. For example, ticket ID is enough to find
    /// the package ID.
    ///
    /// However, we want to make sure that the package ID is consistent with the
    /// one that is configured in the .env file if any is provided.
    pub(crate) fn assert_or_store_package_id(&mut self, package_id: ObjectID) {
        if let Some(existing_package_id) = self.conf.package_id {
            assert_eq!(
                existing_package_id, package_id,
                "Package {package_id} mismatches \
                configured package {existing_package_id}"
            );
        } else {
            self.conf.package_id = Some(package_id);
        }
    }

    pub(crate) fn gas_budget(&self) -> u64 {
        self.conf.gas_budget.unwrap_or(2_000_000_000)
    }

    pub(crate) fn unwrap_wallet_path(&self) -> &Path {
        self.conf
            .wallet_path
            .as_ref()
            .unwrap_or_else(|| panic!("{} is not set", WALLET_PATH))
    }

    pub(crate) async fn get_or_load_atoma_db(
        &mut self,
    ) -> Result<ObjectID, anyhow::Error> {
        if let Some(atoma_db_id) = self.conf.atoma_db_id {
            Ok(atoma_db_id)
        } else {
            let package_id = self.unwrap_package_id();
            let atoma_db =
                get_atoma_db(&self.get_client().await?, package_id).await?;
            self.conf.atoma_db_id = Some(atoma_db);
            Ok(atoma_db)
        }
    }

    pub(crate) async fn get_or_load_db_manager_badge(
        &mut self,
    ) -> Result<ObjectID, anyhow::Error> {
        if let Some(manager_badge_id) = self.conf.manager_badge_id {
            Ok(manager_badge_id)
        } else {
            let package_id = self.unwrap_package_id();
            let badge_id = get_db_manager_badge(
                &self.get_client().await?,
                package_id,
                self.wallet.active_address()?,
            )
            .await?;
            self.conf.manager_badge_id = Some(badge_id);
            Ok(badge_id)
        }
    }

    pub(crate) async fn get_or_load_prompts(
        &mut self,
    ) -> Result<ObjectID, anyhow::Error> {
        if let Some(prompt_standards_id) = self.conf.prompt_standards_id {
            Ok(prompt_standards_id)
        } else {
            let package_id = self.unwrap_package_id();
            let prompt_standards =
                get_prompts(&self.get_client().await?, package_id).await?;
            self.conf.prompt_standards_id = Some(prompt_standards);
            Ok(prompt_standards)
        }
    }

    pub(crate) async fn get_or_load_node_badge(
        &mut self,
    ) -> Result<(ObjectID, u64), anyhow::Error> {
        if let (Some(node_badge_id), Some(node_id)) =
            (self.conf.node_badge_id, self.conf.node_id)
        {
            Ok((node_badge_id, node_id))
        } else {
            let package_id = self.unwrap_package_id();
            let (node_badge_id, node_id) = get_node_badge(
                &self.get_client().await?,
                package_id,
                self.wallet.active_address()?,
            )
            .await?;
            self.conf.node_badge_id = Some(node_badge_id);
            self.conf.node_id = Some(node_id);
            Ok((node_badge_id, node_id))
        }
    }

    pub(crate) async fn get_or_load_toma_wallet(
        &mut self,
    ) -> Result<ObjectID, anyhow::Error> {
        if let Some(toma_wallet_id) = self.conf.toma_wallet_id {
            Ok(toma_wallet_id)
        } else {
            let package_id = self.unwrap_package_id();
            let active_address = self.wallet.active_address()?;
            let toma_wallet = find_toma_token_wallets(
                &self.get_client().await?,
                package_id,
                active_address,
            )
            .await?
            .next();
            if let Some(toma_wallet) = toma_wallet {
                self.conf.toma_wallet_id = Some(toma_wallet);
                Ok(toma_wallet)
            } else {
                anyhow::bail!("No TOMA wallet found")
            }
        }
    }

    pub(crate) async fn ticket_package_and_fields(
        &mut self,
        ticket_id: ObjectID,
    ) -> Result<(ObjectID, serde_json::Value), anyhow::Error> {
        let ticket = self
            .wallet
            .get_client()
            .await?
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
        self.assert_or_store_package_id(package);

        let SuiParsedData::MoveObject(ticket) = ticket.content.unwrap() else {
            return Err(anyhow!("Ticket content must be MoveObject"));
        };

        Ok((package, ticket.fields.to_json_value()))
    }
}

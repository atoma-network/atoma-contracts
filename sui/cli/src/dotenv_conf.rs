use std::path::{Path, PathBuf};

use sui_sdk::{types::base_types::ObjectID, SuiClient};

use crate::{get_atoma_db, prelude::*};

pub(crate) const WALLET_PATH: &str = "WALLET_PATH";
pub(crate) const PACKAGE_ID: &str = "PACKAGE_ID";
pub(crate) const ATOMA_DB_ID: &str = "ATOMA_DB_ID";
pub(crate) const MANAGER_BADGE_ID: &str = "MANAGER_BADGE_ID";
pub(crate) const NODE_BADGE_ID: &str = "NODE_BADGE_ID";
pub(crate) const NODE_ID: &str = "NODE_ID";
pub(crate) const PROMPT_STANDARDS_ID: &str = "PROMPT_STANDARDS_ID";
pub(crate) const TOMA_WALLET_ID: &str = "TOMA_WALLET_ID";

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

    pub(crate) fn with_optional_package_id(
        mut self,
        package_id: Option<String>,
    ) -> Self {
        self.package_id = package_id.map(|s| ObjectID::from_str(&s).unwrap());
        self
    }

    pub(crate) fn unwrap_package_id(&self) -> ObjectID {
        self.package_id
            .clone()
            .unwrap_or_else(|| panic!("{} is not set", PACKAGE_ID))
    }

    pub(crate) fn package_id(&self) -> Option<ObjectID> {
        self.package_id.clone()
    }

    pub(crate) fn gas_budget(&self) -> u64 {
        self.gas_budget.unwrap_or(2_000_000_000)
    }

    pub(crate) fn unwrap_wallet_path(&self) -> &Path {
        self.wallet_path
            .as_ref()
            .unwrap_or_else(|| panic!("{} is not set", WALLET_PATH))
    }

    pub(crate) async fn get_or_load_atoma_db(
        &self,
        sui: &SuiClient,
    ) -> Result<ObjectID, anyhow::Error> {
        if let Some(atoma_db_id) = self.atoma_db_id {
            Ok(atoma_db_id)
        } else {
            let package_id = self.unwrap_package_id();
            let atoma_db = get_atoma_db(sui, package_id).await?;
            Ok(atoma_db)
        }
    }
}

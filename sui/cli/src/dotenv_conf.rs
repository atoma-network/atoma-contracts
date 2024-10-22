use core::panic;
use std::path::{Path, PathBuf};

use sui_sdk::{
    rpc_types::{
        Page, SuiData, SuiObjectDataFilter, SuiObjectDataOptions,
        SuiObjectResponseQuery, SuiParsedData, SuiTransactionBlockEffects,
        SuiTransactionBlockResponseOptions, SuiTransactionBlockResponseQuery,
        TransactionFilter,
    },
    types::base_types::{ObjectID, ObjectType, SuiAddress},
    SuiClient,
};

use crate::{
    prelude::*, DB_MANAGER_TYPE_NAME, DB_MODULE_NAME, DB_NODE_TYPE_NAME,
    DB_TASK_TYPE_NAME, DB_TYPE_NAME, FAUCET_TYPE_NAME, SETTLEMENT_MODULE_NAME,
    SETTLEMENT_TICKET_TYPE_NAME, TOMA_COIN_MODULE_NAME,
};

pub(crate) const ATOMA_DB_ID: &str = "ATOMA_DB_ID";
pub(crate) const ATOMA_PACKAGE_ID: &str = "ATOMA_PACKAGE_ID";
pub(crate) const FAUCET_ID: &str = "FAUCET_ID";
pub(crate) const GAS_BUDGET: &str = "GAS_BUDGET";
pub(crate) const MANAGER_BADGE_ID: &str = "MANAGER_BADGE_ID";
pub(crate) const NODE_BADGE_ID: &str = "NODE_BADGE_ID";
pub(crate) const NODE_ID: &str = "NODE_ID";
pub(crate) const TASK_BADGE_ID: &str = "TASK_BADGE_ID";
pub(crate) const TASK_SMALL_ID: &str = "TASK_SMALL_ID";
pub(crate) const TOMA_PACKAGE_ID: &str = "TOMA_PACKAGE_ID";
pub(crate) const TOMA_WALLET_ID: &str = "TOMA_WALLET_ID";
pub(crate) const WALLET_PATH: &str = "WALLET_PATH";

pub(crate) struct Context {
    pub(crate) conf: DotenvConf,
    pub(crate) wallet: WalletContext,
}

#[derive(Debug, Default)]
pub(crate) struct DotenvConf {
    pub(crate) wallet_path: Option<PathBuf>,
    pub(crate) atoma_package_id: Option<ObjectID>,
    pub(crate) toma_package_id: Option<ObjectID>,
    pub(crate) atoma_db_id: Option<ObjectID>,
    pub(crate) manager_badge_id: Option<ObjectID>,
    pub(crate) node_badge_id: Option<ObjectID>,
    pub(crate) task_badge_id: Option<ObjectID>,
    pub(crate) task_id: Option<u64>,
    pub(crate) node_id: Option<u64>,
    pub(crate) faucet_id: Option<ObjectID>,
    pub(crate) toma_wallet_id: Option<ObjectID>,
    pub(crate) gas_budget: Option<u64>,
}

impl DotenvConf {
    pub(crate) fn from_env() -> Self {
        Self {
            wallet_path: std::env::var(WALLET_PATH).ok().map(PathBuf::from),
            atoma_package_id: std::env::var(ATOMA_PACKAGE_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| ObjectID::from_str(&s).unwrap()),
            toma_package_id: std::env::var(TOMA_PACKAGE_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| ObjectID::from_str(&s).unwrap()),
            atoma_db_id: std::env::var(ATOMA_DB_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| ObjectID::from_str(&s).unwrap()),
            manager_badge_id: std::env::var(MANAGER_BADGE_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| ObjectID::from_str(&s).unwrap()),
            node_badge_id: std::env::var(NODE_BADGE_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| ObjectID::from_str(&s).unwrap()),
            task_badge_id: std::env::var(TASK_BADGE_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| ObjectID::from_str(&s).unwrap()),
            task_id: std::env::var(TASK_SMALL_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| s.parse().unwrap()),
            faucet_id: std::env::var(FAUCET_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| ObjectID::from_str(&s).unwrap()),
            node_id: std::env::var(NODE_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| s.parse().unwrap()),
            toma_wallet_id: std::env::var(TOMA_WALLET_ID)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| ObjectID::from_str(&s).unwrap()),
            gas_budget: std::env::var(GAS_BUDGET)
                .ok()
                .filter(|s| !s.is_empty())
                .map(|s| s.parse().unwrap()),
        }
    }
}

impl Context {
    pub(crate) async fn get_client(&self) -> Result<SuiClient> {
        self.wallet.get_client().await
    }

    pub(crate) fn with_optional_atoma_package_id(
        mut self,
        package_id: Option<String>,
    ) -> Self {
        if let Some(s) = package_id {
            let new_package_id = ObjectID::from_str(&s).unwrap();
            if Some(new_package_id) != self.conf.atoma_package_id {
                debug!("Using Atoma package {new_package_id}, ignoring .env");
                // since the package id has changed, we need to reset all the
                // other ids
                self.reset_ids();
                self.conf.atoma_package_id = Some(new_package_id);
            }
        }

        self
    }

    pub(crate) fn with_optional_toma_package_id(
        mut self,
        package_id: Option<String>,
    ) -> Self {
        if let Some(s) = package_id {
            let new_package_id = ObjectID::from_str(&s).unwrap();
            if Some(new_package_id) != self.conf.toma_package_id {
                debug!("Using Toma package {new_package_id}, ignoring .env");
                // since the package id has changed, we need to reset all the
                // other ids
                self.reset_ids();
                self.conf.toma_package_id = Some(new_package_id);
            }
        }

        self
    }

    /// Removes all the IDs that have been loaded so far from the config.
    fn reset_ids(&mut self) {
        self.conf.atoma_db_id = None;
        self.conf.faucet_id = None;
        self.conf.manager_badge_id = None;
        self.conf.node_badge_id = None;
        self.conf.node_id = None;
        self.conf.toma_wallet_id = None;
    }

    /// Package of the Atoma network.
    pub(crate) fn unwrap_atoma_package_id(&self) -> ObjectID {
        self.conf
            .atoma_package_id
            .unwrap_or_else(|| panic!("{} is not set", ATOMA_PACKAGE_ID))
    }

    /// Package of the TOMA token.
    pub(crate) async fn get_or_load_toma_package_id(
        &mut self,
    ) -> Result<ObjectID> {
        if let Some(toma_package) = self.conf.toma_package_id {
            Ok(toma_package)
        } else {
            let package_id = self.unwrap_atoma_package_id();
            let toma_package =
                get_toma_package(&self.get_client().await?, package_id).await?;
            self.conf.toma_package_id = Some(toma_package);
            Ok(toma_package)
        }
    }

    /// Some CLI calls don't require a package ID to be provided, because it can
    /// be found from the context. For example, ticket ID is enough to find
    /// the package ID.
    ///
    /// However, we want to make sure that the package ID is consistent with the
    /// one that is configured in the .env file if any is provided.
    pub(crate) fn assert_or_store_atoma_package_id(
        &mut self,
        package_id: ObjectID,
    ) {
        if let Some(existing_package_id) = self.conf.atoma_package_id {
            assert_eq!(
                existing_package_id, package_id,
                "Package {package_id} mismatches \
                configured package {existing_package_id}"
            );
        } else {
            self.conf.atoma_package_id = Some(package_id);
        }
    }

    pub(crate) fn gas_budget(&self) -> u64 {
        self.conf.gas_budget.unwrap_or(10_000_000)
    }

    pub(crate) fn unwrap_wallet_path(&self) -> &Path {
        self.conf
            .wallet_path
            .as_ref()
            .unwrap_or_else(|| panic!("{WALLET_PATH} is not set"))
    }

    pub(crate) async fn get_or_load_atoma_db(&mut self) -> Result<ObjectID> {
        if let Some(atoma_db_id) = self.conf.atoma_db_id {
            Ok(atoma_db_id)
        } else {
            let package_id = self.unwrap_atoma_package_id();
            let atoma_db =
                get_atoma_db(&self.get_client().await?, package_id).await?;
            self.conf.atoma_db_id = Some(atoma_db);
            Ok(atoma_db)
        }
    }

    pub(crate) async fn get_or_load_faucet_id(&mut self) -> Result<ObjectID> {
        if let Some(faucet_id) = self.conf.faucet_id {
            Ok(faucet_id)
        } else {
            let package_id = self.get_or_load_toma_package_id().await?;
            let faucet_id =
                get_faucet_id(&self.get_client().await?, package_id).await?;
            self.conf.faucet_id = Some(faucet_id);
            Ok(faucet_id)
        }
    }

    pub(crate) async fn get_or_load_db_manager_badge(
        &mut self,
    ) -> Result<ObjectID> {
        if let Some(manager_badge_id) = self.conf.manager_badge_id {
            Ok(manager_badge_id)
        } else {
            let package_id = self.unwrap_atoma_package_id();
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

    pub(crate) async fn get_or_load_node_badge(
        &mut self,
    ) -> Result<(ObjectID, u64)> {
        if let (Some(node_badge_id), Some(node_id)) =
            (self.conf.node_badge_id, self.conf.node_id)
        {
            Ok((node_badge_id, node_id))
        } else {
            let package_id = self.unwrap_atoma_package_id();
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

    pub(crate) async fn get_or_load_task_badge(
        &mut self,
    ) -> Result<(ObjectID, u64)> {
        if let (Some(task_badge_id), Some(task_id)) =
            (self.conf.task_badge_id, self.conf.task_id)
        {
            Ok((task_badge_id, task_id))
        } else {
            let package_id = self.unwrap_atoma_package_id();
            let (task_badge_id, task_id) = get_task_badge(
                &self.get_client().await?,
                package_id,
                self.wallet.active_address()?,
            )
            .await?;
            self.conf.task_badge_id = Some(task_badge_id);
            Ok((task_badge_id, task_id))
        }
    }

    pub(crate) async fn get_or_load_toma_wallet(&mut self) -> Result<ObjectID> {
        if let Some(toma_wallet_id) = self.conf.toma_wallet_id {
            Ok(toma_wallet_id)
        } else {
            let toma_package_id = self.get_or_load_toma_package_id().await?;
            let active_address = self.wallet.active_address()?;
            let toma_wallet = find_toma_token_wallet(
                &self.get_client().await?,
                toma_package_id,
                active_address,
            )
            .await;
            if let Ok(toma_wallet) = toma_wallet {
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
    ) -> Result<(ObjectID, serde_json::Value)> {
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
        self.assert_or_store_atoma_package_id(package);

        let SuiParsedData::MoveObject(ticket) = ticket.content.unwrap() else {
            return Err(anyhow!("Ticket content must be MoveObject"));
        };

        Ok((package, ticket.fields.to_json_value()))
    }

    pub(crate) async fn load_atoma_db_fields(
        &mut self,
    ) -> Result<serde_json::Value> {
        let atoma_id = self.get_or_load_atoma_db().await?;

        let SuiParsedData::MoveObject(atoma) = self
            .get_client()
            .await?
            .read_api()
            .get_object_with_options(
                atoma_id,
                SuiObjectDataOptions {
                    show_content: true,
                    ..Default::default()
                },
            )
            .await?
            .data
            .ok_or_else(|| anyhow!("Cannot fetch AtomaDb data"))?
            .content
            .ok_or_else(|| anyhow!("AtomaDb has no content"))?
        else {
            return Err(anyhow!("AtomaDb must be a Move object"));
        };

        if atoma.type_.module.as_str() != DB_MODULE_NAME
            || atoma.type_.name.as_str() != DB_TYPE_NAME
        {
            return Err(anyhow!(
                "AtomaDb must be of type {DB_MODULE_NAME}.{DB_TYPE_NAME}",
            ));
        }

        Ok(atoma.fields.to_json_value())
    }
}

/// Returns the ID of the node badge and the small ID of the node.
async fn get_node_badge(
    client: &SuiClient,
    package: ObjectID,
    active_address: SuiAddress,
) -> Result<(ObjectID, u64)> {
    let Page {
        data,
        has_next_page,
        ..
    } = client
        .read_api()
        .get_owned_objects(
            active_address,
            Some(SuiObjectResponseQuery {
                filter: Some(SuiObjectDataFilter::Package(package)),
                options: Some(SuiObjectDataOptions {
                    show_type: true,
                    show_content: true,
                    ..Default::default()
                }),
            }),
            None,
            None,
        )
        .await?;
    assert!(!has_next_page, "We don't support pagination yet");

    data.into_iter()
        .find_map(|resp| {
            let object = resp.data?;

            let ObjectType::Struct(type_) = object.type_? else {
                return None;
            };

            if type_.module().as_str() == DB_MODULE_NAME
                && type_.name().as_str() == DB_NODE_TYPE_NAME
            {
                let id = object
                    .content?
                    .try_as_move()?
                    .clone()
                    .fields
                    .to_json_value();

                Some((
                    object.object_id,
                    id["small_id"]["inner"].as_str()?.parse().ok()?,
                ))
            } else {
                None
            }
        })
        .ok_or_else(|| {
            anyhow::anyhow!("No {DB_NODE_TYPE_NAME} found for the package")
        })
}

async fn get_task_badge(
    client: &SuiClient,
    package: ObjectID,
    active_address: SuiAddress,
) -> Result<(ObjectID, u64)> {
    let Page {
        data,
        has_next_page,
        ..
    } = client
        .read_api()
        .get_owned_objects(
            active_address,
            Some(SuiObjectResponseQuery {
                filter: Some(SuiObjectDataFilter::Package(package)),
                options: Some(SuiObjectDataOptions {
                    show_type: true,
                    show_content: true,
                    ..Default::default()
                }),
            }),
            None,
            None,
        )
        .await?;
    assert!(!has_next_page, "We don't support pagination yet");

    data.into_iter()
        .find_map(|resp| {
            let object = resp.data?;

            let ObjectType::Struct(type_) = object.type_? else {
                return None;
            };

            if type_.module().as_str() == DB_MODULE_NAME
                && type_.name().as_str() == DB_TASK_TYPE_NAME
            {
                let id = object
                    .content?
                    .try_as_move()?
                    .clone()
                    .fields
                    .to_json_value();

                Some((
                    object.object_id,
                    id["small_id"]["inner"].as_str()?.parse().ok()?,
                ))
            } else {
                None
            }
        })
        .ok_or_else(|| {
            anyhow::anyhow!("No {DB_NODE_TYPE_NAME} found for the package")
        })
}

async fn find_toma_token_wallet(
    client: &SuiClient,
    toma_package: ObjectID,
    active_address: SuiAddress,
) -> Result<ObjectID> {
    let Page { data: coins, .. } = client
        .coin_read_api()
        .get_coins(
            active_address,
            Some(format!("{toma_package}::toma::TOMA")),
            None,
            None,
        )
        .await?;
    coins
        .into_iter()
        .max_by_key(|coin| coin.balance)
        .map(|coin| coin.coin_object_id)
        .ok_or_else(|| {
            anyhow::anyhow!(
                "No TOMA coins for {active_address}. \
                Have you just received them? \
                It may take a few seconds for cache to refresh. \
                Double check that your address owns TOMA coins and try again."
            )
        })
}

async fn get_atoma_db(
    client: &SuiClient,
    package: ObjectID,
) -> Result<ObjectID> {
    get_publish_tx_created_object(client, package, DB_MODULE_NAME, DB_TYPE_NAME)
        .await
}

async fn get_faucet_id(
    client: &SuiClient,
    toma_package: ObjectID,
) -> Result<ObjectID> {
    // get_publish_tx_created_object(
    //     client,
    //     toma_package,
    //     TOMA_COIN_MODULE_NAME,
    //     FAUCET_TYPE_NAME,
    // )
    // .await
    Ok(ObjectID::from_str("0xeef012ef16681b151db14110266c218e7485eaef806aa4e6655690d6723f12f5").unwrap())
}

async fn get_publish_tx_created_object(
    client: &SuiClient,
    package: ObjectID,
    module: &str,
    name: &str,
) -> Result<ObjectID> {
    let Page {
        data,
        has_next_page,
        ..
    } = client
        .read_api()
        .query_transaction_blocks(
            SuiTransactionBlockResponseQuery {
                filter: Some(TransactionFilter::ChangedObject(package)),
                options: Some(SuiTransactionBlockResponseOptions {
                    show_effects: true,
                    ..Default::default()
                }),
            },
            None,
            Some(1),
            false,
        )
        .await?;
    assert_eq!(1, data.len(), "Did you select right package ID?");
    assert!(!has_next_page);

    let SuiTransactionBlockEffects::V1(changes) =
        data.into_iter().next().unwrap().effects.unwrap();

    let object_ids = changes.created.into_iter().map(|r| r.reference.object_id);
    for object_id in object_ids {
        let type_ = client
            .read_api()
            .get_object_with_options(
                object_id,
                SuiObjectDataOptions {
                    show_type: true,
                    ..Default::default()
                },
            )
            .await
            .ok()
            .and_then(|r| r.data)
            .and_then(|data| data.type_);
        if let Some(ObjectType::Struct(type_)) = type_ {
            if type_.module().as_str() == module
                && type_.name().as_str() == name
            {
                return Ok(object_id);
            }
        }
    }

    Err(anyhow::anyhow!("No {module}::{name} found for the package"))
}

async fn get_db_manager_badge(
    client: &SuiClient,
    package: ObjectID,
    active_address: SuiAddress,
) -> Result<ObjectID> {
    let Page {
        data,
        has_next_page,
        ..
    } = client
        .read_api()
        .get_owned_objects(
            active_address,
            Some(SuiObjectResponseQuery {
                filter: Some(SuiObjectDataFilter::Package(package)),
                options: Some(SuiObjectDataOptions {
                    show_type: true,
                    ..Default::default()
                }),
            }),
            None,
            None,
        )
        .await?;
    assert!(!has_next_page, "We don't support pagination yet");

    data.into_iter()
        .find_map(|resp| {
            let object = resp.data?;

            let ObjectType::Struct(type_) = object.type_? else {
                return None;
            };

            if type_.module().as_str() == DB_MODULE_NAME
                && type_.name().as_str() == DB_MANAGER_TYPE_NAME
            {
                Some(object.object_id)
            } else {
                None
            }
        })
        .ok_or_else(|| {
            anyhow::anyhow!("No {DB_MANAGER_TYPE_NAME} found for the package")
        })
}

async fn get_toma_package(
    client: &SuiClient,
    atoma_package: ObjectID,
) -> Result<ObjectID> {
    let xd = client
        .read_api()
        .get_object_with_options(
            atoma_package,
            SuiObjectDataOptions {
                show_type: true,
                show_content: true,
                ..Default::default()
            },
        )
        .await?
        .data
        .expect("Package not found");

    let Some(ObjectType::Package) = xd.type_ else {
        panic!("Object {atoma_package} is not a package");
    };

    let Some(SuiParsedData::Package(content)) = xd.content else {
        panic!("Package {atoma_package} has no content");
    };

    let hay = content
        .disassembled
        .get(DB_MODULE_NAME)
        .unwrap()
        .as_str()
        .unwrap();

    // it's there without the 0x prefix
    let re = regex::Regex::new(r"use ([a-f0-9]{64})::toma;").unwrap();

    if let Some(needle) = re.captures(hay) {
        Ok(ObjectID::from_str(&needle[1])
            .expect("Invalid Toma package ID found in Atoma package"))
    } else {
        Err(anyhow::anyhow!("No Toma package ID found in Atoma package"))
    }
}

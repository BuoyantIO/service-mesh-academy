use futures_util::StreamExt;
use std::{sync::Arc, time::Duration};
use thiserror::Error;
use tracing::Instrument;

use kube::{
    api::{Patch, PatchParams},
    runtime::{controller::Action, Config, Controller},
    Api, Client, ResourceExt,
};

use super::{ExternalWorkload, ExternalWorkloadStatus};

#[derive(Clone)]
pub struct SharedData {
    pub client: Client,
}

#[derive(Debug, Error)]
pub enum ControllerError {
    #[error("Failed to patch external workload: {0}")]
    WriteFailed(#[source] kube::Error),

    #[error("Missing workload field: {0}")]
    MissingField(&'static str),
}

pub async fn run_controller(api: Api<ExternalWorkload>, cfg: Config, shared_data: Arc<SharedData>) {
    Controller::new(api, Default::default())
        .shutdown_on_signal()
        .with_config(cfg)
        .run(
            reconcile,
            |_, error, _| {
                tracing::error!(%error, "Failed to reconcile ExternalWorkload");
                Action::requeue(Duration::from_secs(60))
            },
            shared_data,
        )
        .for_each(|result| async move {
            match result {
                Ok(v) => tracing::info!("Reconciled {v:?}"),
                Err(error) => tracing::error!(%error, "Failed to reconcile object"),
            }
        })
        .instrument(tracing::info_span!("status_controller"))
        .await;
}

/// Controller will trigger this whenever our main pod has changed. The
/// function reconciles a pod by writing a status if it does not document a
/// port.
async fn reconcile(
    workload: Arc<ExternalWorkload>,
    ctx: Arc<SharedData>,
) -> Result<Action, ControllerError> {
    // Get workload's status conditions. If no status is present, use an
    // empty vec.
    let mut conditions = workload.status.clone().unwrap_or_default().conditions;

    // If the condition already exists, exit
    for cond in conditions.iter() {
        if cond.typ == super::WORKLOAD_READY_COND {
            // Do nothing until this resource changes
            return Ok(Action::await_change());
        }
    }

    // Create a new condition
    conditions.push(super::mk_condition());

    // Create the updated status
    let status = ExternalWorkloadStatus { conditions };
    // Create an api type to do writes
    let namespace = workload
        .metadata
        .namespace
        .as_ref()
        .ok_or_else(|| ControllerError::MissingField(".metadata.namespace"))?;
    let api = Api::<ExternalWorkload>::namespaced(ctx.client.clone(), &namespace);

    let name = workload.name_any();
    let value = serde_json::json!({
            "apiVersion": "workload.linkerd.io/v1beta1",
            "kind": "ExternalWorkload",
            "name": &name,
            "status": status,
    });

    let p = Patch::Merge(value);
    // Patch using a merge strategy
    api.patch_status(&name, &PatchParams::apply("kubecon-controller"), &p)
        .await
        .map_err(|error| ControllerError::WriteFailed(error))?;

    // We could also requeue with a deadline to ensure events are never
    // missed
    Ok(Action::await_change())
}

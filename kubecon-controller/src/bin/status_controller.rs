/* KUBECON STATUS CONTROLLER EXAMPLE
 *
 *  Creates a simple status controller using the runtime from kube-rs.
 *  The controller will reconcile ExternalWorkload objects by writing to their
 *  status when empty.
 *
 */

use k8s_openapi::apiextensions_apiserver::pkg::apis::apiextensions::v1::CustomResourceDefinition;
use kube::{
    api::{Patch, PatchParams, PostParams},
    Api, Client, CustomResourceExt, ResourceExt,
};
use kubecon_controller::{mk_external_workload, run_controller, ExternalWorkload, SharedData};
use std::num::NonZeroU16;

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "info");
    }

    tracing_subscriber::fmt::init();
    tracing::info!("Hello, Kubecon! We're going to do writes now!");

    // Register CRD
    let client = Client::try_default().await?;
    register_crd(client.clone()).await?;

    // Create some configuration params for the controller
    let config = kube::runtime::controller::Config::default().concurrency(2);
    let api = kube::api::Api::<ExternalWorkload>::all(client.clone());

    // Some shared state we might need to reconcile objects
    let state = std::sync::Arc::new(SharedData { client });

    // Run the controller until it receives a shutdown signal
    run_controller(api, config, state).await;

    Ok(())
}

async fn register_crd(client: Client) -> anyhow::Result<()> {
    // Don't attempt to create a CRD unless configured to do so
    if std::env::var("CREATE_CRD").is_err() {
        tracing::info!("Skipping CRD creation");
        return Ok(());
    }

    let crds: Api<CustomResourceDefinition> = Api::all(client.clone());
    crds.patch(
        "externalworkloads.workload.linkerd.io",
        &PatchParams::apply("crdreg"),
        &Patch::Apply(ExternalWorkload::crd()),
    )
    .await?;

    // Create an ExternalWorkload instance using a helper function that takes
    // only a name, namespace and port list.
    let example = {
        let port = NonZeroU16::new(80).expect("should not fail to cast '80' to non-zero u16");
        mk_external_workload("test-123", "default", vec![port])
    };

    // Create workloads
    let workloads: Api<ExternalWorkload> = Api::namespaced(client, &example.namespace().unwrap());
    workloads.create(&PostParams::default(), &example).await?;
    let example = workloads.get(&example.name_any()).await?;
    tracing::info!(name = %example.name_any(), "Created workload");

    Ok(())
}

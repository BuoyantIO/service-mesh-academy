use k8s_openapi::api::core::v1::Pod;

use kube::{api::ListParams, Api, Client, ResourceExt};

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    // Quick hack to get rust log to default to info
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "info");
    }

    // Set-up global tracing subscriber.
    // Can set log level through "RUST_LOG"
    tracing_subscriber::fmt::init();
    tracing::info!("Hello, Kubecon!");

    // Create a Kubernetes client.
    // HTTP client decorated with Kubernetes-specific information
    let client = Client::try_default().await?;

    // Create an 'Api' type that allows us to manage pods in 'default' namespace.
    let pods = Api::<Pod>::default_namespaced(client.clone());
    for pod in pods.list(&ListParams::default()).await? {
        let name = pod.name_any();
        tracing::info!(%name, "Got pod in default namespace");
    }

    // Create an 'Api' type that allows us to list across namespaces.
    let all_pods = Api::<Pod>::all(client);
    for pod in all_pods.list(&ListParams::default()).await? {
        let name = pod.name_any();
        let ns = pod.namespace().unwrap_or_default();
        tracing::info!(%name, %ns, "Got pod");
    }
    Ok(())
}

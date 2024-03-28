/* KUBECON STATEFUL CONTROLLER EXAMPLE
 *
 *  Creates a stateful controller that holds ExternalWorkload data.
 *
 *  Built using kubert
 */

use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::bail;
use clap::Parser;
use kube::ResourceExt;
use kubecon_controller::ExternalWorkload;
use parking_lot::RwLock;

#[derive(Debug, Parser)]
#[clap(name = "stateful-controller", about = "A quick look at using kubert")]
struct Args {
    #[clap(long, default_value = "info", env = "LOG_LEVEL")]
    log_level: kubert::LogFilter,

    #[clap(long, default_value = "plain")]
    log_format: kubert::LogFormat,

    #[clap(flatten)]
    client: kubert::ClientArgs,
}

pub type SharedIndex = Arc<RwLock<Index>>;

/// Holds all indexing state. Owned and updated by a single task that processes
/// watch events, publishing results to the shared lookup map for quick lookups
/// in the API server.
#[derive(Debug)]
pub struct Index {
    // Holds ExternalWorkloads by name and returns whether their status is ready
    by_name: HashMap<String, bool>,
}

pub struct Reader {
    index: SharedIndex,
}

impl Reader {
    fn new(index: SharedIndex) -> Reader {
        Self { index }
    }

    pub fn is_ready(&self, name: &str) -> Option<bool> {
        let index = self.index.read();
        index.by_name.get(name).cloned()
    }

    pub fn list(&self) -> Vec<String> {
        let index = self.index.read();
        index.by_name.keys().cloned().collect()
    }

    pub async fn list_periodically(self, duration: Duration) {
        tracing::info!("Listing statuses...");
        loop {
            let sleep = tokio::time::sleep(duration);
            for workload in self.list() {
                let is_rdy = self.is_ready(&workload).unwrap_or_default();
                tracing::info!(is_ready = %is_rdy, name = %workload, "Checking for readiness");
            }
            sleep.await;
        }
    }
}

impl Index {
    pub fn shared() -> SharedIndex {
        Arc::new(RwLock::new(Self {
            by_name: HashMap::new(),
        }))
    }

    pub fn read_handle(index: &SharedIndex) -> Reader {
        Reader::new(index.clone())
    }
}

impl kubert::index::IndexNamespacedResource<ExternalWorkload> for Index {
    fn apply(&mut self, resource: ExternalWorkload) {
        tracing::info!(name = %resource.name_any(), "Indexing resource");
        // Check if we have a 'Ready' condition. We don't care about the value
        // since it's always `True`
        let is_ready = resource
            .status
            .clone()
            .unwrap_or_default()
            .conditions
            .into_iter()
            .find(kubecon_controller::is_ready)
            .is_some();
        if is_ready {
            tracing::info!(name = %resource.name_any(), "Found ready workload");
            self.by_name.insert(resource.name_any(), true);
        } else {
            tracing::info!(name = %resource.name_any(), "Found unready workload");
            self.by_name.remove(&resource.name_any());
        }
    }

    fn delete(&mut self, _: String, name: String) {
        self.by_name.remove(&name);
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    let Args {
        client,
        log_level,
        log_format,
    } = Args::parse();

    let mut runtime = kubert::Runtime::builder()
        .with_log(log_level, log_format)
        .with_client(client)
        .build()
        .await?;

    tracing::info!("Hello, Kubecon! Take 2!");

    // Create an index that can be shared across multiple tasks.
    // The index is more generic; it holds any "domain specific" resource we
    // want it to hold
    let index = Index::shared();

    // Create a handle that we can use to get updates.
    let reader = Index::read_handle(&index);

    // Schedule a watcher with the runtime
    let workloads =
        runtime.watch_all::<ExternalWorkload>(kube::runtime::watcher::Config::default());
    tokio::spawn(kubert::index::namespaced(index, workloads));

    // Simulate some business logic; a periodic list.
    tokio::spawn(reader.list_periodically(Duration::from_secs(3)));

    // Block the main thread on the shutdown signal. Once it fires, wait for the background tasks to
    // complete before exiting.
    if runtime.run().await.is_err() {
        bail!("Aborted");
    }

    Ok(())
}

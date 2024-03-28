use std::num::NonZeroU16;

use k8s_openapi::{
    apimachinery::pkg::apis::meta::v1::{self as metav1, Time},
    chrono::{DateTime, Utc},
};
use kube::CustomResource;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

pub const WORKLOAD_READY_COND: &str = "Ready";

/// ExternalWorkload describes a single workload (i.e. a deployable unit,
/// conceptually similar to a Kubernetes Pod) that is running outside of a
/// Kubernetes cluster. An ExternalWorkload should be enrolled in the mesh and
/// typically represents a virtual machine.
#[derive(Clone, Debug, PartialEq, Eq, CustomResource, Deserialize, Serialize, JsonSchema)]
#[kube(
    group = "workload.linkerd.io",
    version = "v1beta1",
    kind = "ExternalWorkload",
    status = "ExternalWorkloadStatus",
    namespaced
)]
pub struct ExternalWorkloadSpec {
    /// MeshTls describes TLS settings associated with an external workload
    #[serde(rename = "meshTLS")]
    pub mesh_tls: MeshTls,
    /// Ports describes a set of ports exposed by the workload
    pub ports: Option<Vec<PortSpec>>,
    /// List of IP addresses that can be used to send traffic to an external
    /// workload
    #[serde(rename = "workloadIPs")]
    pub workload_ips: Option<Vec<WorkloadIP>>,
}

/// MeshTls describes TLS settings associated with an external workload
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize, JsonSchema)]
pub struct MeshTls {
    /// Identity associated with the workload. Used by peers to perform
    /// verification in the mTLS handshake
    pub identity: String,
    /// ServerName is the DNS formatted name associated with the workload. Used
    /// to terminate TLS using the SNI extension.
    #[serde(rename = "serverName")]
    pub server_name: String,
}

/// PortSpec represents a network port in a single workload.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize, JsonSchema)]
pub struct PortSpec {
    /// If specified, must be an IANA_SVC_NAME and unique within the exposed
    /// ports set. Each named port must have a unique name. The name may be
    /// referred to by services
    pub name: Option<String>,
    /// Number of port exposed on the workload's IP address.
    /// Must be a valid port number, i.e. 0 < x < 65536.
    pub port: std::num::NonZeroU16,
    /// Protocol defines network protocols supported. One of UDP, TCP, or SCTP.
    /// Should coincide with Service selecting the workload.
    /// Defaults to "TCP" if unspecified.
    pub protocol: Option<String>,
}

/// WorkloadIPs contains a list of IP addresses exposed by an ExternalWorkload
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize, JsonSchema)]
pub struct WorkloadIP {
    pub ip: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize, JsonSchema)]
pub struct ExternalWorkloadStatus {
    pub conditions: Vec<Condition>,
}

impl Default for ExternalWorkloadStatus {
    fn default() -> Self {
        Self { conditions: vec![] }
    }
}

/// WorkloadCondition represents the service state of an ExternalWorkload
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Condition {
    /// Type of the condition
    // see: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#pod-conditions
    #[serde(rename = "type")]
    pub(crate) typ: String,
    /// Status of the condition.
    /// Can be True, False, Unknown
    status: ConditionStatus,
    /// Last time a condition transitioned from one status to another.
    last_transition_time: Option<metav1::Time>,
    /// Last time an ExternalWorkload was probed for a condition.
    last_probe_time: Option<metav1::Time>,
    /// Unique one word reason in CamelCase that describes the reason for a
    /// transition.
    reason: Option<String>,
    /// Human readable message that describes details about last transition.
    message: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize, JsonSchema)]
pub enum ConditionStatus {
    True,
    False,
    Unknown,
}

pub fn mk_condition() -> Condition {
    Condition {
        typ: WORKLOAD_READY_COND.to_string(),
        status: ConditionStatus::True,
        message: Some("Workload created".into()),
        reason: Some("WorkloadCreated".into()),
        last_probe_time: Some(Time(super::now())),
        last_transition_time: Some(Time(super::now())),
    }
}

pub fn is_ready(cond: &Condition) -> bool {
    cond.typ == WORKLOAD_READY_COND && cond.status == ConditionStatus::True
}

pub fn mk_external_workload(
    name: &str,
    namespace: &str,
    ports: Vec<NonZeroU16>,
) -> ExternalWorkload {
    let ports = ports
        .into_iter()
        .map(|p| PortSpec {
            port: p,
            name: None,
            protocol: None,
        })
        .collect();
    ExternalWorkload {
        metadata: kube::api::ObjectMeta {
            name: Some(name.into()),
            namespace: Some(namespace.into()),
            ..Default::default()
        },
        spec: ExternalWorkloadSpec {
            mesh_tls: MeshTls {
                identity: format!(
                    "{name}.{namespace}.serviceaccount.identity.linkerd.cluster.local"
                ),
                server_name: format!("{name}.{namespace}.cluster.local"),
            },
            ports: Some(ports),
            workload_ips: Some(vec![WorkloadIP {
                ip: "192.0.2.0".into(),
            }]),
        },
        status: None,
    }
}

pub fn now() -> DateTime<Utc> {
    Utc::now()
}

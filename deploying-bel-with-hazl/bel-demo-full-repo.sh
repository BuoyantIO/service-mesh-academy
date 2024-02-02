#!/bin/bash
# steps-repo.sh
# Demo script for the deploying-bel-with-hazl GitHub repository
# https://github.com/southsidedean/deploying-bel-with-hazl
# Full script, to match the README.md
# Requires demo-magic.sh
# Automates the demonstration
# Jason Morgan | Tom Dean | Buoyant
# Last edit: 1/30/2024

# Source the demo-magic.sh script
source demo-magic.sh

# Demo execution steps
# This is where you start the actual demo

echo "Welcome to the Buoyant Enterprise for Linkerd Installation, HAZL and Policy Generation demonstration!"
echo "Press ENTER to start the demonstration."
wait
clear

# Clean up existing k3d demo-cluster
clear
echo "Cleaning up existing demo-cluster..."
echo
pe "k3d cluster delete demo-cluster"
echo
echo "Cluster deletion complete!"
wait
clear

# Create new k3d demo-cluster, using the configuration in cluster/hazl.yaml file
echo "Creating new demo-cluster..."
echo
pe "k3d cluster create -c cluster/demo-cluster.yaml --wait"
echo
echo "Cluster creation complete!"
wait
clear

# Let's confirm our cluster exists
echo "Let's confirm that our cluster exists."
echo
pe "k3d cluster list"
wait
clear

# Let's check out our cluster nodes
echo "Let's check out our cluster's nodes."
echo
pe "kubectl get nodes"
wait
clear

# Generate certificates
echo "We're going to create a Kubernetes Secret that will be used by Helm at runtime, and will need ca.crt, issuer.crt, and issuer.key files."
echo
echo "Cleaning up any existing certificates..."
echo
rm certs/*.{crt,key}
echo "Contents of the 'certs' directory:"
ls -la certs
echo
echo "Generating certificates..."
echo
pe "cd certs"
echo "Generating root certificate."
echo
pe "step certificate create root.linkerd.cluster.local ca.crt ca.key --profile root-ca --no-password --insecure"
echo
echo Generating intermediate certificate and key pair.
echo
pe "step certificate create identity.linkerd.cluster.local issuer.crt issuer.key --profile intermediate-ca --not-after 8760h --no-password --insecure --ca ca.crt --ca-key ca.key"
echo
echo "Certificates in place:"
ls -al
pe "cd .."
echo
wait
clear

# Source the settings.sh script
echo "I already have my trial credentials, and have my environment variables configured in my settings.sh file."
echo "Let's take a look at the settings.sh file."
echo
pe "more settings.sh"
echo
echo "Let's apply our settings from settings.sh."
pe "source settings.sh"
echo
echo "Settings applied!"
wait
clear

# Let's install the Linkerd CLI
echo "Let's install the Linkerd CLI!"
echo
echo "First, download the BEL CLI."
pe "curl -sL https://enterprise.buoyant.io/install-preview | sh"
echo
echo "Next, add the CLI executables to your \$PATH."
echo
pe "export PATH=/home/tdean/.linkerd2/bin:\$PATH"
echo
echo "\$PATH set!"
wait
clear

# Environment Variable Pre-Checks
echo "Checking Environment Variables."
echo
echo "Value of \$API_CLIENT_ID: "$API_CLIENT_ID
echo
echo "Value of \$API_CLIENT_SECRET: "$API_CLIENT_SECRET
echo
echo "Value of \$BUOYANT_LICENSE: "$BUOYANT_LICENSE
echo
echo "Value of \$CLUSTER_NAME: "$CLUSTER_NAME
wait
clear

# Run Linkerd pre-checks
echo "Running Linkerd pre-checks..."
echo
pe "linkerd check --pre"
wait
clear

# Install BEL Operator Components
echo "Let's install the BEL Operator components."
echo

# Add the linkerd-buoyant Helm repository
echo "Add the linkerd-buoyant Helm repository."
echo
pe "helm repo add linkerd-buoyant https://helm.buoyant.cloud"
echo

# Update Helm repositories
echo "Update the Helm repositories."
echo
pe "helm repo update"
wait
clear

# Now, we can install the BEL operator itself
echo "Now, we can install the BEL operator itself."
echo
pe "helm install linkerd-buoyant \\
  --create-namespace \\
  --namespace linkerd-buoyant \\
  --set metadata.agentName=\"\${CLUSTER_NAME}\" \\
  --set metrics.debugMetrics=true \\
  --set api.clientID=\"\${API_CLIENT_ID}\" \\
  --set api.clientSecret=\"\${API_CLIENT_SECRET}\" \\
linkerd-buoyant/linkerd-buoyant"
echo
echo "BEL install under way!"
wait
clear

# Wait for the metrics agent to be ready
echo "Waiting for the metrics agent to be ready."
echo
pe "kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant"
echo
echo "Rollout complete!"
wait
clear

# Run the post-install operator health checks
echo "Run the post-install operator health checks"
echo
pe "linkerd buoyant check"
wait
clear

# Create the linkerd-identity-secret.yaml file
echo "Create the linkerd-identity-secret.yaml file"
echo
pe "cat <<EOF > linkerd-identity-secret.yaml
---
apiVersion: v1
data:
  ca.crt: \$(base64 < certs/ca.crt | tr -d '\n')
  tls.crt: \$(base64 < certs/issuer.crt| tr -d '\n')
  tls.key: \$(base64 < certs/issuer.key | tr -d '\n')
kind: Secret
metadata:
  name: linkerd-identity-issuer
  namespace: linkerd
type: kubernetes.io/tls
EOF"
echo
echo "The linkerd-identity-secret.yaml file has been created!"
wait
clear

# Review the linkerd-identity-secret.yaml file
echo "Let's review the linkerd-identity-secret.yaml file."
echo
pe "more linkerd-identity-secret.yaml"
wait
clear

# Create the linkerd-identity-secret
echo "Create the linkerd-identity-secret."
echo
pe "kubectl apply -f linkerd-identity-secret.yaml"
echo
echo "Checking secrets..."
echo
pe "kubectl get secrets -A"
wait
clear

# Create the Linkerd BEL Operator CRD
echo "Create the Linkerd BEL Operator CRD."
echo
pe "cat <<EOF > linkerd-control-plane-config.yaml
---
apiVersion: linkerd.buoyant.io/v1alpha1
kind: ControlPlane
metadata:
  name: linkerd-control-plane
spec:
  components:
    linkerd:
      version: preview-24.1.3
      license: $BUOYANT_LICENSE
      controlPlaneConfig:
        proxy:
          image:
            version: preview-24.1.3-hazl
        identityTrustAnchorsPEM: |
\$(sed 's/^/          /' < certs/ca.crt )
        identity:
          issuer:
            scheme: kubernetes.io/tls
        destinationController:
          experimentalArgs:
          # - -experimental-endpoint-zone-weights
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: DoesNotExist
EOF"
echo
echo "The linkerd-control-plane-config.yaml file has been created!"
wait
clear

# Review the linkerd-control-plane-config.yaml file
echo "Review the linkerd-control-plane-config.yaml file."
echo
pe "more linkerd-control-plane-config.yaml"
wait
clear

# Create the Linkerd Control Plane
echo "Create the Linkerd Control Plane"
echo
pe "kubectl apply -f linkerd-control-plane-config.yaml"
wait
clear

# Let's check out our pods
echo "Let's check out the pods in our cluster again and watch the Control Plane deployment."
echo
pe "watch -n 1 kubectl get pods -A -o wide --sort-by .metadata.namespace"
wait
clear

# Verify Linkerd installation
echo "Verify Linkerd installation."
echo
pe "linkerd check"
wait
clear

# Create the Dataplane Objects
echo "Create the Dataplane Objects"
echo
pe "kubectl apply -f - <<EOF
---
apiVersion: linkerd.buoyant.io/v1alpha1
kind: DataPlane
metadata:
  name: linkerd-buoyant
  namespace: linkerd-buoyant
spec:
  workloadSelector:
    matchLabels: {}
EOF"
echo
echo "The Dataplane Objects have been created!"
wait
clear

# Monitor Buoyant Cloud Metrics Rollout
echo "Monitor Buoyant Cloud Metrics Rollout"
echo
pe "kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant"
wait
clear

# Check linkerd-buoyant Proxies
echo "Check linkerd-buoyant Proxies"
echo
pe "linkerd check --proxy -n linkerd-buoyant"
wait
clear

# Deploy the colorz application
echo "Deploy the colorz application."
echo
pe "kubectl apply -k colorz"
echo
echo "The colorz application has been deployed!"
wait
clear

# Create Security Policy
echo "Create Security Policy"
echo
pe "linkerd policy generate | kubectl apply -f -"
echo
echo "The Security Policy has been created!"
wait
clear

# Let's take a look at the colorz application in Buoyant Cloud!
echo "Let's take a look at the colorz application in Buoyant Cloud!"
echo
wait
clear

# Let's take a look at how quick and easy we can enable High Availability Zonal Load Balancing (HAZL)
echo "Let's take a look at how quickly we can enable High Availability Zonal Load Balancing (HAZL)."
echo
pe "vim linkerd-control-plane-config.yaml"
wait
clear
echo "Apply the ControlPlane CRD config to have the Linkerd BEL operator update the Linkerd control plane configuration, and enable HAZL"
echo
pe "kubectl apply -f linkerd-control-plane-config.yaml"
wait
clear

# Let's take a look at the colorz application in Buoyant Cloud!
echo "Let's take a look at the colorz application in Buoyant Cloud!"
echo
wait
clear

# Let's take a look at how straightforward it is to disable High Availability Zonal Load Balancing (HAZL)
echo "Let's take a look at how straightforward it is to disable High Availability Zonal Load Balancing (HAZL)."
echo
pe "vim linkerd-control-plane-config.yaml"
wait
clear
echo "Apply the ControlPlane CRD config to have the Linkerd BEL operator update the Linkerd control plane configuration, and disable HAZL"
echo
pe "kubectl apply -f linkerd-control-plane-config.yaml"
wait
clear


# Let's take a look at the colorz application in Buoyant Cloud!
echo "Let's take a look at the colorz application in Buoyant Cloud!"
echo
wait
clear

# Demo complete
echo "The demonstration is complete!"
wait
clear

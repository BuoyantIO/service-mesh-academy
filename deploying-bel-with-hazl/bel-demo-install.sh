#!/bin/bash
# steps-demo.sh
# Demo script for the deploying-bel-with-hazl GitHub repository
# https://github.com/BuoyantIO/service-mesh-academy/tree/main/deploying-bel-with-hazl
# Condensed script for a more focused demonstration
# Requires demo-magic.sh
# Automates the demonstration
# Jason Morgan | Tom Dean | Buoyant
# Last edit: 2/2/2024

# Source the demo-magic.sh script
source demo-magic.sh

# Demo preparation steps
# Run these prior to starting the demo

clear
echo "Starting demo prep..."
echo

# Clean up existing k3d demo-cluster
echo "Cleaning up existing demo-cluster..."
echo
k3d cluster delete demo-cluster
echo
echo "Cluster deletion complete!"
echo

# Create new k3d demo-cluster, using the configuration in cluster/hazl.yaml file
echo "Creating new demo-cluster..."
echo
k3d cluster create -c cluster/demo-cluster.yaml --wait
echo
echo "Cluster creation complete!"
echo

# Let's confirm our cluster exists
echo "Let's confirm that our cluster exists."
echo
k3d cluster list
echo

# Let's check out our cluster nodes
echo "Let's check out our cluster's nodes."
echo
kubectl get nodes
echo

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
cd certs
echo "Generating root certificate."
echo
step certificate create root.linkerd.cluster.local ca.crt ca.key \
--profile root-ca --no-password --insecure
echo
echo Generating intermediate certificate and key pair.
echo
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
--profile intermediate-ca --not-after 8760h --no-password --insecure \
--ca ca.crt --ca-key ca.key
echo
echo "Certificates in place:"
ls -al
cd ..
echo

# Demo execution steps
# This is where you start the actual demo
# This is for Installation/HAZL/Policy demo

echo "Welcome to the Buoyant Enterprise for Linkerd Installation, HAZL and Policy Generation demonstration!"
echo "Your demo environment is ready.  Press ENTER to start the demonstration."
wait
clear

# Source the settings.sh script
echo "You're going to need some information to install Buoyant Enterprise Linkerd."
echo "To get system credentials for accessing the Buoyant Enterprise for Linkerd trial images,"
echo "go to the Buoyant Enterprise for Linkerd Installation page, and follow the instructions."
echo
echo "=============================================="
echo "URL: https://enterprise.buoyant.io/start_trial"
echo "=============================================="
echo
echo "I already have my trial credentials, and have my environment variables configured in my settings.sh file."
echo "Let's take a look at the settings.sh file."
echo
pe "more settings.sh"
echo
echo "Let's apply our settings from settings.sh."
pe "source settings.sh"
echo
echo "Settings applied!"
echo

# Environment Variable Pre-Checks
echo "Checking Environment Variables."
echo
echo "Value of API_CLIENT_ID: "$API_CLIENT_ID
echo
echo "Value of API_CLIENT_SECRET: "$API_CLIENT_SECRET
echo
echo "Value of BUOYANT_LICENSE: "$BUOYANT_LICENSE
echo
echo "Value of CLUSTER_NAME: "$CLUSTER_NAME
wait
clear

# Let's install the Linkerd CLI
echo "Let's install the Linkerd CLI!"
echo
echo "First, download the BEL CLI."
pe "curl -sL https://enterprise.buoyant.io/install-preview | sh"
echo
echo "Next, add the CLI executables to your \$PATH."
echo "Injecting ~/.linkerd2/bin into \$PATH."
export PATH=~/.linkerd2/bin:$PATH
echo
echo "\$PATH set!"
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
echo "We'll use the linkerd-buoyant Helm chart to install the operator."
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

# Now, we can install the BEL operator
echo "Now, we can install the BEL operator, using Helm."
echo
echo "BEL install under way!"
echo
pe "helm install linkerd-buoyant \\
  --create-namespace \\
  --namespace linkerd-buoyant \\
  --set metadata.agentName=\"\${CLUSTER_NAME}\" \\
  --set metrics.debugMetrics=true \\
  --set api.clientID=\"\${API_CLIENT_ID}\" \\
  --set api.clientSecret=\"\${API_CLIENT_SECRET}\" \\
linkerd-buoyant/linkerd-buoyant"
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
echo "We want to make sure everything deployed properly, so let's run the post-install operator health checks"
echo
pe "linkerd buoyant check"
wait
clear

# Create the linkerd-identity-secret.yaml file
echo "We're going to use the Linkerd Trust Root CA & Identity Certificates & Keys to create a Kubernetes Secret"
echo "that will be used by Helm at runtime."
echo
echo "Creating the linkerd-identity-secret.yaml file..."
echo
cat <<EOF > linkerd-identity-secret.yaml
---
apiVersion: v1
data:
  ca.crt: $(base64 < certs/ca.crt | tr -d '\n')
  tls.crt: $(base64 < certs/issuer.crt| tr -d '\n')
  tls.key: $(base64 < certs/issuer.key | tr -d '\n')
kind: Secret
metadata:
  name: linkerd-identity-issuer
  namespace: linkerd
type: kubernetes.io/tls
EOF
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
echo "Create a CRD config that will be used by the BEL operator to install and manage the Linkerd control plane."
echo "We will need the ca.crt file from above. This CRD configuration also enables High Availability Zonal Load Balancing (HAZL),"
echo "using the - -experimental-endpoint-zone-weights experimentalArgs. We're going to omit the - -experimental-endpoint-zone-weights"
echo "in the experimentalArgs for now, by commenting it out with a # in the manifest."
echo
echo "Creating the Linkerd BEL Operator CRD."
echo
cat <<EOF > linkerd-control-plane-config.yaml
---
apiVersion: linkerd.buoyant.io/v1alpha1
kind: ControlPlane
metadata:
  name: linkerd-control-plane
spec:
  components:
    linkerd:
      version: preview-24.1.4
      license: $BUOYANT_LICENSE
      controlPlaneConfig:
        proxy:
          image:
            version: preview-24.1.4-hazl
        identityTrustAnchorsPEM: |
$(sed 's/^/          /' < certs/ca.crt )
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
EOF
echo
echo "The linkerd-control-plane-config.yaml file has been created!"

# Review the linkerd-control-plane-config.yaml file
echo "Let's review the linkerd-control-plane-config.yaml manifest file we just created."
echo
pe "more linkerd-control-plane-config.yaml"
wait
clear

# Create the Linkerd Control Plane
echo "We can now apply the ControlPlane CRD configuration to have the Linkerd BEL operator create the Linkerd control plane."
echo
pe "kubectl apply -f linkerd-control-plane-config.yaml"
wait
clear

# Let's check out our pods
echo "Let's check out the pods in our cluster to see what we're created so far."
echo
pe "watch -n 1 kubectl get pods -A -o wide --sort-by .metadata.namespace"
wait
clear

# Verify Linkerd installation
echo "We can verify the health and configuration of Linkerd by running the 'linkerd check' command."
echo
pe "linkerd check"
wait
clear

# Create the Dataplane Objects
echo "To create the Dataplane Objects, we'll inject a small YAML manifest into kubectl."
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
echo
echo "With that you will see the Linkerd proxy get added to the Buoyant Cloud Agent."
echo "We've successfully installed a trial of Buoyant Enterprise for Linkerd. We can now use Linkerd"
echo "to manage and secure our Kubernetes applications."
echo
echo "To make adjustments to the Linkerd deployment simply edit and re-apply the previously-created linkerd-control-plane-config.yaml CRD config."
wait
clear

# Monitor Buoyant Cloud Metrics Rollout
echo "Let's monitor the Buoyant Cloud Metrics Rollout"
echo
echo "While the rollout is under way, we can hop over to Buoyant Cloud and see things start to light up."
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
echo "Let's have BEL generate a Security Policy for our 'colorz' application."
echo
pe "linkerd policy generate | kubectl apply -f -"
echo
echo "The Security Policy has been created!"
wait
clear

# Let's take a look at the colorz application in Buoyant Cloud!
echo "Let's jump over to the web browser and take a look at the 'colorz' application in Buoyant Cloud!"
echo "We're going to pay particular attention to traffic flow and check out the Security Policies we just generated."
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
echo "Let's take a look at the colorz application in Buoyant Cloud, and see what effect enabling HAZL has on cross-zone traffic."
wait
clear

# Now HAZL is working, and traffic is staying in a single availability zone.
# What happens when we turn the traffic up and overwhelm the single color?
# We'll adjust the number of requests sent by the brush from 50 to 300.

echo "We've accomplished our goal, HAZL is working, and traffic for our 'colorz' application is staying in a single availability zone."
echo
echo "Life is good."
echo
echo "What happens when we turn the traffic up and overwhelm the single color service?"
echo "We'll adjust the number of requests sent by the brush from 50 to 300."
echo
pe "kubectl edit cm brush-config -n colorz"
echo
echo "This will increase the number of requests the 'brush' is sending."
echo
echo "Let's take a look at the effect this has on traffic for the 'colorz' namespace, in Buoyant Cloud."
wait
clear

# We can end the demonstration here if we want.
# If we want to turn things around and see the reverse, continue, otherwise press CTRL-C

echo "We can end the demonstration here if we want."
echo "If we want to turn things around and see the reverse, continue, otherwise press CTRL-C"
wait
clear

# We'll set the number of requests that the 'brush' makes back to 50 from 300
echo "We'll adjust the number of requests sent by the 'brush' back to 50 from the current 300."
echo
pe "kubectl edit cm brush-config -n colorz"
echo
echo "This will decrease the number of requests the 'brush' is sending."
echo
echo "Let's take a look at the effect this has on traffic for the 'colorz' namespace, in Buoyant Cloud."
wait
clear

# Demo complete
echo "The demonstration is complete!"
wait
clear

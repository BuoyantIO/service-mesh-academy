# Non-Production: Setting up an In-Cluster Trust Anchor
#
# WARNING WARNING WARNING WARNING
# This is not what you really want to do in production!!
# WARNING WARNING WARNING WARNING
#
# In real-world production, you really don't want to ever have the trust
# anchor's private key present in your cluster at all: instead, you want to
# let cert-manager hand off a CSR to your off-cluster CA and get a signed
# certificate. `cert-manager` supports several different mechanisms here,
# including Vault, Venafi, etc.
#
# Those mechanisms are out of scope for this SMA, so we're going to create
# a trust anchor certificate, load it into the cluster, and then set up a
# cert-manager Issuer based on it. Again, don't do this in the real world.
#
# We'll start by creating the trust anchor certificate with `step`. You can
# read much more about this in the l5d-certificate-management SMA, but the
# short version is:
#
#   root.linkerd.cluster.local is the Subject CN;
#   ca.crt and ca.key are the output files for public and private key;
#   the rest is boilerplate for a root CA cert with a ten-year expiry.

rm -rf ca.crt ca.key

step certificate create \
     root.linkerd.cluster.local \
     ca.crt ca.key              \
     --profile root-ca          \
     --no-password --insecure   \
     --not-after=87600h

# Given the trust anchor cert, create the linkerd namespace and save the
# trust anchor cert as a Secret. Note the ca.crt and ca.key files; these are
# outputs from step above.

kubectl create ns linkerd

kubectl create secret tls linkerd-trust-anchor \
        --cert=ca.crt \
        --key=ca.key \
        --namespace=linkerd

# Finally, we'll create an Issuer using the trust anchor cert. For a
# real-world install, this Issuer would instead be configured to connect to
# your external secret store.
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: linkerd-trust-anchor
  namespace: linkerd
spec:
  ca:
    secretName: linkerd-trust-anchor
EOF

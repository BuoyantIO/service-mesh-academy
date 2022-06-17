# Install Linkerd with cert-manager and an external issuer

These steps will guide you through installing Linkerd without generating any
certificates locally, and without having Linkerd generate the certificates
itself. By using cert-manager, we can generate Linkerd's mTLS certificates and
have them signed by an external issuer.

The **objective** of this document is to show how an enterprise, or a company
that already uses a PKI, can make use of the existing infrastructure to
bootstrap a zero-trust environment in Kubernetes without much work.

This guide assumes everything will be done locally on the machine. The first
steps will focus on configuring a Kubernetes cluster and a PKI engine. If you
already have a PKI server running somewhere -- great, just replace the
endpoints (and skip steps) accordingly.


## Spin up a local k8s cluster

[host-internal]: https://k3d.io/v5.2.0/faq/faq/#how-to-access-services-like-a-database-running-on-my-docker-host-machine
[k3d-docs]: https://k3d.io/v5.2.0/

The first requirement is to have a working Kubernetes environment. Anything
`v1.21+` should work well. I recommend using something like [`k3d`][k3d-docs].
If in doubt on how to install, refer to their documentation. Other tools such
as `kind` and `minikube` should work as well. I do not recommend trying this
out in an actual hosted cluster unless you also have an external issuer server
that you can easily access from within the environment.

```sh
#
# Pre-flight check
#

$ k3d version
k3d version v5.4.3
k3s version v1.23.6-k3s1 (default)
```

* Since we will be running the external issuer server locally, we need to have
access to our machine's IP. An easy way to do this which is platform agnostic,
is to apply a network utils pod, exec onto it, and resolve
[`host.k3d.internal`][host-internal].

```sh
#
# Cluster creation
#

$ k3d cluster create demo

# Run a shell pod and make a note of what nslookup returns
$ kubectl run tmp-shell --tty --image nicolaka/netshoot -i -- /bin/bash
bash-5.1# nslookup host.k3d.internal
Name:   host.k3d.internal
Address: 172.29.0.1

```

* We will configure our external issuer to be bound on all networks
  (`0.0.0.0`), it will be addressable by our k3d pods by making requests to the
  host's IP address, which we have just retrieved.

We are now ready to mess around with our external issuer

## Configure Vault

[vault-install-docs]: https://learn.hashicorp.com/tutorials/vault/getting-started-install?in=vault/getting-started

* If you haven't already, follow the instructions to [install
Vault][vault-install-docs] on your target platform.

* We can now run `Vault` in the background, or in a separate shell session.

```sh
#
# Starting Vault
#
# Either export VAULT_ADDR=http://0.0.0.0:8200
# or type it before the commands, like in the example
#

$ vault server -dev -dev-root-token-id root -dev-listen-address 0.0.0.0:8200 &

# Login as root
$ VAULT_ADDR=http://0.0.0.0:8200 vault login root

# Enable vault pki engine
$ VAULT_ADDR=http://0.0.0.0:8200 vault secrets enable pki

# Test Vault connectivity
$ kubectl exec tmp-shell -it -- bash
  bash-5.1# dig +short host.k3d.internal | xargs -I{} curl -s http://{}:8200/v1/sys/seal-status
```

* We need to configure `Vault` with the pki endpoints, and we need to tell
  it to enable the secrets engine.
* In order for `cert-manager` to use `Vault`, we will also need to create a set
  of roles that will permit us to sign certificates. We will also need to
  create a token that will be used for any signing requests.

```sh
#
# Vault config & policies
#

# First, enable the secrets engine if you have not done so already
$ vault secrets enable pki

# Tune certs to satisfy 90 days request
$ vault secrets tune -max-lease-ttl=8760h pki

# Generate a root CA keypair
$ vault write pki/root/generate/internal common_name=root.linkerd.cluster.local ttl=8760h key_type=ec

# Configure vault endpoints, we can use the address of our vault server (127.0.0.1:8200)
$ vault write pki/config/urls \
   issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
   crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"

# Create a vault policy
$ echo 'path "pki*" {  capabilities = ["create", "read", "update", "delete", "list", "sudo"]}' \
   |vault policy write pki_policy -

# Create a token that uses the policy we just created; this will output a token
# save the token for later
$ vault write /auth/token/create policies="pki_policy" \
   no_parent=true no_default_policy=true renewable=true \
   ttl=767h num_uses=0

# Copy token, encode it and create a k8s secret in the cert-manager namespace.
# See `token.yaml` for an example
$ kubectl create secret generic \
       my-secret-token \
       --namespace=cert-manager \
       --from-literal=token={token}
```

## Deploy the manifests

[trust-docs]: https://github.com/cert-manager/trust

* With `Vault` configured and in place, all that's left is to start creating
  certificates. We'll be using cert-manager to handle all of this for us.

* cert-manager will take declarative manifests and create certificates based on
  them. Certificates will be stored in a `Secret` that will contain the public
  information (certificate itself) and its private key. We will need to install
  a second tool to help us turn some of these secrets into config-maps. We will
  be using [trust][trust-docs]

```sh
#
# Install cert-manager and trust
#

# First, cert-manager
$  helm upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace

# Second, trust
$  helm upgrade -i -n cert-manager cert-manager-trust jetstack/cert-manager-trust --wait -n cert-manager

# Quick healthcheck
$ kubectl get pods -n cert-manager

NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-cainjector-5c55bb7cb4-ths8s   1/1     Running   0          2m34s
cert-manager-76578c9687-v8zm6              1/1     Running   0          2m34s
cert-manager-webhook-556f979d7f-k24bj      1/1     Running   0          2m34s
cert-manager-trust-5c4b6f8ff6-d5k2k        1/1     Running   0          36s

```

* Linkerd requires two CAs: a root CA (trust anchor) and an intermediate signed
  by the root (identity-issuer).


First, we will deploy a `ClusterIssuer` resource to handle our CSRs by sending
them to be signed by the CA we generated in our external issuer

```sh
#
# Create an issuer to handle in-cluster, cert-manager CSRs
#

#
# apiVersion: cert-manager.io/v1
# kind: ClusterIssuer
# metadata:
#   name: vault-issuer
#   namespace: cert-manager
# spec:
#   vault:
#     path: pki/root/sign-intermediate # our endpoint
#     server: http://172.28.0.1:8200 # our addressable vault server
#     auth:
#       tokenSecretRef:
#          name: my-secret-token # ref to the token applied in 2nd step
#          key: token
#
# this manifest is taken from vault-issuer.yaml

# Apply manifest
$ kubectl apply -f vault-issuer.yaml

# Check result
$ kubectl get clusterissuers -o wide
```

Now that cert-manager can sign our certificates, let's create our root linkerd
CA and our intermediate cert.

```sh
#
# Create Linkerd certs
#
# Fortunately, the manifests can be applied as they are
# no need to change them
#

# Create issuer cert
$ kubectl apply -f linkerd-issuer-cert.yaml

# Create bundle to turn trust root into a cm
$ kubectl apply -f linkerd-root-bundle.yaml

# Copy secret over to linkerd namespace
$ kubectl get secret linkerd-identity-issuer --namespace=cert-manager -o yaml \
  | grep -v '^\s*namespace:\s'  \
  | kubectl apply --namespace=linkerd -f -


```


We're ready to deploy Linkerd

```
$ linkerd install --identity-external-issuer \
   --set "identity.externalCA=true" \
  |kubectl apply -f - 
```

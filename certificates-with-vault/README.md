# Certificate Management with Vault

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about certificate management with Vault. The easiest way to
use this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

<!-- set -e -->

@import demosh/demo-tools.sh -->
@import demosh/check-requirements.sh -->

<!-- @start_livecast -->

```bash
BAT_STYLE="grid,numbers"
```

---
<!-- @SHOW -->

# Certificate Management with Vault

Welcome to the Service Mesh Academy about Vault and certificates with Linkerd!
We'll show off a fairly real-world scenario, where we'll install Linkerd
without generating any certificates by hand, and without having Linkerd
generate the certificates itself. Instead, we'll use Vault running _outside_
the cluster along with cert-manager running _inside_ the cluster to securely
manage all the keys for us.

Note that our goal is **not** to teach you how to use Vault, in particular:
it's to show a practical, relatively low-effort way to actually use external
PKI with Linkerd to bootstrap a zero-trust environment in Kubernetes. Many
companies have existing external PKI already set up (whether with Vault or
something else); being able to make use of it without too much work is a huge
win.

<!-- @wait_clear -->

## The Setup

In order to demo all this simply, we'll be running Kubernetes in a `k3d`
cluster. We'll run Vault in Docker to make things easy to demo, but we will
_not_ be running Docker in Kubernetes: it will be a separate Docker container
that happens to be connected to the same Docker network as our `k3d` cluster.

The big win of this setup is that you can run it completely on a laptop with
no external dependencies. If you want to replicate this with clusters in the
cloud, the main thing to worry about is making sure that your Kubernetes
cluster has IP connectivity to your Vault instance. Everything else should be
pretty much the same.

<!-- @wait -->

The way all the pieces fit together here is more complex than normal:

- We'll start by creating our `k3d` cluster. This will be named `pki-cluster`,
  and we'll tell `k3d` to connect it to a network named `pki-network`.
- We'll then fire up Vault in a Docker container that's also connected to
  `pki-network`. (And yes, we'll use Vault in dev mode to make life easier,
  but that's the only way we'll cheat in this setup.)
- We'll then use the `vault` CLI _running on our local host machine_ to
  configure Vault in Docker.

Taken together, this implies that we'll have to make sure that we can talk to
the Vault instance both from inside the Docker network and from our host
machine. This mirrors many real-world setups where your Kubernetes cluster is
on one network, but you do administration from a different network.

<!-- @wait_clear -->

## 1. Starting our `k3d` cluster

First up, make sure we don't have an old cluster lying around:

```bash
k3d cluster delete pki-cluster
```

Next up, create our new cluster! This command looks complex, but it's actually
less terrible than you might think -- most of it is just turning off things we
don't need (traefik, local-storage, and metrics-server), and we also expose
ports 80 and 443 to our local system to make it easy to try services out.

```bash
k3d cluster create pki-cluster \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
    --network=pki-network \
    --k3s-arg '--disable=local-storage,traefik,metrics-server@server:*;agents:*'
```

Once that's done, let's just make sure we can talk to it:

```bash
kubectl get ns
```

<!-- @wait_clear -->

## 2. Starting Vault

We have a running `k3d` cluster, so now let's get Vault going. This is another
complex-looking command:

```
docker run \
       --detach \
       --rm --name vault \
       -p 8200:8200 \
       --network=pki-network \
       --cap-add=IPC_LOCK \
       hashicorp/vault \
       server \
       -dev -dev-listen-address 0.0.0.0:8200 \
       -dev-root-token-id my-token
```

Let's break that down.

<!-- @wait -->

- `docker run`: start a container running in Docker
- `--detach`: basically, run the container in the background
- `--rm --name vault`: remove the container when it dies, and name it "vault"
  so we can find it easily later
- `-p 8200:8200`: expose Vault's API port to our local system
- `--network=pki-network`: connect to the same network as our `k3d` cluster
- `--cap-add=IPC_LOCK`: give the container the `IPC_LOCK` capability, which
  Vault wants

<!-- @wait -->

Next is the image name (`hashicorp/vault`), and then comes the command line
for Vault itself:

- `server` is the command to run
- `-dev -dev-listen-address 0.0.0.0:8200`: run Vault in dev mode, binding on
  all interfaces rather than just `localhost`
- `-dev-root-token-id my-token`: set the dev-mode root "password" to
  `my-token`, which we will use to trivially log in later

<!-- @wait -->

So, off we go! First make sure we don't have some other `vault` container
lying around...

```bash
docker kill vault
```

...then fire up the one we want.

```bash
docker run \
       --detach \
       --rm --name vault \
       -p 8200:8200 \
       --network=pki-network \
       --cap-add=IPC_LOCK \
       hashicorp/vault \
       server \
       -dev -dev-listen-address 0.0.0.0:8200 \
       -dev-root-token-id my-token
```

OK, Vault is running! Let's make sure of that by checking its status from our
local system, using the `vault` CLI. We'll start by setting the `VAULT_ADDR`
environment variable, so that we don't have to include it in every command.
Remember, we'll be running the `vault` CLI on our local system, so we can just
do this all using our local shell.

```bash
export VAULT_ADDR=http://0.0.0.0:8200/
```

Then we can run `vault status` to make sure all's well.

```bash
vault status
```

So far so good.

<!-- @wait_clear -->

## Setting up Vault

Now that we have Vault running, the next step is to set up Vault. We're not
going to go deep into the details of the setup, because this is very
Vault-specific, but we'll talk a bit about it.

We'll start by authenticating our `vault` CLI to the Vault server, using the
`dev-root-token-id` that we passed to the server when we started it running.
Remember, this is running on the local host.

```bash
vault login my-token
```

Next up, we need to enable the Vault PKI engine, and configure its maximum
allowed expiry time for certificates. Here we're using 90 days (2160 hours).

```bash
vault secrets enable pki
vault secrets tune -max-lease-ttl=2160h pki
```

After that, we need to tell Vault to enable the URLs that cert-manager expects
to use when talking to Vault.

```bash
vault write pki/config/urls \
   issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
   crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
```

Finally, cert-manager will need to present Vault with a token before Vault
will actually do things that cert-manager needs. Vault associates tokens with
_policies_, which are kind of like roles in other systems, so we'll start by
creating a policy that allows us to do anything...

```bash
echo 'path "pki*" {  capabilities = ["create", "read", "update", "delete", "list", "sudo"]}' \
   | vault policy write pki_policy -
```

...and then we'll get a token for that policy.

```bash
VAULT_TOKEN=$(vault write -field=token /auth/token/create \
                          policies="pki_policy" \
                          no_parent=true no_default_policy=true \
                          renewable=true ttl=767h num_uses=0)
```

That's the Vault setup done!

<!-- @wait_clear -->

## Creating the Trust Anchor

Finally, we'll tell Vault to actually create our Linkerd trust anchor. Note
that:

- this certificate only exists within Vault;
- we explicitly give it the common name of `root.linkerd.cluster.local`;
- we set its TTL to our maximum of 2160 hours; and
- we tell Vault to generate it using elliptic-curve crypto (`key_type=ec`).

We tell `vault write` to only output the certificate, which we save so that we
can inspect it. Note that the certificate contains no private information, so
this is entirely safe.

```bash
CERT=$(vault write -field=certificate pki/root/generate/internal \
      common_name=root.linkerd.cluster.local \
      ttl=2160h key_type=ec)
echo "$CERT" | step certificate inspect -
```

That's actually all we need there! Now it's on to get cert-manager installed.

<!-- @wait_clear -->

## Installing cert-manager

We'll start by using Helm to install both cert-manager and trust-manager.

```bash
helm repo add --force-update jetstack https://charts.jetstack.io
helm repo update
```

When we install cert-manager, we'll have it create the `cert-manager`
namespace, and install the cert-manager CRDs too.

```bash
helm install cert-manager jetstack/cert-manager \
             -n cert-manager --create-namespace \
             --set installCRDs=true --wait
```

trust-manager will be installed in the `cert-manager` namespace, but we'll
explicitly tell it to use the `linkerd` namespace as its "trust namespace".
The trust namespace is the single namespace from which trust-manager is
allowed to read information, and we're going to need it to read the Linkerd
identity issuer.

We don't need to create the `cert-manager` namespace here (it already exists),
but we _do_ need to create the `linkerd` namespace manually so that we can use
it as the trust namespace.

```bash
kubectl create namespace linkerd
helm install trust-manager jetstack/trust-manager \
             -n cert-manager \
             --set app.trust.namespace=linkerd \
             --wait
```

Let's make sure that things look happy.

```bash
kubectl get pods -n cert-manager
```

<!-- @wait_clear -->

## Configuring cert-manager: the access-token secret

OK, cert-manager is running! Next step, we need to configure it to produce the
certificates we need. This starts with saving the Vault token we got awhile
back for cert-manager to use.

```bash
kubectl create secret generic \
               my-secret-token \
               --namespace=cert-manager \
               --from-literal=token="$VAULT_TOKEN"
```

We don't want to actually look into that secret, but we can describe it to
make sure that there's some data in it, at least.

```bash
kubectl describe secret -n cert-manager my-secret-token
```

So, yes, there's some data in there. Good sign!

<!-- @wait_clear -->

## Configuring cert-manager: the Vault issuer

Recall that Linkerd needs two certificates:

- the _trust anchor_ is the root of the heirarchy for Linkerd; and
- the _identity issuer_ is an intermediate CA cert that must be signed by the
  trust anchor.

We've already told Vault to create the trust anchor for us: next up, we need
to configure cert-manager to create the identity issuer certificate. To do
this, cert-manager will produce a _certificate signing request_ (CSR), which
it will then hand to Vault. Vault will use the CSR to produce a signed
identity issuer for cert-manager.

<!-- @wait -->

To make all this happen, we use a cert-manager ClusterIssuer resource to tell
cert-manager how to talk to Vault. This ClusterIssuer needs three critical bits
of information:

1. The access token, which we just saved in a Secret.
2. The address of the Vault server.
3. The URL path to use to ask Vault for a new certificate. For Vault, this is
   `pki/root/sign-intermediate`.

<!-- @wait -->

So the address of the Vault server is the missing bit at the moment: we can't
use `0.0.0.0` as we've been doing from our local host, because cert-manager
needs to talk to Vault from inside the Docker network. That means we need to
figure out the address of the `vault` container within that network.

Fortunately, that's not that hard: `docker inspect pki-network` will show us
all the details of everything attached to the `pki-network`, as JSON, so we
can use `jq` to extract the single bit that we need: the `IPv4Address`
contained in the block that also has a `Name` of `vault`:

```bash
VAULT_DOCKER_ADDRESS=$(docker inspect pki-network \
                       | jq -r '.[0].Containers | .[] | select(.Name == "vault") | .IPv4Address' \
                       | cut -d/ -f1)
#@immed
echo Vault is running at ${VAULT_DOCKER_ADDRESS}
```

Given the right address for Vault, we can assemble the correct YAML:

```bash
#@immed
sed -e "s/%VAULT_DOCKER_ADDRESS%/${VAULT_DOCKER_ADDRESS}/g" < k8s/vault-issuer.template > k8s/vault-issuer.yaml
bat k8s/vault-issuer.yaml
```

Let's go ahead and apply that, then check to make sure it's happy.

```bash
kubectl apply -f k8s/vault-issuer.yaml
kubectl get clusterissuers -o wide
```

<!-- @wait_clear -->

Now that cert-manager can sign our certificates, let's go ahead and tell
cert-manager how to set things up for Linkerd. First, we'll use a Certificate
resource to tell cert-manager how to use the Vault issuer to issue our
identity issuer certificate:

```bash
bat k8s/identity-issuer-cert.yaml
```

**NOTE** that this Certificate goes in the `linkerd` namespace, **not** the
`cert-manager` namespace! This is because Linkerd actually needs access to the
identity issuer, so we have cert-manager create it where it will need to be
used.

```bash
kubectl apply -f k8s/identity-issuer-cert.yaml
```

Finally, we'll use a Bundle resource to tell trust-manager to copy only the
public half of the trust anchor into a ConfigMap for Linkerd to use. Note that
Bundles are always cluster-scoped -- but also note that the reason we don't
have to specify namespaces for the source and destination is that
trust-manager can only read from its trust namespace, in this case `linkerd`,
and it defaults to writing there too.

```bash
bat k8s/trust-anchor-bundle.yaml
kubectl apply -f k8s/trust-anchor-bundle.yaml
```

Once all that is done, let's take a look at our Certificate and Bundle
resources:

```bash
kubectl get bundle,certificate -A
```

We can see that everything looks good there, great!

<!-- @wait_clear -->
<!-- @SHOW -->

Let's also take a look to make sure that we actually have the things we expect
in the Linkerd namespace. This is a bit ugly if we try to just view the raw
certificates, so let's start with a function to make things simpler to view:

```bash
inspect_cert () {
  sub_selector='\(.extensions.subject_key_id | .[0:16])... \(.subject_dn)'
  iss_selector='\(.extensions.authority_key_id | .[0:16])... \(.issuer_dn)'

  step certificate inspect --format json \
    | jq -r "\"Issuer:  $iss_selector\",\"Subject: $sub_selector\""
}
```

OK. First up, our `linkerd-identity-trust-roots` ConfigMap should have the
trust anchor's public half in the `ca-bundle.crt` key:

```bash
kubectl get configmap \
            -n linkerd linkerd-identity-trust-roots \
            -o jsonpath='{ .data.ca-bundle\.crt }' \
    | inspect_cert
```

We see that this is indeed a self-signed certificate, great!

<!-- @wait -->

Next up: the `linkerd-identity-issuer` Secret. It includes three keys:

- `tls.crt` is the public half of the identity issuer cert;
- `tls.key` is the private key of the identity issuer cert; and
- `ca.crt` is the public half of the identity issuer's signer (this should be
  the same as what's in the bundle above).

Annoyingly, these have an extra layer of base64 encoding applied to them, but
that's OK, we can unwrap that easily enough. So first up, let's look at
`tls.crt`:

```bash
kubectl get secret \
            -n linkerd linkerd-identity-issuer \
            -o jsonpath='{ .data.tls\.crt }' \
    | base64 -d | inspect_cert
```

Not a self-signed cert, good! And here's the info for the trust anchor again:

```bash
#@immed
kubectl get configmap \
            -n linkerd linkerd-identity-trust-roots \
            -o jsonpath='{ .data.ca-bundle\.crt }' \
    | inspect_cert
```

So we can see that yes, the identity issuer was issued by the trust anchor.

<!-- @wait -->

Just for the fun of it, we can look at `ca.crt` in the identity issuer:

```bash
kubectl get secret \
            -n linkerd linkerd-identity-issuer \
            -o jsonpath='{ .data.ca\.crt }' \
    | base64 -d | inspect_cert
```

and yes, that's the same as the trust anchor.

<!-- @wait_clear -->

## Installing Linkerd

**Finally** we're ready to deploy Linkerd! We may as well use Helm for this,
too. Start by setting up Helm repos:

```bash
helm repo add --force-update linkerd https://helm.linkerd.io/stable
helm repo update
```

...then install the Linkerd CRDs.

```bash
helm install linkerd-crds -n linkerd linkerd/linkerd-crds
```

After that we can actually install Linkerd! Pay attention to these `--set`
parameters we pass here:

- `identity.issuer.scheme=kubernetes.io/tls` tells Helm that it should expect
  the identity issuer to already exist, so don't try to create one, and
- `identity.externalCA=true` tells Helm that it should expect the trust bundle
  to already exist, too.

These things, of course, are being handled by cert-manager and trust-manager.

```bash
helm install linkerd-control-plane linkerd/linkerd-control-plane \
     -n linkerd \
     --set identity.issuer.scheme=kubernetes.io/tls \
     --set identity.externalCA=true
```

Once that's done, we can use `linkerd check` to validate that everything
worked:

```bash
linkerd check
```

Note that we see a warning for the identity issuer certificate not being valid
for at least 60 days. That's expected, since we created that with a 48-hour
lifespan!

<!-- @wait_clear -->

## Summary

After all that, we have Vault generating all our certificates, cert-manager
and trust-manager handling rotating and distributing them as needed, and
Linkerd consuming them for mTLS everywhere.

Critically, Vault is _not running in our cluster_, and if you look back over
this whole process, the private key for the trust anchor has never been
revealed outside of Vault. Using an external CA to isolate key generation lets
us dramatically increase security of the overall system.

<!-- @wait -->

Vault, of course, isn't the only external CA we can use: cert-manager supports
a lot of different issuers, including ACME, Vault, Venafi, and many others
issuers (see https://cert-manager.io/docs/configuration/external/). We used
Vault for this workshop because it's free to use and relatively easy to set up
in Docker, but you're encouraged to try other kinds of external CAs.

With that, we're ready to go on and install workloads into our mesh. You can
find the source for this demo at

https://github.com/BuoyantIO/service-mesh-academy

in the `certificates-with-vault` directory. As always, we welcome feedback!
Join us at https://slack.linkerd.io/ for more.

<!-- @wait -->
<!-- @show_slides -->

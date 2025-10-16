<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Certificate Management Without Losing Your Mind
-->

# Certificate Management Without Losing Your Mind

This is the documentation - and executable code! - for the Service Mesh
Academy workshop on certificate management without losing your mind. The
easiest way to use this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires that you have TWO running Kubernetes clusters with
Linkerd and Faces already installed:

- the `manual` cluster (see manual-setup.sh) uses certificates that are
  entirely managed by hand

- the `auto` cluster (see auto-setup.sh) uses cert-manager and
  trust-manager to manage certificates semi-automatically

It doesn't really matter what kind of clusters these are. The setup scripts
use k3d, and on a Mac, we recommend using [OrbStack](https://orbstack.dev) to
back these clusters.

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

# Certificate Management Without Losing Your Mind

## Manual Certificate Management

We're starting out with a cluster called `manual` in which we've already set
up Linkerd with manually-managed certificates.

```bash
kubectl config use-context manual
```

Let's take a look at the certificates that Linkerd is using, starting with the
trust bundle. We should see exactly one certificate in the bundle right now.

```bash
kubectl get configmap \
    -n linkerd linkerd-identity-trust-roots \
    -o jsonpath='{ .data.ca-bundle\.crt }' \
 | step certificate inspect --bundle
```

This is a self-signed certificate -- its `Issuer` and `Subject` are the same
name, and while it has an `X509v3 Subject Key Identifier`, it doesn't have an
`X509v3 Authority Key Identifier`.

<!-- @wait -->

Next up let's look at the identity issuer. This is almost the same command,
but since we're looking at a Secret we have to do a base64 decode before the
`step certificate inspect`:

```bash
kubectl get secret \
    -n linkerd linkerd-identity-issuer \
    -o jsonpath='{ .data.tls\.crt }' \
  | base64 -d \
  | step certificate inspect
```

This is _not_ a self-signed certificate: its `Issuer` and `Subject` have
different names, and it has both an `X509v3 Subject Key Identifier` and an
`X509v3 Authority Key Identifier`... and, in fact, its `Issuer` is the
certificate we saw in the trust bundle.

<!-- @wait_clear -->

## Verifying the Certificates

To verify that is messy, but we can do it! First, let's make a function that
can pull the names and key IDs out of a certificate dump:

```bash
inspect_certs () {
  step certificate inspect --bundle --format json \
    | egrep 'issuer_dn|subject_dn|subject_key_id|authority_key_id' \
    | sed -e 's/^.*"issuer_dn": "\(.*\)",\{0,1\}$/issuer DN:  \1/' \
          -e 's/^.*"subject_dn": "\(.*\)",\{0,1\}$/subject DN: \1/' \
          -e 's/^.*"subject_key_id": "\(.*\)",\{0,1\}$/subject ID: \1/' \
          -e 's/^.*"authority_key_id": "\(.*\)",\{0,1\}.*$/issuer ID:  \1/' \
    | sort
}
```

This looks horrible, but it's really mostly just picking lines and
reformatting. We'll use this function in another function to look at the trust
bundle and the identity issuer and focus in on what we want to see:

```bash
show_chain () {
  echo "Trust bundle:"
  kubectl get cm -n linkerd linkerd-identity-trust-roots \
                 -o jsonpath='{.data.ca-bundle\.crt}' \
    | inspect_certs
  echo
  echo "Identity issuer:"
  kubectl get secret -n linkerd linkerd-identity-issuer \
                     -o jsonpath='{.data.tls\.crt}' \
    | base64 -d \
    | inspect_certs
}
```

Let's run this function and see what we get:

```bash
show_chain
```

We can see that the identity issuer cert was, indeed, issued using the
certificate in the trust bundle!

<!-- @wait -->

Finally, we can go one step further and look at a workload certificate -- this
is what the `linkerd identity` command is for. We'll look at the `face`
workload in the `faces` namespace, using a label selector to find it:

```bash
linkerd identity -n faces -l faces.buoyant.io/component=face
```

Unfortunately we don't get the raw certificate from this command, but we can
notice that the only time `keyid:` appears is in the value for the `X509v3
Authority Key Identifier` field. We can use that to extract the issuer ID:

```bash
linkerd identity -n faces -l faces.buoyant.io/component=face \
    | grep keyid: \
    | sed -e 's/^.*keyid://' \
    | tr -d ':' \
    | tr 'A-Z' 'a-z'
```

This ID matches the `subject ID` of the identity issuer certificate we saw
above.

<!-- @wait_clear -->
<!-- @start_livecast -->

## Manual Rotation

Rotating Linkerd certificates is mostly a matter of being very careful about
what you do when. We'll go through the whole thing manually here, starting
with generating a new trust anchor and a new identity issuer certificate.

### 1. Generate a New Trust Anchor and Identity Issuer

```bash
#@immed
rm -rf certs2
#@immed
mkdir -p certs2
step certificate create \
     --profile root-ca \
     --no-password --insecure \
     --not-after='87600h' \
     root.linkerd.cluster.local \
     certs2/anchor.crt certs2/anchor.key

step certificate create \
     --profile intermediate-ca \
     --no-password --insecure \
     --not-after='2160h' \
     --ca certs2/anchor.crt --ca-key certs2/anchor.key \
     identity.linkerd.cluster.local \
     certs2/issuer.crt certs2/issuer.key
```

We now have a new trust anchor and a new identity issuer certificate. Since
they're stored in PEM format on disk, we can cheat a bit and use our
`inspect_certs` function to look at them:

```bash
echo "New trust anchor:" ;\
inspect_certs < certs2/anchor.crt ;\
echo ;\
echo "New identity issuer:" ;\
inspect_certs < certs2/issuer.crt
```

You can see that the signing relationship is the same as before: the new
identity issuer was signed by the new trust anchor... and, of course, the IDs
are different from our old certificates.

### 2. Update the Trust Bundle

Next up, we need to _add_ the new trust anchor to the trust bundle. We'll do
this with `kubectl edit`, but first we'll dump the new trust anchor so we can
copy it:

```bash
cat certs2/anchor.crt
```

After copying that, we can edit the ConfigMap and literally paste it in:

```bash
kubectl edit configmap -n linkerd linkerd-identity-trust-roots
```

If we look at the trust chain now, we can see that there are _two_
certificates in the trust bundle:

```bash
show_chain
```

The sorting looks weird, but note that we have _two_ IDs now - one for the old
cert and one for the new - and the identity issuer is still signed by the old
trust anchor.

<!-- @wait_clear -->

### 3. Restart the World

After updating the trust bundle, we need to restart _everything_ so that the
control plane and data plane both pick up the new trust anchor. We'll do the
control plane first, then any application data planes (in our case, just the
`faces` namespace):

First, the control plane:

```bash
kubectl rollout restart -n linkerd deploy
kubectl rollout status -n linkerd deploy
```

Then, the application data planes:

```bash
kubectl rollout restart -n faces deploy
kubectl rollout status -n faces deploy
```

At this point, everything will have the new trust bundle, so we can update the
identity issuer.

### 4. Update the Identity Issuer

Updating the identity issuer is more straightforward than updating the trust
bundle: we'll use `kubectl patch` to update the Secret with the new
certificate and key. (This is just overwriting `data/tls.crt` and
`data/tls.key` in the Secret with new base64-encoded values, but the shell
escaping makes it look awful.)

```bash
kubectl patch secret -n linkerd linkerd-identity-issuer --type='json' -p="[ {\"op\": \"replace\", \"path\": \"/data/tls.crt\", \"value\": \"$(base64 -w0 < certs2/issuer.crt)\"}, {\"op\": \"replace\", \"path\": \"/data/tls.key\", \"value\": \"$(base64 -w0 < certs2/issuer.key)\"} ]"
```

We can verify that this worked with with the `show_chain` function again:

```bash
show_chain
```

We can see that our identity issuer is now signed by the new trust anchor, but the
old trust anchor is still in the trust bundle.

<!-- @wait_clear -->

### 5. Restart the Control Plane

At this point, we need to restart the control plane to make sure that the
identity controller picks up the new identity issuer. (We don't need to
restart the data plane again - yet - since it already has the new trust
anchor.)

We could also wait two minutes, but let's not.

```bash
kubectl rollout restart -n linkerd deploy
kubectl rollout status -n linkerd deploy
```

<!-- @wait_clear -->

### 6. Restart the Data Plane(s)

Now that the control plane has the new identity issuer, we need to restart the
data plane(s) so that they get new workload certificates signed by the new
issuer. We could also wait for this to happen as the workload certificates
expire, but that takes a day or so.

```bash
kubectl rollout restart -n faces deploy
kubectl rollout status -n faces deploy
```

At this point, we can use `linkerd identity` to look at a workload certificate
and see that it's signed by the new identity issuer:

```bash
linkerd identity -n faces -l faces.buoyant.io/component=face \
  | grep keyid: \
  | sed -e 's/^.*keyid://' \
  | tr -d ':' \
  | tr 'A-Z' 'a-z'
```

This ID matches the `subject ID` of the new identity issuer certificate we saw
above:

```bash
inspect_certs < certs2/issuer.crt
```

<!-- @wait_clear -->

### 7. Remove the Old Trust Anchor

Once we're sure that everything is working with the new trust anchor and
identity issuer, we can remove the old trust anchor from the trust bundle.
We'll do this with `kubectl edit` again.

```bash
kubectl edit configmap -n linkerd linkerd-identity-trust-roots
```

We can verify that this worked by looking at the trust bundle and the identity
issuer again:

```bash
show_chain
```

We can see that now we have only a single trust anchor in the bundle, and that
it's the signer of the identity issuer.

<!-- @wait_clear -->

### 8. Restart the World

Finally, we need to restart everything one last time to make sure that
everything has the new trust anchor and identity issuer. Again, we'll do the
control plane first, then the data plane(s).

```bash
kubectl rollout restart -n linkerd deploy
kubectl rollout status -n linkerd deploy
kubectl rollout restart -n faces deploy
kubectl rollout status -n faces deploy
```

At this point, everything should be working with the new trust anchor and
identity issuer, and the old trust anchor should be gone.

<!-- @wait_clear -->
<!-- @start_livecast -->

## Certificate Management With cert-manager

For cert-manager, we'll start by switching to our `auto` cluster, in which
we've already set up Linkerd, cert-manager, and trust-manager.

```bash
kubectl config use-context auto
```

Things are mostly simpler with cert-manager and trust-manager, but there are
still manual steps and things to be careful.

## cert-manager Config

Let's start with a very quick look at how cert-manager is set up. We have a
self-signed Issuer and a Certificate for the trust anchor:

```bash
bat cert-manager/trust-anchor-issuer.yaml
bat cert-manager/trust-anchor-cert.yaml
```

Note that the Issuer and Certificate are both in the `cert-manager` namespace.
This is because Linkerd doesn't need access to the trust anchor: it just needs
the trust bundle. This means it's better to put the Certificate (and its
associated Secret) in a namespace that Linkerd doesn't have access to.

We also have a ClusterIssuer and a Certificate for the identity issuer:

```bash
bat cert-manager/identity-issuer-clusterissuer.yaml
bat cert-manager/identity-issuer-cert.yaml
```

We use a ClusterIssuer here because we need to cross namespaces: the trust
anchor cert is in the `cert-manager` namespace, but the identity issuer cert
needs to be in the `linkerd` namespace. A ClusterIssuer is the _only_ way to
tell cert-manager to do this.

<!-- @wait -->

We can check the status on all these resources with `kubectl get`:

```bash
kubectl get issuer,clusterissuer,certificate -A
```

Note that they all say they're `Ready`, telling us that cert-manager has
successfully set everything up. We can also look at the Secrets that
cert-manager has created for us:

```bash
kubectl describe secret -n cert-manager linkerd-trust-anchor
kubectl describe secret -n linkerd linkerd-identity-issuer
```

<!-- @wait_clear -->

## trust-manager Config

For trust-manager, first, we've already copied the `linkerd-trust-anchor`
Secret into the `linkerd-previous-anchor` Secret, so that trust-manager can do
its thing:

```bash
kubectl describe -n cert-manager secret linkerd-previous-anchor
```

Finally, we have a trust-manager Bundle that copies both trust anchor certs
into the trust bundle:

```bash
bat cert-manager/linkerd-identity-trust-roots-bundle.yaml
```

## Using Cert-Manager

So! Let's start by looking at the trust bundle. Our trusty `show_chain`
function will work just fine for this, because we're sticking with the
external-CA setup (since we have to for cert-manager to work!).

```bash
show_chain
```

So far so good!

## Rotation With cert-manager

So it's time to do a rotation. With cert-manager, we can use the `cmctl renew`
command to force this, though of course cert-manager can do it on its own as
the certificates age.

We'll start, though, by setting up a function to get the subject key ID from a
Secret, so that we can tell when cert-manager has actually rotated the
certificates:

```bash
get_subject () {
    kubectl get secret -n "$1" "$2" -o jsonpath='{ .data.tls\.crt }' \
            | base64 -d \
            | step certificate inspect --format json - \
            | jq -r '.extensions.subject_key_id'
}
```

Once again, we're relying on `step certificate inspect` for the heavy lifting
here. Let's use this function to get the current subject key IDs for the trust
anchor and identity issuer:

```bash
previous_anchor=$(get_subject cert-manager linkerd-trust-anchor)
#@immed
echo "Previous trust anchor ID: ${previous_anchor}"
previous_issuer=$(get_subject linkerd linkerd-identity-issuer)
#@immed
echo "Previous identity issuer ID: ${previous_issuer}"
```

And with that, off we go!

<!-- @wait_clear -->

### 1. Rotate the Trust Anchor

We'll start by triggering a rotation of the trust anchor, and then we'll wait
for the new anchor certificate to show up.

```bash
cmctl renew -n cert-manager trust-anchor-cert

while true; do \
    new_anchor=$(get_subject cert-manager linkerd-trust-anchor) ;\
    echo "prev $previous_anchor, current $new_anchor" ;\
    if [ "$new_anchor" != "$previous_anchor" ]; then break; fi ;\
    sleep 1 ;\
done
```

At this point, trust-manager should _also_ have done its thing -- so if we
check the chain again, we should see _two_ certificates in the trust bundle,
but we should see that the identity issuer is still signed by the old trust
anchor:

```bash
echo "Old trust anchor ID $previous_anchor" ;\
echo ;\
show_chain
```

Remember, cert-manager _won't_ actually rotate the identity issuer.

<!-- @wait_clear -->

### 2. Restart the World

As before, we need to restart everything so that the control plane and data
plane(s) pick up the new trust anchor.

```bash
kubectl -n linkerd rollout restart deploy
kubectl -n linkerd rollout status deploy
kubectl -n faces rollout restart deploy
kubectl -n faces rollout status deploy
```

<!-- @wait_clear -->

### 3. Rotate the Identity Issuer

Now we can rotate the identity issuer. Again, we'll use `cmctl renew` to
trigger this, and then we'll wait for the new issuer certificate to show up.

```bash
cmctl renew -n linkerd identity-issuer-cert

while true; do \
    new_issuer=$(get_subject linkerd linkerd-identity-issuer) ;\
    echo "prev $previous_issuer, current $new_issuer" ;\
    if [ "$new_issuer" != "$previous_issuer" ]; then break; fi ;\
    sleep 1 ;\
done
```

At this point, if we check the chain again, we should see that the identity
issuer is now signed by the new trust anchor:

```bash
#@immed
new_anchor=$(get_subject cert-manager linkerd-trust-anchor)
echo "New trust anchor ID $new_anchor" ;\
echo ;\
show_chain
```

<!-- @wait_clear -->

### 4. Restart the Control Plane

Just like before, we need to restart the control plane so that the identity
controller picks up the new identity issuer.

```bash
kubectl -n linkerd rollout restart deploy
kubectl -n linkerd rollout status deploy
```

<!-- @wait_clear -->

### 5. Restart the Data Plane(s)

Next, we need to restart the data plane(s) so that they get new workload
certificates signed by the new identity issuer.

```bash
kubectl -n faces rollout restart deploy
kubectl -n faces rollout status deploy
```

<!-- @wait_clear -->

### 6. Remove the Old Trust Anchor

Once we're sure that everything is working with the new trust anchor and
identity issuer, we can remove the old trust anchor from the trust bundle --
but this time, we do it by copying the `linkerd-trust-anchor` Secret to the
`linkerd-previous-anchor` Secret again, so that trust-manager can do its
thing.

```bash
kubectl get secret -n cert-manager linkerd-trust-anchor -o yaml \
        | sed -e s/linkerd-trust-anchor/linkerd-previous-anchor/ \
        | egrep -v '^  *(resourceVersion|uid)' \
        | kubectl apply -f -
```

Once that's done, we can check the chain again, and we should see just the new
trust anchor in the trust bundle:

```bash
echo "New trust anchor ID $new_anchor" ;\
echo ;\
show_chain
```

<!-- @wait_clear -->

### 7. Restart the World (again)

Finally, we need to restart everything one last time to make sure that all
components are using the new trust anchor and identity issuer.

```bash
kubectl -n linkerd rollout restart deploy
kubectl -n linkerd rollout status deploy
kubectl -n faces rollout restart deploy
kubectl -n faces rollout status deploy
```

At this point, everything should be working with the new trust anchor and
identity issuer, and the old trust anchor should be gone!

<!-- @wait_clear -->

## So... Why Use cert-manager?

If you still have to do all the manual steps, why use cert-manager at all?

<!-- @wait -->

The biggest reason is the integrations. We showed using a self-signed Issuer
for the trust anchor, but cert-manager supports a wide variety of Issuers,
including ACME (for Let's Encrypt), HashiCorp Vault, Venafi's commercial
issuers, and many others. This means that you can integrate with your existing
PKI infrastructure, and you can use cert-manager to manage certificates for
other applications in your cluster as well. This is _much_ cleaner than
storing private keys on your own.

<!-- @wait -->

It's also simpler - as you saw - to trigger renewals. `cmctl renew` works with
any cert-manager integrations, and you don't need to worry about the details
of how each Issuer works.

<!-- @wait -->

And, of course, this is obviously an area where we're actively exploring how
to make things more seamless. Hopefully, though, this gives you a good idea of
what's really going on and how to check everything on your own clusters!

<!-- @wait -->
<!-- @show_slides -->


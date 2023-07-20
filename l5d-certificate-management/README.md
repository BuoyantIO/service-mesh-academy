# Linkerd Certificate Management

This is the documentation - and executable code! - for the Service Mesh
Academy certificate management workshop. The easiest way to use this file is
to execute it with [`demosh`].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [`demosh`], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

For this workshop, you'll need to start with an _empty_ Kubernetes cluster.
You can use `create-cluster.sh` to create an appropriate `k3d` cluster; don't
install anything else after that.

You'll also need [`linkerd`] (version 2.13 or later), [`step`], and [`helm`].
If you're using [`demosh`] to execute this file, it will make sure that you
have everything you need.

[`demosh`]: https://github.com/BuoyantIO/demosh
[`linkerd`]: https://linkerd.io/2/getting-started/
[`step`]: https://smallstep.com/docs/step-cli/installation
[`helm`]: https://helm.sh/docs/intro/quickstart/

<!-- set -e >
<!-- @import demosh/check-requirements.sh -->
<!-- @import demosh/demo-tools.sh -->

<!-- @start_livecast -->

```bash
BAT_STYLE="grid,numbers"
```

----
<!-- @SHOW -->

# Linkerd Certificate Management

We're going to look at certificate management tasks for Linkerd.

## BASIC SKILL: Generate and inspect certificates with step(1)

Linkerd needs a trust anchor and issuer certificates, so it's important
to know how to create them. We'll use step(1) to make it less painful to
work with certificates.

When in doubt, use 'step --help'.

<!-- @wait_clear -->

## Generate a certificate with step

This looks complex, but it's actually a pretty simple thing. Here's the basic
`step` command for making a certificate:

```
step certificate create \
     --profile root-ca \
     --no-password --insecure
     cn.of.my.cert \
     ca.crt ca.key
```

<!-- @wait -->

- `--profile` says what kind of cert to make. The really useful ones are
  `root-ca` to generate a root CA cert and `intermediate-ca` to generate an
  intermediate CA cert.

- `--no-password --insecure` together say not to give the certificate a
  password, and we understand that that's insecure.

- `cn.of.my.cert` gives the CN of the cert's `Subject`.

- `ca.crt ca.key` specify the output files for the public certificate and its
  private key.

<!-- @wait -->

- For an intermediate CA cert, you'll also give `--ca` and `--ca-key` to tell
  `step` the certificate to sign the new cert with.

- You can also use `--not-after` to set the certificate's lifetime. Its value
  is either a duration or an RFC3339 time string.

<!-- @wait_clear -->

Here's a simple run to make a root CA cert:

```bash
#@immed
rm -f ca.crt ca.key
step certificate create \
     --profile root-ca \
     --no-password --insecure \
     cn.of.my.cert \
     ca.crt ca.key
```

The certificate is encoded, so we can't just read it:

```bash
head ca.crt
```

Instead, we'll use 'step certificate inspect'.

```bash
step certificate inspect ca.crt
```

<!-- @wait_clear -->

## DEVELOPMENT SETUP: Linkerd with manually-managed certificates

To put this to use, let's use `step` to create a self-signed trust anchor
cert, use that to create an identity issuer cert, and use both to install
Linkerd.

Note that Linkerd requires that the trust anchor and the identity issuer not
be the same certificate, and that the trust anchor sign the identity issuer.
Also note that we're focusing on a development setup here, where it's OK for
these to be manually rotated with long expiration times.

<!-- @slides_then_terminal -->

We call this a development setup because we're generating the trust anchor and
identity issuer by hand, without paying any particular attention to the fact
that the trust anchor private key needs to be kept _secret_ to be useful! In
production (or, really, even in staging), you should really be using a proper,
secured, off-cluster CA to generate the trust anchor.

A thing we're doing correctly here is that we're not storing the trust anchor
secret key in the cluster. Linkerd doesn't need the trust anchor's secret key
on the cluster, and you should never put it there.

<!-- @wait_clear -->

`step` arguments for our trust anchor:

- The Subject CN of the trust anchor must always be `root.linkerd.cluster.local`
- We'll use the `root-ca` profile.
- We'll use `--not-after` to make the trust anchor expire in ten years (~87600
  hours).
- We'll save the trust anchor halves in `trust-anchor.crt` and `trust-anchor.key`.

```bash
#@immed
rm -rf trust-anchor.crt trust-anchor.key

step certificate create \
     --profile root-ca --no-password --insecure \
     --not-after='87600h' \
     root.linkerd.cluster.local \
     trust-anchor.crt trust-anchor.key
```

<!-- @wait -->

We can inspect this to see that it looks much the same as our previous
test certificate, but check out the Validity section.

```bash
step certificate inspect trust-anchor.crt
```

<!-- @wait_clear -->

## DEVELOPMENT SETUP: Create an issuer cert signed by the trust anchor.

Once again, we're going to generate the identity issuer certificate by hand,
without thinking too hard about how to keep it safe. Note, too, that issuer
cert _does_ need to have both halves stored on the cluster, so we should be
thinking about rotating it pretty frequently (definitely more frequently than
the trust anchor!) and also note that it must be signed by the trust anchor.

<!-- @wait_clear -->

Here are the `step` arguments for our identity issuer:

- The Subject CN must be `identity.linkerd.cluster.local`
- We'll use the `intermediate-CA` profile, since this is not a self-signed
  certificate.
- We'll use `--ca` and `--ca-key` to tell `step` to use the trust anchor to
  sign the identity issuer.
- We'll use `--not-after` to make the identity issuer expire after 90 days
  (2160 hours).
- We'll save the identity issuer halves in `issuer.crt`` and `issuer.key`

```bash
#@immed
rm -rf identity.crt identity.key

step certificate create \
     --profile intermediate-ca --no-password --insecure \
     --ca trust-anchor.crt --ca-key trust-anchor.key \
     --not-after='2160h' \
     identity.linkerd.cluster.local \
     identity.crt identity.key
```

If we inspect this, the major differences are around the Issuer and the path
length constraint.

```bash
step certificate inspect identity.crt
```

<!-- @wait_clear -->

## DEVELOPMENT SETUP: Install Linkerd with our new certificates!

We'll install Linkerd using these certificates that we just generated, and
then not think about rotation for 90 days. 😂

But first! let's make sure that our cluster is alive and well, and that it can
support Linkerd.

```bash
kubectl get nodes
kubectl get ns | sort
linkerd check --pre
```

<!-- @wait_clear -->

So far so good. We'll install Linkerd with its CLI, starting with its CRDs.

```bash
linkerd install --crds | kubectl apply -f -
```

<!-- @wait_clear -->

Next, install Linkerd proper. Look carefully at the options here: we
explicitly tell Linkerd which certificates to use (so it won't create its
own), and we **do not** provide the private half of the trust anchor, because
Linkerd doesn't need it, and you don't really want to store it in the cluster.

```bash
linkerd install \
  --identity-issuance-lifetime="30m" \
  --identity-trust-anchors-file trust-anchor.crt \
  --identity-issuer-certificate-file identity.crt \
  --identity-issuer-key-file identity.key \
  | kubectl apply -f -
```

We'll use `linkerd check` again to make sure that all is well (this will check
all the certificates as part of its work).

```bash
linkerd check
```

<!-- @wait_clear -->

## OPERATIONAL SKILL: Manually rotating certificates

Next up: manually rotating certificates. Rotating certificates is an important
part of operating Linkerd: you need to rotate certificates before they expire,
or whenever you need or want to replace them for any other reason. We'll
demonstrate this skill by switching our certificates out for versions with
more sane expiration times.

The process differs depending on which certificate you rotate: the trust
anchor is the most annoying to rotate, the identity issuer isn't bad to
rotate, and the workload certificates should be handled automatically in all
cases.

<!-- @wait_clear -->

Start by checking the state of the proxies using 'linkerd check --proxy'.

Things you might see:

**This is a warning**: you may have time to fix it without downtime.

${BROWN}‼${COLOR_RESET} trust anchors are valid for at least 60 days
    Anchors expiring soon:
  * 266297593235225729893956725969676248553 root.linkerd.cluster.local will expire on 2022-08-24T02:38:20Z
    see https://linkerd.io/2.12/checks/#l5d-identity-trustAnchors-not-expiring-soon for hints

<!-- @wait -->

**THIS MEANS DOWNTIME**. You need to keep this from ever happening.

${RED}×${COLOR_RESET} trust anchors are within their validity period
    Invalid anchors:
  * 266297593235225729893956725969676248553 root.linkerd.cluster.local not valid anymore. Expired on 2022-08-24T02:38:20Z
    see https://linkerd.io/2.12/checks/#l5d-identity-trustAnchors-are-time-valid for hints

<!-- @wait -->

An expired identity issuer cert **still means downtime**, but it's easier to
fix than an expired trust anchor.

${BROWN}‼${COLOR_RESET} issuer cert is valid for at least 60 days
    issuer certificate will expire on 2022-08-24T02:30:32Z
    see https://linkerd.io/2.12/checks/#l5d-identity-issuer-cert-not-expiring-soon for hints

${RED}×${COLOR_RESET} issuer cert is within its validity period
    issuer certificate is not valid anymore. Expired on 2022-08-24T02:30:32Z
    see https://linkerd.io/2.12/checks/#l5d-identity-issuer-cert-is-time-valid for hints

**In short**: _don't let your certificates expire_. This is important enough
that we'll shortly be talking about automating rotation -- and, unfortunately,
expired certificates are **the** most common reason for Linkerd outages in the
real world.

<!-- @wait_clear -->

For manual rotation, the first thing you need is the new certificates to
switch to, so we'll start by using `step` to generate new certificates. We'll
give this set shorter expiry times -- shorter expirations make our environment
more secure and robust.

* Key compromises might happen more often than you think. Private keys need to
  be carefully managed, and they should be rotated as often as possible for
  your environment to avoid compromises. This is especially true with the
  issuer certificates, since their private keys typically live in the cluster.

* Also, in many environments you'll have to deal with certificates getting
  revoked. If your trust anchor gets revoked by the corporate security
  department, you'll want to be comfortable rotating quickly!

<!-- @wait_clear -->

We'll generate a new trust anchor cert with a validity of two months (~1440h)
and a new identity issuer with a validity of one week (~168h). This might turn
out to be too short in practice, but it's great for security -- there's no
right or wrong answer here, you make decisions about what's right for your
environment and work patterns.

(These `step` commands are exactly the same as before, we're just changing the
expiration times.)

```bash
#@immed
rm -f new-anchor.crt new-anchor.key

step certificate create \
     --profile root-ca --no-password --insecure \
     --not-after=1440h \
     root.linkerd.cluster.local new-anchor.crt new-anchor.key
```

This time, pay attention to the Validity section.

```bash
step certificate inspect new-anchor.crt
```
<!-- @wait_clear -->

Given the new trust anchor, generate the issuer certificate. Again, this is
the same as before, we're just changing the expiration time.

```bash
#@immed
rm -f new-identity.crt new-identity.key

step certificate create \
     --profile intermediate-ca --no-password --insecure \
     --ca new-anchor.crt --ca-key new-anchor.key \
     --not-after=168h \
     identity.linkerd.cluster.local new-identity.crt new-identity.key
```

Once again, check the Validity section.

```bash
step certificate inspect new-identity.crt
```

<!-- @wait_clear -->

Now that we have the new certificates, we can actually do the rotation. This
is a multi-step process, and **it requires some care to do it all without
downtime**. So keep a careful eye on your trust anchors and don't let them
expire!

<!-- @wait -->

To rotate the trust anchor, we start by _bundling_ the new trust anchor cert
with the old one. The bundle contains both anchors, to allow a clean
transition between them: we'll tell Linkerd to use this bundle rather than a
single trust anchor cert, and that will allow Linkerd to temporarily validate
identity issuers and workload certs using either trust anchor.

We'll start by reading the current trust anchor from the cluster, to be
completely certain that we have the correct certificate. This is using
`kubectl` to examine the `linkerd-identity-trust-roots` ConfigMap, and grab
the `ca-bundle.crt` element from its `data` element: that's where the trust
bundle lives.

```bash
kubectl -n linkerd get cm linkerd-identity-trust-roots \
        -o=jsonpath='{.data.ca-bundle\.crt}' \
    > original-trust-anchor.crt
```

We'll inspect this one to show that it's really a certificate, but you
know what certificates look like by now, so we won't do it after this. 🙂

```bash
step certificate inspect original-trust-anchor.crt
```

<!-- @wait_clear -->

Next, bundle the certificates together with `step certificate bundle`. The
command line here simply lists a bunch of input certificates, then ends with
the output filename: here, we're taking `original-trust-anchor.crt` and
`new-anchor.crt` and placing them into a bundle named `bundle.crt`.

```bash
#@immed
rm -f bundle.crt

step certificate bundle original-trust-anchor.crt new-anchor.crt bundle.crt
```

<!-- @wait_clear -->

Finally, we use `linkerd upgrade` to tell Linkerd to use the new trust anchor
bundle.

```bash
linkerd upgrade --identity-trust-anchors-file=bundle.crt | kubectl apply -f -
```

Various control plane elements are restarting here. We need to wait for
the restarts to finish.

```bash
watch 'kubectl get pods -n linkerd'
```

<!-- @clear -->

At this point, you'd need to restart your meshed workloads to make sure they
all pick up the new trust bundle. For example, if you have the Faces demo
installed, you could do

```
kubectl rollout restart -n faces deploy
kubectl rollout status -n faces deploy
```

to trigger a rolling restart and wait for it to complete.

<!-- @wait_clear -->

Once the restarts are done, run some checks.

```bash
linkerd check --proxy
```

<!-- @wait -->

After restarting all your deployments, all your Linkerd proxies will be using
the new trust bundle, and you'll continue with rotating the identity issuer.

<!-- @wait_clear -->

## OPERATIONAL SKILL: Manually rotating identity issuer certificates

**You must have a valid trust anchor** for this step to work, which is why we
demo'd rotating the trust anchor first! Specifically, you need

- A valid trust anchor cert in the trust anchor bundle that your proxies have
- A new identity issuer cert signed by that valid trust anchor cert

In our case, we just rotated the trust anchor, so point 1 is good, and right
before we did that we created a new identity issuer cert (the 1-week
certificate in `new-identity.crt` and `new-identity.key`), so point 2 is good
too.

Given that, all we actually have to do is run `linkerd upgrade` to tell the
proxies to use the new identity issuer cert.

```bash
linkerd upgrade \
        --identity-issuer-certificate-file new-identity.crt \
        --identity-issuer-key-file new-identity.key \
        | kubectl apply -f -
```

<!-- @wait_clear -->

You can see the new identity issuer cert being reloaded by watching the
Kubernetes event log. Here we'll repeatedly look for the `IssuerUpdated` event
(note that this may take a little bit to appear):

```bash
watch 'kubectl get events --field-selector reason=IssuerUpdated -n linkerd'
```

<!-- @clear -->

At this point you have a choice. You can restart your meshed workloads here to
make sure everything updates to the new identity issuer immediately, or you
can just wait for the next workload certificate rotation. Either is OK;
restarting meshed workloads by hand is definitely more deterministic.

<!-- @wait_clear -->

## OPERATIONAL SKILL: Cleaning up the trust anchor bundle after rotating is complete

Once the workloads are restarted, Linkerd isn't using the old trust anchor at
all, and we can remove it from the bundle entirely. We'll do this the easy
way, by just switching the "bundle" to be the single current trust anchor
certificate:

```bash
linkerd upgrade --identity-trust-anchors-file=new-anchor.crt | kubectl apply -f -
```

It's best to restart meshed workloads one more time here, to make certain that
no one with access to the old trust anchor can slip a certificate they've
signed with it past your Linkerd installation. But that's it for manually
rotating certificates!

<!-- @wait_clear -->

## OPERATIONAL SKILL: Manually rotating certificates

In total, you'll run `linkerd upgrade` three times when replacing both the
trust anchor and the issuer certificate:

1. Upgrade with the old and new trust anchors as a bundle -- if we don't
   do this, the workload certificates for older workloads will be rejected
   because they're still signed by the old trust anchor, so you'll have
   downtime.

2. Upgrade with the new issuer cert, signed by the new trust anchor. At
   this point, workloads will be able to get certificates signed by the
   new trust anchor.

3. Upgrade with just the new trust anchor, to clean up -- we don't need
   the old trust anchor anymore.

<!-- @wait_clear -->

## OPERATIONAL SKILL: Rotating expired certificates

**THIS IS NOT A ZERO-DOWNTIME OPERATION.** If your cluster has an expired
certificate, it's not running a configuration that makes sense, and you need
to replace the expired certificate(s) immediately.

<!-- @wait -->

If only your issuer certificate has expired, just rotate the certificate as if
it were still valid. Nothing special needs to happen here.

<!-- @wait -->

If your trust anchor certificate has expired, though, you'll need to rotate
the trust anchor and also the identity certificate! and there's no point in
bundling the old trust anchor cert, because it's invalid. Remember: you need
to do both.

<!-- @wait -->

Since this is an operation that's not guaranteed to be zero downtime, I'm
leaving it as homework 🙂. You'll find a guide in this repository (the
EXPIRED-CERTS.md file).

<!-- @wait_clear -->

## ALMOST-PRODUCTION SETUP: Using cert-manager to bootstrap and rotate the identity issuer

All this certificate management is a lot of work. It's easier to wrangle it
with a tool such as cert-manager, so let's demo that. (cert-manager is another
CNCF project -- you can find it at https://cert-manager.io/).

cert-manager can handle both bootstrapping identity and automagically rotating
certificates. In this workshop we'll demo the bootstrap step while showing the
setup for the rotation step, but we're not actually going to wait for the
certificate to rotate. That's another homework assignment. 🙂 (It's literally
just "wait until it's time for the certificate to rotate, then check to make
sure it did".)

<!-- @wait -->

**Please note**: this is the _almost_-production setup. We'll be using
cert-manager to bootstrap and rotate the identity issuer, but we'll still use
our `step`-generated self-signed trust anchor. There are two reasons for this:

1. In a real production setup, you should really be using some sort of
   external store to hold your trust anchor anyway. cert-manager has a lot of
   ways to support this, but fundamentally, it's the same setup as we're
   showing here: you just use a different type of Issuer for the identity
   issuer. We'll point this out as we get into configuration.

2. When you rotate the identity issuer, Linkerd knows how to do everything
   needed as soon as you change the TLS secret in the cluster. However, when
   you rotate the trust anchor, you **must** restart all the meshed workloads,
   and that's going to take a little custom setup for your specific setup.

<!-- @wait_clear -->

We'll start by uninstalling Linkerd, since we'll be installing it differently
than we did for the manual scenario.

```bash
linkerd uninstall | kubectl delete -f -
```

Next up, we'll use Helm to install cert-manager, straight from their
quickstart:

```bash
helm repo add jetstack https://charts.jetstack.io --force-update

helm upgrade -i -n cert-manager cert-manager \
     jetstack/cert-manager --set installCRDs=true --wait --create-namespace
```

<!-- @wait_clear -->

OK, it's time to configure cert-manager.

1. We'll use a cert-manager ClusterIssuer resource to tell cert-manager how to
   use our trust anchor certificate to issue certificates.

   **This is the bit that you'll need to change for the real world.** The
   ClusterIssuer we're going to set up just tells cert-manager to assume that
   it has a cert, with its secret key, in the cluster. To make that work, **we
   have to do what we said never to do**, and store the secret key of the
   trust anchor we generated with `step` in the cluster.

   In the real world, you'll need to use the correct kind of cert-manager
   Issuer or ClusterIssuer for your external CA store. And you won't put the
   trust anchor secret key in your cluster!

<!-- @wait -->

2. We'll use a cert-manager Certificate resource to tell cert-manager to
   actually create the identity issuer certificate, using the ClusterIssuer
   from step 1 so it's signed by our trust anchor. Remember that the identity
   issuer needs to be created in the `linkerd` namespace.

<!-- @wait_clear -->

So. First up, let's go ahead and do the thing you should never do: write our
trust anchor into a secret that cert-manager can see. We'll put this secret
into the `cert-manager` namespace, so at least Linkerd can't look at it. (In
fact, nothing but cert-manager should be able to see things in the
`cert-manager` namespace: check your RBAC!)

```bash
kubectl create secret tls linkerd-trust-anchor \
  --cert=trust-anchor.crt \
  --key=trust-anchor.key \
  --namespace=cert-manager
```

After that, we can create the ClusterIssuer that knows how to use that secret
to issue certificates:

```bash
bat manifests/cert-manager-ca-issuer.yaml
kubectl apply -f manifests/cert-manager-ca-issuer.yaml
```

<!-- @wait_clear -->

Creating the ClusterIssuer doesn't really do anything interesting -- we need
to go ahead and get the Certificate resource set up to have anything to see,
so let's go ahead and do that.

In order to do that, we'll need to create the `linkerd` namespace by hand,
since we haven't installed Linkerd yet.

```bash
kubectl create namespace linkerd
```

Once that's done, we can apply our Certificate resource.

```bash
bat manifests/cert-manager-identity-issuer.yaml

kubectl apply -f manifests/cert-manager-identity-issuer.yaml
```

<!-- @wait_clear -->

At this point, the Certificate resource should show that a certificate was
created.

```bash
kubectl get certificate -n linkerd linkerd-identity-issuer
```

<!-- @wait_clear -->

We can go take a closer look at the newly-created `linkerd-identity-issuer`
secret, too:

```bash
kubectl describe secret -n linkerd linkerd-identity-issuer
```

Just to prove that there's really a certificate in there, let's look at it
with 'step certificate inspect'. See the `tls.crt` key listed in the output?
Its value is a base64-encoded certificate (which, yes, means that it's
base64-encoded base64-encoded data -- oh well). If we unwrap one layer of
base64 encoding, we can feed that into 'step certificate inspect'.

```bash
kubectl get secret -n linkerd linkerd-identity-issuer \
                   -o jsonpath='{ .data.tls\.crt }' \
  | base64 -d \
  | step certificate inspect -
```

As a bonus, cert-manager is polite enough to put the public half of the trust
anchor into that Secret too -- that's the `ca.crt` key. We can look at that
too.

```bash
kubectl get secret -n linkerd linkerd-identity-issuer \
                   -o jsonpath='{ .data.ca\.crt }' \
  | base64 -d \
  | step certificate inspect -
```

<!-- @wait_clear -->

Now, finally, we can install Linkerd. We'll use Helm this time, so we'll start
with setting up repos and installing the Linkerd CRD chart:

```bash
helm repo add linkerd https://helm.linkerd.io/stable --force-update
helm install linkerd-crds -n linkerd --version 1.6.1 linkerd/linkerd-crds
```

<!-- @wait_clear -->

Next up, the control plane chart. When we install this one, we pass some very
specific arguments:

- `--set-file identityTrustAnchorsPEM=trust-anchor.crt` tells Linkerd the file
  that has our initial trust anchor bundle. Remember, Linkerd doesn't have
  access to the Secret in the `cert-manager` namespace, so it still needs
  this.

- `--set identity.issuer.scheme=kubernetes.io/tls` tells Linkerd that it
  should expect that someone else will supply a Kubernetes TLS Secret for the
  identity issuer, so Linkerd shouldn't try to create it.

<!-- @wait -->

```bash
helm install linkerd-control-plane -n linkerd \
  --set-file identityTrustAnchorsPEM=trust-anchor.crt \
  --set identity.issuer.scheme=kubernetes.io/tls \
  linkerd/linkerd-control-plane
```

Once that's done, let's make sure all is well:

```bash
linkerd check
```

<!-- @wait_clear -->

At this point, we have cert-manager handling rotating the identity issuer cert
for us, which will make things much easier going forward! We'll still need to
manually rotate the trust anchor, but that's easier too:

1. Create the new trust anchor certificate and bundle as shown above.

<!-- @wait -->

2. Update the trust anchor bundle with `helm upgrade` (this is the same as the
   `helm install`, but passing `bundle.crt`):

   ```
   helm upgrade linkerd-control-plane -n linkerd \
        --set-file identityTrustAnchorsPEM=bundle.crt \
        --set identity.issuer.scheme=kubernetes.io/tls \
        linkerd/linkerd-control-plane
   ```

<!-- @wait -->

3. Restart meshed workloads.

<!-- @wait -->

4. Update the `linkerd-trust-anchor` Secret in the `cert-manager` namespace,
   which will cause cert-manager to update your identity issuer for you!

<!-- @wait -->

5. Rerun `helm upgrade` with just the new trust anchor, and restart meshed
   workloads once more.

<!-- @wait_clear -->

One final note: Jetstack (now Venafi), the folks behind cert-manager, have
another tool called trust-manager which is capable of copying the trust
anchor's public key from the cert-manager namespace into the trust anchor
bundle ConfigMap that Linkerd uses. We didn't use that in this example because
it ends up being helpful to separate updating the trust anchor bundle and
updating the Secret itself, but it's worth a look. In general, once you have
cert-manager running, there's a lot more you can do, such as setting your
expiry periods programatically, or pulling in certificates from your corporate
PKI (maybe it's not cloud-native).

<!-- @wait_clear -->

When all is said and done, here's what you end up with. There's a trust anchor
Secret in the `cert-manager` namespace, which Linkerd can't see. **This is the
bit you'll need to change in production.**

```bash
kubectl describe secrets -n cert-manager linkerd-trust-anchor
```

In the `linkerd` namespace, we have a `linkerd-identity-trust-roots`
ConfigMap. This stores the trust anchor bundle, which is public keys only.
Linkerd needs to see this to validate mTLS certificates.

```bash
kubectl describe cm -n linkerd linkerd-identity-trust-roots
```

In the `linkerd` namespace, we also have the `linkerd-identity-issuer` Secret,
which holds the identity issuer cert public and private keys. Linkerd needs
this to manage workload identities.

```bash
kubectl describe secrets -n linkerd linkerd-identity-issuer
```

<!-- @wait_clear -->

## Certificate Management with Linkerd

So there's our whirlwind overview of Linkerd certificate management -- thanks!

https://github.com/BuoyantIO/service-mesh-academy is the source repo for this
workshop (this is in the `l5d-certificate-management` directory), and feedback
is always welcome via the Linkerd Slack at https://slack.linkerd.io/ --
thanks!

<!-- @wait -->
<!-- @show_slides -->

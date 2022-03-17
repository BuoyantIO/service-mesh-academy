# Certificate Management with Linkerd

Three different ways to manage your certificates with Linkerd. What we will be doing today:

* Generate and inspect a certificate with `step`.
* (Staging step) Generate a self-signed CA and an issuer.
* (Production step) Generate a self-signed CA, generate an issuer with cert-manager and install Linkerd.
* Rotate issuer and CA.
* Re-install Linkerd using CA managed by cert-manager.


### 1) Generating certificates with `step`
---

* When in doubt, `step --help`
* To create certificates:

```sh
# step certificate create <subject> <crt-output> <key-output> \
# [--profile=leaf/root-ca/self-signed/intermediate-ca] \ 
# [--no-password (don't use pass to encrypt private key)]
#
# Example:
$ step certificate create root.linkerd.cluster.local ca.crt ca.key --profile root-ca --no-password \
 --insecure #[--insecure required by --no-password]
```

* Certificate is encoded, we can't just read it. We can decode and inspect
  using `step certificate inspect <path>`


### 2) Generating a self-signed CA and an issuer
---

Linkerd's operational model requires a CA and an issuer. Generally, it is
recommended that these are different certificates to have better security. In a
staging environment, we might find that rotating trust anchors often is
painful; we'd expect to do it in a production environment, but production
environments have more stringent requirements.

If we are not concerned with security requirements in a staging environment, we
can set a longer expiration date for our certificates to avoid rotating often.

In `step`, we can provide an arbitrary expiration time with `--not-after`. It
takes either a duration (e.g seconds, minutes, hours) or a **time** (which must
be [RFC3339][rfc-time] compliant).

**TIP**: if it's hard to work with RFC3339 times, you can use `date
--rfc-3339=ns` on most unix systems. `man date` for more.

```sh
# First, generate trust anchors
# 
$ step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --no-password --insecure \
  --not-after="2060-03-17T16:00:00+00:00"
#
# Second, generate issuer, signed by our CA
# 
$ step certificate create identity.linkerd.cluster.local identity.crt identity.key \
  --profile intermediate-ca --no-password --insecure \
  --ca ca.crt --ca-key ca.key \
  --not-after="2050-03-17T16:00:00+00:00"
```

* Notice the additional flags: why are they needed?
* Notice the expiry dates: is it necessary for the trust anchor to expire after
the issuer?

* Install Linkerd and don't worry about certificate rotation until 2050 at the very least!

```sh
$ linkerd install \
 --identity-trust-anchors-file ca.crt \
 --identity-issuer-certificate-file identity.crt \
 --identity-issuer-key-file identity.key \
 |kubectl apply -f -

```

### 3) Generating self-signed certificates for the security conscious
---

**Why do we want shorter validty periods**: because they make our environment
more secure and robust.

* Key compromises might happen more often than you think. Private keys need
  some love and be rotated as often as possibly to avoid compromises (this is
  especially true with issuer CAs that typically live in the cluster).
* Revoking certificates might happen, best to get used to rotating your
  certificates.


We will generate a root CA with a validty of one year (or ~ 8760h) and an
issuer with a validty of one week (~ 168h). This might be a bit too short,
there's no right or wrong answer, the shorter, the better (i.e 1-2 months).

```sh
$ step certificate create root.linkerd.cluster.local ca.crt ca.key \
  --profile root-ca --no-password --insecure \
  --not-after=8700h

$ step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --ca ca.crt --ca-key ca.key \
  --no-password --insecure --not-after=170h
```

### 4) Rotating your certificates manually
---

With added security comes more headaches, unsurprisingly. 

* Once we have shorter validty periods, we need to rotate certificates. 
* The process may slightly differ depending on which layer you are planning to rotate.
* Trust anchors will be the most difficult to rotate, followed by intermediate
  (issuer) certificates, and leaf (proxy) certificates, which shouldn't be a
  concern 99% of the time.

You can understand the state of the control and data plane through `linkerd
check --proxy`.

**Rotating valid root certificates**: is a multi-step process and can be done
without any downtime. Monitor those certificates closely.

1. To rotate trust, generate a new CA certificate.
2. Bundle original trust with the new one.
3. Deploy the bundle by doing an upgrade.

```sh
$ step certificate create root.linkerd.cluster.local new-ca.crt new-ca.key \
  --profile root-ca --no-password --insecure

# We need to 'bundle' new CA with old CA 
# We can either take old CA from the filesystem or from linkerd-identity-trust-roots cm
# 
$ step certificate bundle new-ca.crt ca.crt bundle.crt

# Deploy!
$ linkerd upgrade --identity-trust-anchors-file=bundle.crt | kubectl apply -f -

# Restart your data plane workloads, e.g kubectl rollout restart deploy -n default
# finally, run some checks.
#
$ linkerd check --proxy
```

**Rotating valid issuer certificates**: fortunately, don't need a bundle here
provided root is ok.

```sh
$ step certificate create identity.linkerd.cluster.local new-issuer.crt new-issuer.key \
  --profile intermediate-ca --ca new-ca.crt --ca-key new-ca.key \
  --no-password --insecure

$ linkerd upgrade \
  --identity-issuer-certificate-file new-issuer.crt \
  --identity-issuer-key-file new-issuer.key \
  |kubectl apply -f - 


# Restart identity service so new identity issuer can be reloaded and used to sign
# new leaves
#
# Check events if you want to see confirmation of changes being reloaded
# Notice: identity service won't re-deploy since it reads the issuer from cm
$ kubectl get events --field-selector reason=IssuerUpdated -n linkerd

# Bonus round: removing old root from bundle
#
$ linkerd upgrade --identity-trust-anchors-file=new-ca.crt|kubectl apply -f -

```

In total, there are 3 upgrades when replacing both CA and issuer:

1. Upgrade with CA as bundle (if we don't do this, older pods will not work so
   we will have downtime. Won't be able to do certificate validation for
   existing pods since their certificates rely on old issuer and old CA)
2. Upgrade with new issuer (signed by new CA. Means certificate validation will
   now work well)
3. Upgrade with just new CA (we clean up after ourselves).


**Rotating expired certificates**: is not guaranteed to be a zero-downtime
operation. If your root certificate has expired, then you will need to replace
both **issuer** and **root**, otherwise certificate validation will fail. If
your issuer has expired, you can simply generate a new one (signed by CA) and
upgrade.

Since this is an operation that's not guaranteed to be zero downtime, I'm
leaving it as homework :). We do have a [guide][expired-guide] if you get
stuck.

### 4) Using cert-manager to automate identity bootstrapping

If you want to do everything automagically, you can opt to do all of these
operations **in-cluster** with the help of a PKI, such as
[cert-manager][cert-manager] (which we have found to work out great).

For this workshop, we won't cover [automatically rotating
certificates][auto-guide]. It will be trivial to do once we bootstrap identity,
and can be a great way to solidfy the knowledge outside of this session
(problem-based learning).

[cert-manager][cert-manager] currently distributes bootstrapped certificates as
Kubernetes `Secret` objects, and contains both the public key (certificate) and
the private key. This works well for our identity issuer, but not for our trust
roots. Since our trust roots will need to be mounted to different pods, we
don't want the private key to be accessible from within the pod. We will
introduce a second tool from the folks at JetStack called [trust][trust]. We
will discuss its usage shortly, for now, let's install both.

```sh
# Let's also uninstall Linkerd, we'll re install it without passing in any explicit params :)
$ linkerd uninstall|kubectl delete -f -
##
# Let's install cert-manager and trust 
#
$ helm repo add jetstack https://charts.jetstack.io --force-update
$ helm upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace
$ helm upgrade -i -n cert-manager cert-manager-trust jetstack/cert-manager-trust --wait
```

To install Linkerd, we need:

1. A self-signed CA to exist in a `ConfigMap` in "linkerd" namespace (`linkerd-identity-trust-roots`)
2. An issuer certificate to exist in a `Secret` in "linkerd" namespace.

We will create both of these using `cert-manager` and `trust` CRDs.

```sh
$ kubectl apply -f manifests/cert-manager-ca-issuer.yaml
# Notice the fields here and why we can't mount it to a pod:
$ kubectl get secret linkerd-identity-trust-roots -n cert-manager

$ kubectl apply -f manifests/cert-manager-identity-issuer.yaml
$ kubectl get secrets -n linkerd

$ kubectl apply -f manifests/ca-bundle.yaml
$ kubectl get cm -n linkerd

$ linkerd install \
  --identity-external-issuer \
  --set "identity.externalCA=true" \
  |kubectl apply -f -

```

You should end up with:

```
:; k get secrets -n cert-manager
NAME                                       TYPE                                  DATA   AGE
linkerd-identity-trust-roots               kubernetes.io/tls                     3      64m

:; k get secrets -n linkerd
NAME                                 TYPE                                  DATA   AGE
linkerd-identity-issuer              kubernetes.io/tls                     3      62m
linkerd-identity-token-7tndg         kubernetes.io/service-account-token   3      58m

:; k get cm -n linkerd
NAME                           DATA   AGE
kube-root-ca.crt               1      62m
linkerd-identity-trust-roots   1      62m
linkerd-config                 1      59m
```

And voila! You have automated certificate bootstrapping. You can do a lot more
things now, such as setting your expiry periods programatically, or pulling in
certificates from your corporate PKI (non-cloud-native). This approach gives
you more flexibility, albeit at slightly comprimising your security by keeping
your trust anchor private key in-cluster.

Happy Meshing!



### Links

* [RFC 3339][rfc-time]
* [Linkerd Getting Started Guide][start-guide]
* [Linkerd Generating Your Own CA][ca-guide]
* [Replacing Expired Certificates][expired-guide]
* [Automatically Replacing Expired Certificates][auto-guide]
* [Cert Manager docs][cert-manager]
* [Trust GitHub repo][trust]

[rfc-time]: https://datatracker.ietf.org/doc/html/rfc3339
[start-guide]: https://linkerd.io/2.11/getting-started/
[ca-guide]: https://linkerd.io/2.11/tasks/generate-certificates/
[expired-guide]: https://linkerd.io/2.11/tasks/replacing_expired_certificates/
[cert-manager]: https://cert-manager.io/docs/
[auto-guide]: https://linkerd.io/2.11/tasks/automatically-rotating-control-plane-tls-credentials/
[trust]: https://github.com/cert-manager/trust

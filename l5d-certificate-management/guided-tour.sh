#!/bin/env bash

##########
## Certificate Management with Linkerd

######## SETUP
# This uses demo-magic by Paxton Hare: https://github.com/paxtonhare/demo-magic/
# A copy of demo-magic.sh from there is included here; demo-magic-extras.sh is
# from Flynn (GitHub @kflynn).

# shellcheck source=demo-magic.sh
. demo-magic.sh
. demo-magic-extras.sh

DEMO_CMD_COLOR=$BLACK
DEMO_COMMENT_COLOR=$PURPLE
PROMPT_WAIT=false
TYPE_SPEED=60

# This show_* stuff allows using environment variable hooks to control what's
# shown when livecasting the demo. If you don't set the environment variables,
# the show_* commands will be noops.

run_hook () {
  # set -x
  hookname="DEMO_HOOK_${1}"
  hook=$(eval "echo \$$hookname")
  nowait="$2"

  if [ -n "$hook" ]; then $hook; else echo "no $hookname"; fi
  if [ -z "$nowait" ]; then wait; fi
  # set +x
}

show_terminal () { run_hook TERMINAL "$@"; }
show_browser  () { run_hook BROWSER "$@"; }
show_video    () { run_hook VIDEO "$@"; }
show_slides   () { run_hook SLIDES "$@"; }
slide_advance () { run_hook ADVANCE "$@"; }

# For livecasts we actually delete the cluster at the start, before the
# audience sees anything. This isn't necessarily the best way to do things
# outside of the livecast, so it's commented out for now.
# k3d cluster delete certs

show_slides --nowait
clear
show "Waiting..."
wait

clear
show_terminal --nowait

######## THE TOUR

# To run the tour, you'll need
#
# * a Kubernetes cluster and the `kubectl` command
#    * you can run `cycle-cluster.sh` to create a suitable `k3d` cluster
# * the `linkerd` CLI — https://linkerd.io/2.12/getting-started/
# * the `step` CLI — https://smallstep.com/docs/step-cli/installation
# * the `helm` CLI — https://helm.sh/docs/intro/quickstart/

clear

show "# BASIC SKILL: Generate and inspect certificates with step(1)"
show ""
show "# Linkerd needs a trust anchor and issuer certificates, so it's important"
show "# to know how to create them. We'll use step(1) to make it less painful to"
show "# work with certificates."
show
show "# When in doubt, use 'step --help'."
wait
clear

show "# Generate a certificate with step"

rm -f ca.crt ca.key
pe "step certificate create root.linkerd.cluster.local ca.crt ca.key --profile root-ca --no-password --insecure"

show ""
show "# The certificate is encoded, so we can't just read it."
pe "head ca.crt"

wait
show ""
show "# Instead, we use 'step certificate inspect'."

pe "step certificate inspect ca.crt"

wait
clear

show "# STAGING SETUP: Create a self-signed trust anchor"
show ""
show "# Linkerd needs a trust anchor and an issuer, which should be different."
show "# The trust anchor must sign the issuer certificate."
show ""
show "# In staging, it's OK for these to be manually rotated with long expiration"
show "# times. And in many scenarios - including staging - it can be fine for the"
show "# trust anchor to sign itself (a 'self-signed' certificate)."

wait

show ""
show "# Step arguments for a self-signed CA:"
show "#   root.linkerd.cluster.local: name for the Subject"
show "#   trust-anchor.crt and trust-anchor.key: where to save the cert"
show "#   --profile root-ca: self-signed certificate for use as a CA root"
show "#   --no-password --insecure: don't require a password to use the cert"
show "#   --not-after: expiration time, either a duration or an RFC3339 time string"
show ""

pi             "$ step certificate create root.linkerd.cluster.local trust-anchor.crt trust-anchor.key \\\\"
pi             "       --profile root-ca --no-password --insecure \\\\"
DEMO_PROMPT= p "       --not-after='2060-03-17T16:00:00+00:00'"

rm -rf trust-anchor.crt trust-anchor.key

step certificate create root.linkerd.cluster.local trust-anchor.crt trust-anchor.key \
     --profile root-ca --no-password --insecure \
     --not-after='2060-03-17T16:00:00+00:00'

show ""
show "# We can inspect this to see that it looks much the same as our previous"
show "# test certificate, but check out the Validity section."
pe "step certificate inspect trust-anchor.crt"
wait

clear

show "# STAGING SETUP: Create an issuer cert signed by the trust anchor."
show ""
show "# Again, in staging, it's OK for the issuer cert to be manually rotated"
show "# with a long expiration times (though less than the trust anchor!). It"
show "# cannot be self-signed though."
wait

show ""
show "# Step arguments for an issuer certificate:"
show "#   identity.linkerd.cluster.local: name for the Subject"
show "#   issuer.crt and issuer.key: where to save the cert"
show "#   --profile intermediate-ca: this cert is signed by another, and will be used to sign more!"
show "#   --no-password --insecure: don't require a password to use the cert"
show "#   --ca trust-anchor.crt: use this certificate to sign the new cert"
show "#   --ca-key trust-anchor.key: private key for --ca certificate"
show "#   --not-after: expiration time, either a duration or an RFC3339 time string"
show ""

pi             "$ step certificate create identity.linkerd.cluster.local identity.crt identity.key \\\\"
pi             "       --profile intermediate-ca --no-password --insecure \\\\"
pi             "       --ca trust-anchor.crt --ca-key trust-anchor.key \\\\"
DEMO_PROMPT= p "       --not-after='2050-03-17T16:00:00+00:00'"

rm -rf identity.crt identity.key

step certificate create identity.linkerd.cluster.local identity.crt identity.key \
  --profile intermediate-ca --no-password --insecure \
  --ca trust-anchor.crt --ca-key trust-anchor.key \
  --not-after="2050-03-17T16:00:00+00:00"

show ""
show "# If we inspect this, the major differences are around the Issuer and the"
show "# path length constraint."
pe "step certificate inspect identity.crt"
wait

clear

show "# STAGING SETUP: Install Linkerd with our new certificates! and don't"
show "# think about rotation until... 2050. 😂"
show ""
show "# First, we need a cluster."

# Again, for the livecast we create the cluster every time. It's commented
# out here because you might want to keep the cluster around.
# show ""
# pi             "$ k3d cluster create certs \\\\"
# pi             "      -p "80:80@loadbalancer" -p "443:443@loadbalancer" \\\\"
# DEMO_PROMPT= p "      --k3s-arg '--no-deploy=traefik@server:*;agents:*'"

# k3d cluster create certs \
#     -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
#     --k3s-arg '--no-deploy=traefik@server:*;agents:*'

# pe "kubectl ns default"
# wait

# clear
# show "# OK, let's make sure all is well."

pei "kubectl get nodes"
pei "kubectl get ns | sort"
wait

show ""
show "# We also need to know that our cluster can support Linkerd."
pe "linkerd check --pre"
echo
echo
wait

clear
show "# We'll install Linkerd with its CLI, starting with its CRDs."
pe "linkerd install --crds | kubectl apply -f -"
wait

show ""
show "# Next, install Linkerd proper. Look carefully at the options here:"
show "# we DO NOT provide the private half of the trust anchor. This is"
show "# because, in this manual world, it's ONLY used to verify identity."
show ""

pi             "$ linkerd install \\\\"
pi             "          --identity-trust-anchors-file trust-anchor.crt \\\\"
pi             "          --identity-issuer-certificate-file identity.crt \\\\"
pi             "          --identity-issuer-key-file identity.key \\\\"
DEMO_PROMPT= p "          | kubectl apply -f -"

linkerd install \
  --identity-trust-anchors-file trust-anchor.crt \
  --identity-issuer-certificate-file identity.crt \
  --identity-issuer-key-file identity.key \
  | kubectl apply -f -

show ""
show "# Use 'linkerd check' to make sure that all is well (this will check"
show "# all the certificates as part of its work)."

pe "linkerd check"
echo
echo
wait

clear

show "# BETTER SECURITY: Really, 2050 is just too long. Let's make this more"
show "# realistic by generating new certificates with shorter expiration times."
show ""
show "# Remember: shorter expirations make our environment more secure and robust."
show ""
show "# * Key compromises might happen more often than you think. Private keys need"
show "#   some love and be rotated as often as possibly to avoid compromises. This is"
show "#   especially true with the issuer certificates, since their private keys"
show "#   typically live in the cluster."
show "# * Revoking certificates might happen, best to get used to rotating your"
show "#   certificates."
show ""
wait
show "# We will generate a root CA with a validity of two months (or ~ 1440h) and an"
show "# issuer with a validity of one week (~ 168h). This might turn out to be too"
show "# short in practice, but it's great for security -- there's no right or wrong"
show "# answer here, you make decisions about what's right for your environment and"
show "# work patterns."
show ""

pi             "$ step certificate create root.linkerd.cluster.local new-anchor.crt new-anchor.key \\\\"
pi             "       --profile root-ca --no-password --insecure \\\\"
DEMO_PROMPT= p "       --not-after=1440h"

rm -f new-anchor.crt new-anchor.key
step certificate create root.linkerd.cluster.local new-anchor.crt new-anchor.key \
     --profile root-ca --no-password --insecure \
     --not-after=1440h

show ""
show "# This time, pay attention to the Validity section."
pe "step certificate inspect new-anchor.crt"
wait

clear
show "# Given the new trust anchor, generate the issuer certificate."
show ""
pi             "$ step certificate create identity.linkerd.cluster.local new-identity.crt new-identity.key \\\\"
pi             "       --profile intermediate-ca --no-password --insecure \\\\"
pi             "       --ca new-anchor.crt --ca-key new-anchor.key \\\\"
DEMO_PROMPT= p "       --not-after=168h"

rm -f new-identity.crt new-identity.key
step certificate create identity.linkerd.cluster.local new-identity.crt new-identity.key \
     --profile intermediate-ca --no-password --insecure \
     --ca new-anchor.crt --ca-key new-anchor.key \
     --not-after=168h

show ""
show "# Again, look at the Validity section."
pe "step certificate inspect new-identity.crt"
wait

clear

show "# OPERATIONAL SKILL: Manually rotating certificates"
show ""
show "# With added security comes more headaches, unsurprisingly -- namely, we"
show "# need to rotate the certificates before they expire, or whenever we need"
show "# to replace them (as we do now, to switch to our more-secure certificates)."
show "#"
show "# * The process differs depending on which certificate you rotate:"
show "#   Trust anchors will be the most difficult to rotate, followed by intermediate"
show "#   (issuer) certificates, and finally by leaf (proxy) certificates, which should"
show "#   be automatic in all cases."
wait

show ""
show "# Start by checking the state of proxies through 'linkerd check --proxy'."
show "# "
show "# Things you might see:"
show ""
show "# This is a warning: you may have time to fix it without downtime."
show "${BROWN}‼${COLOR_RESET} trust anchors are valid for at least 60 days"
show "    Anchors expiring soon:"
show "  * 266297593235225729893956725969676248553 root.linkerd.cluster.local will expire on 2022-08-24T02:38:20Z"
show "    see https://linkerd.io/2.12/checks/#l5d-identity-trustAnchors-not-expiring-soon for hints"
wait
show ""
show "# THIS MEANS DOWNTIME. You need to keep this from ever happening."
show "${RED}×${COLOR_RESET} trust anchors are within their validity period"
show "    Invalid anchors:"
show "  * 266297593235225729893956725969676248553 root.linkerd.cluster.local not valid anymore. Expired on 2022-08-24T02:38:20Z"
show "    see https://linkerd.io/2.12/checks/#l5d-identity-trustAnchors-are-time-valid for hints"
wait
show ""
show "# An expired issuer cert still means downtime, but it's easier to"
show "# fix than an expired trust anchor."
show ""
show "${BROWN}‼${COLOR_RESET} issuer cert is valid for at least 60 days"
show "    issuer certificate will expire on 2022-08-24T02:30:32Z"
show "    see https://linkerd.io/2.12/checks/#l5d-identity-issuer-cert-not-expiring-soon for hints"
show ""
show "${RED}×${COLOR_RESET} issuer cert is within its validity period"
show "    issuer certificate is not valid anymore. Expired on 2022-08-24T02:30:32Z"
show "    see https://linkerd.io/2.12/checks/#l5d-identity-issuer-cert-is-time-valid for hints"

wait
show ""
pe "linkerd check --proxy"
echo
echo
wait

clear
show "# OPERATIONAL SKILL: Manually rotating trust anchor certificate"
show ""
show "# Manually rotating valid root certificates is a multi-step process, and"
show "# it requires some care to do it all without downtime. Keep a careful eye"
show "# on your trust anchors!"
wait

show ""
show "# To rotate the trust anchor, we start by generating a new trust anchor."
show "# Remember: rotating means replacing, when it comes to certificates."

pi             "$ step certificate create root.linkerd.cluster.local new-anchor.crt new-anchor.key \\\\"
DEMO_PROMPT= p "       --profile root-ca --no-password --insecure"

show ""
show "# We're not actually going to run that: instead we'll use the 60-day trust"
show "# anchor that we generated a few minutes ago."

show ""
show "# Next, we need to bundle the new trust anchor cert with the old one. The"
show "# bundle contains both anchors, to allow to make a clean transition between"
show "# them."

show ""
show "# We'll start by reading the current trust anchor from the cluster, to be"
show "# completely certain that we have the correct certificate."
show ""
pi             "$ kubectl -n linkerd get cm linkerd-identity-trust-roots -o=jsonpath='{.data.ca-bundle\\\\.crt}' \\\\"
DEMO_PROMPT= p "          > original-trust-anchor.crt"

kubectl -n linkerd get cm linkerd-identity-trust-roots -o=jsonpath='{.data.ca-bundle\.crt}' \
        > original-trust-anchor.crt

show ""
show "# We'll inspect this one to show that it's really a certificate, but you"
show "# know what certificates look like by now, so we won't do it after this. 🙂"
pe "step certificate inspect original-trust-anchor.crt"

wait
clear
show ""
show "# Next, bundle the certificates together..."
rm -f bundle.crt
pe "step certificate bundle original-trust-anchor.crt new-anchor.crt bundle.crt"

show ""
show "# ...and deploy the bundle using 'linkerd upgrade'."
pe "linkerd upgrade --identity-trust-anchors-file=bundle.crt | kubectl apply -f -"
show ""
show "# Various control plane elements are restarting here. We need to wait for"
show "# the restarts to finish."
pe "watch 'kubectl get pods -n linkerd'"

clear
show "# This is where you'd restart your meshed workloads, for example:"
show "$ kubectl rollout restart -n emojivoto deploy"
wait
show ""
show "# Once the restarts are done, run some checks."

pe "linkerd check --proxy"
echo
echo
wait

clear
show "# OPERATIONAL SKILL: Manually rotating identity certificates"
show ""
show "# This REQUIRES A VALID TRUST ANCHOR but it's easy. Just generate the"
show "# new identity certificate signed by the trust anchor."
show ""
pi             "$ step certificate create identity.linkerd.cluster.local new-identity.crt new-identity.key \\\\"
pi             "       --profile intermediate-ca --ca new-anchor.crt --ca-key new-anchor.key \\\\"
DEMO_PROMPT= p "       --no-password --insecure"

show ""
show "# We're not actually going to run that: instead we'll use the 1-week"
show "# identity issuer that we generated a few minutes ago."

show ""
show "# Once the certificate is created, deploy it!"
show ""

pi             "linkerd upgrade \\\\"
pi             "        --identity-issuer-certificate-file new-identity.crt \\\\"
pi             "        --identity-issuer-key-file new-identity.key \\\\"
DEMO_PROMPT= p "        | kubectl apply -f -"

linkerd upgrade \
        --identity-issuer-certificate-file new-identity.crt \
        --identity-issuer-key-file new-identity.key \
        | kubectl apply -f - 

wait
clear

show "# Check events if you want to see confirmation of changes being reloaded."
show "# (This may take a little bit to appear.)"
pe "watch 'kubectl get events --field-selector reason=IssuerUpdated -n linkerd'"

show ""
show "# Again, you'd need to restart your meshed workloads here."
wait

show ""
show "# And, finally, we can remove the old root from the bundle entirely."
pe "linkerd upgrade --identity-trust-anchors-file=new-anchor.crt | kubectl apply -f -"
show ""
pe "linkerd check --proxy"
echo
echo
wait

clear
show "# In total, there are 3 upgrades when replacing both the trust anchor and"
show "# the issuer certificate:"
show "#"
show "# 1. Upgrade with the old and new trust anchors as a bundle -- if we don't"
show "#    do this, the workload certificates for older workloads will be rejected"
show "#    because they're still signed by the old trust anchor, so you'll have"
show "#    downtime."
show "#"
show "# 2. Upgrade with the new issuer cert, signed by the new trust anchor. At"
show "#    this point, workloads will be able to get certificates signed by the"
show "#    new trust anchor."
show "#"
show "# 3. Upgrade with just the new trust anchor, to clean up -- we don't need"
show "#    the old trust anchor anymore."
wait

clear
show ""
show "# OPERATIONAL SKILL: Rotating expired certificates"
show ""
show "# THIS IS NOT A ZERO-DOWNTIME OPERATION. If your cluster has an expired certificate,"
show "# it's not running a configuration that makes sense, and you need to replace the"
show "# expired certificate(s) immediately."
wait
show ""
show "# If only your issuer certificate has expired, just rotate the certificate as if"
show "# it were still valid. Nothing special needs to happen here."
wait
show ""
show "# If your trust anchor certificate has expired, though, you'll need to rotate"
show "# the trust anchor and also the identity certificate! and there's no point in"
show "# bundling the old trust anchor cert, because it's invalid. Remember: you need"
show "# to do both."
wait
show ""
show "# Since this is an operation that's not guaranteed to be zero downtime, I'm"
show "# leaving it as homework 🙂. You'll find a guide in this repository."

wait
clear

show "# PRODUCTION SETUP: Using cert-manager to automate identity bootstrapping"
show ""
show "# All this certificate management is a lot of work. It's easier to wrangle it"
show "# with a PKI such as cert-manager, so let's demo that."
show ""
show "# A good PKI can handle both bootstrapping identity and automagically"
show "# rotating certificates, but in this workshop we'll only show the bootstrap"
show "# step -- the automatic rotation tends to be easy once bootstrapped (and"
show "# it's a great way to make sure you understand things)."
wait

show ""
show "# We'll start by uninstalling Linkerd, since we'll be installing it"
show "# differently than we did for the manual scenario!"
show ""
pe "linkerd uninstall | kubectl delete -f -"

show ""
show "# OK, continue by installing cert-manager. We'll use Helm for this."
pe "helm repo add jetstack https://charts.jetstack.io --force-update"
pe "helm upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace"

show ""
show "# Also install the JetStack 'trust' tool."
pe "helm upgrade -i -n cert-manager cert-manager-trust jetstack/cert-manager-trust --wait"
wait

clear
show "# Next up, before we reinstall Linkerd we need to set up a few things using"
show "# cert-manager:"
show "#"
show "# 1. We'll use cert-manager to create a self-signed root CA. (This is mostly"
show "#    for workshop purposes: in many real-world scenarios, you'd already have"
show "#    some established corporate CA and you'd use that instead.)"
wait
show "#"
show "# 2. We'll use that root CA to create and sign a trust anchor certificate,"
show "#    signed by the root CA. This will stored in the cert-manager namespace,"
show "#    in the linkerd-identity-trust-roots Secret."
wait
show "#"
show "# (It's important to note that Linkerd will not have access to anything in"
show "#  the cert-manager namespace. In fact, nothing but cert-manager should be"
show "#  able to access the cert-manager namespace -- set your RBAC accordingly!)"
wait
show "#"
show "# 3. We'll use that trust anchor to set up _another_ CA, which we'll use"
show "#    to sign our issuer certificate. The issuer certificate must be stored"
show "#    in the linkerd namespace."
wait
show "#"
show "# 4. Finally, we'll use the cert-manager trust extension to copy the public"
show "#    key for our trust anchor from the cert-manager namespace to the linkerd"
show "#    namespace, so that Linkerd has access to it."
wait
show "#"
show "# Worth remembering: our trust anchor is _not_ self-signed any more - which"
show "# means that cert-manager can handle rotating it! - and its private key is"
show "# _never_ stored anywhere that Linkerd can see it."

wait
clear
pi "# Here are the CRDs to set up the trust anchor:"
wait
bat manifests/cert-manager-ca-issuer.yaml

clear
show "# Applying them tells cert-manager to create our trust anchor."
show ""
pe "kubectl apply -f manifests/cert-manager-ca-issuer.yaml"
wait

show ""
show "# Let's look at the trust anchor's Secret. Don't mount this in a pod: it's"
show "# not a good idea."

pe "kubectl describe secret -n cert-manager linkerd-identity-trust-roots"
echo
echo
wait

clear
show "# Just to prove that there's really a certificate in there, let's look"
show "# at it with 'step certificate inspect'. See the 'ca.crt' key listed"
show "# in the output? Its value is a base64-encoded certificate (which, yes,"
show "# means that it's base64-encoded base64-encoded data -- oh well). If"
show "# we unwrap one layer of base64 encoding, we can feed that into 'step"
show "# certificate inspect'."

pi             "kubectl get secret -n cert-manager linkerd-identity-trust-roots \\\\"
pi             "                   -o jsonpath='{ .data.ca\\\\.crt }' \\\\"
pi             "  | base64 -d \\\\"
DEMO_PROMPT= p "  | step certificate inspect -"

kubectl get secret -n cert-manager linkerd-identity-trust-roots \
                   -o jsonpath='{ .data.ca\.crt }' \
  | base64 -d \
  | step certificate inspect -

wait

clear
show "# Onward. Set up the identity issuer as well and look at what we get with it."
show ""
pi "# Again, here are the raw CRDs:"
wait
bat manifests/cert-manager-identity-issuer.yaml

clear
show "# We'll apply those and then look at the resulting Secret."
show ""
pe "kubectl apply -f manifests/cert-manager-identity-issuer.yaml"
show ""
pe "kubectl get secrets -n linkerd"
echo
echo
wait

clear
show "# Almost done. Finally, we'll use the Trust extension to copy the trust"
show "# anchor's public key into the trust anchor bundle ConfigMap that Linkerd"
show "# uses."
show ""
show "# Last time for the CRDs:"
bat manifests/ca-bundle.yaml
show ""
pe "kubectl apply -f manifests/ca-bundle.yaml"
show ""
show "# Let's make sure that the ConfigMap is present..."
pe "kubectl get cm -n linkerd"
echo
echo
wait

clear
show "# Finally, tell Linkerd to use cert-manager for certificates."
show ""
pe "linkerd install --crds | kubectl apply -f -"

show ""
pi             "$ linkerd install \\\\"
pi             "  --identity-external-issuer \\\\"
pi             "  --set identity.externalCA=true \\\\"
DEMO_PROMPT= p "  | kubectl apply -f -"

linkerd install \
  --identity-external-issuer \
  --set identity.externalCA=true \
  | kubectl apply -f -
wait

show ""
show "# Check to see if everything still looks good."
pe "linkerd check --proxy"
echo
echo
wait

clear
show "# When all is said and done, here's what you'll end up with."

pe "kubectl get secrets -n cert-manager"
wait
# NAME                                       TYPE                                  DATA   AGE
# linkerd-identity-trust-roots               kubernetes.io/tls                     3      64m

show ""
pe "kubectl get secrets -n linkerd"
wait
# NAME                                 TYPE                                  DATA   AGE
# linkerd-identity-issuer              kubernetes.io/tls                     3      62m
# linkerd-identity-token-7tndg         kubernetes.io/service-account-token   3      58m

show ""
pe "kubectl get cm -n linkerd"
wait
# NAME                           DATA   AGE
# kube-root-ca.crt               1      62m
# linkerd-identity-trust-roots   1      62m
# linkerd-config                 1      59m

clear
show "# And there you have it -- automated certificate bootstrapping. You can do"
show "# a lot more things now, such as setting your expiry periods programatically,"
show "# or pulling in certificates from your corporate PKI (maybe it's not"
show "# cloud-native). This approach gives you more flexibility, although at the"
show "# cost of at slightly lessening your security by keeping your trust anchor"
show "# private key in-cluster."
wait

show_slides --nowait

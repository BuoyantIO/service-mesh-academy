# Integrating enterprise PKI with Kubernetes

Integrating existing enterprise PKI with Kubernetes can be daunting —
there are many moving parts and many pitfalls in achieving trust across boundaries!

From terminating TLS at the ingress level, to securing communication between workloads;
the interplay between Kubernetes components such as cert-manager and linkerd with enterprise PKI quickly becomes non-trivial.

There is an ongoing effort by companies such as Jetstack and Buoyant to make this easier and
here we will demonstrate how to combine enterprise PKI software such as Venafi TPP with cert-manager and linkerd;
to manage identity, while providing mTLS between your workloads, greatly reducing the burden on platform teams.

## Setting the Scene

Kubernetes and Cloud Native technologies such as cert-manager and linkerd are increasingly adopted by enterprises.
Often these enterprises will have established PKI policies and PKI teams using tried-and-trusted PKI software.
And there is friction where these two worlds meet:
* Platform teams managing the Kubernetes infrastructure are challenged with enforcing  enterprise wide PKI policies in the clusters that they own.
* PKI teams face the challenge of gaining visibility of numerous, automated and often short lived TLS artifacts which are created by the teams who deploy software on Kubernetes.

So the challenge is to identify the main points of friction,
figure out how the systems and software can already be integrated,
and figure out how the APIs and integration points can be improved to achieve smoother integration.

In this tutorial we will show you how to configure linkerd so that it creates mTLS certificates which are chained to intermediate CA certificates managed by cert-manager and which are signed by and visible in Venafi TPP; an enterprise PKI software suite.

Let's quickly introduce the four pieces of software:

### Venafi Trust Protection Platform (TPP)

[Venafi TPP][tpp] comprises a Web UI, a REST API and a pluggable backend which combine to give you the visibility, intelligence and automation to protect machine identities throughout your organization. It can be extended through an ecosystem of hundreds of out-of-the-box integrated third-party applications and certificate authorities (CAs).
PKI teams use Venafi TPP to discover and provision certificates and apply and enforce security best practices for certificates.

[tpp]: https://www.venafi.com/platform/trust-protection-platform

### cert-manager

[cert-manager] is a powerful and extensible X.509 certificate controller for Kubernetes and OpenShift workloads.
It will obtain signed certificates from a variety of Issuers; both popular public Issuers such as Let's Encrypt as well as private Issuers.
Thereafter it ensures that the certificates are valid and up-to-date, and will attempt to renew certificates at a configured time before expiry.

[cert-manager]: https://cert-manager.io/

### linkerd

[linkerd] is a service mesh.
It transparently adds mutual TLS to any on-cluster TCP communication, with no configuration.
And it allows you to track success rates, latencies, and request volumes for every meshed workload, without changes or config.

[linkerd]: https://linkerd.io/

### trust

[trust] is an operator for distributing trust bundles across a Kubernetes cluster. trust is designed to complement cert-manager by enabling services to trust X.509 certificates signed by Issuers, as well as external CAs which may not be known to cert-manager at all.

[trust]: https://cert-manager.io/docs/projects/trust/

## Integration Points

Linkerd needs a trust anchor certificate and an issuer certificate with its corresponding key.
The linkerd installer provides a hook to allow these certificates to be externally managed; by cert-manager for example.
See [Generating your own mTLS root certificates](https://linkerd.io/2.11/tasks/generate-certificates/)
and [Automatically Rotating Control Plane TLS Credentials](https://linkerd.io/2.11/tasks/automatically-rotating-control-plane-tls-credentials/).

cert-manager integrates with Venafi TPP and with Hashicorp Vault, and with a long list of other PKI systems.
So here we configure cert-manager to automatically sign the linkerd trust anchor certificate using Venafi TPP.

trust is configured to distribute the public certificate of the linkerd trust anchor to ConfigMap objects in every Kubernetes namespace,
where it can be consumed by the linkerd proxy to verify the mTLS certificates of peers to which it connects or which connect to it.

The diagram below illustrates these integrations.
* Circle = TLS CA certificate
* Rectangle = Kubernetes custom resource
* Rhombus = linkerd component

[![](https://mermaid.ink/img/pako:eNqVVU2P2jAQ_SuWTyCtKy3HSIu0ZXtAbSXURT3l4sYTsJo4ke1IRcB_r-MP1vGahc3JzLx5M29mbI646hjgAu8k7fdo-1IKZL7N9_Vstnou0G8QtOZou9nM56VwTjX8ceiqGZQGGexTH0hNWirobgSg6FsrNYAcM6xcvDMUNkkOupUG9qvrtEojGi7-gmREjwhCRbXvZELxCpUEHVFYWSGQMxCa64NnkCNinjCsjBJe84pqsDTPNs0sMt9VSIT_4dBrn9ypyRNeCuQWFHGCYNnG2xKmqb8OgjUQ9cAZbrRhynE7sSfLtT8vOD8JLzRJnzAcfViBQtx5ir9URft-6rGz6ETNdz9pH69WsKXTzHXDlgS0fgyFkF52_w7k8ZzHLRLcIsGZnuY77I-XW4menpYnxXdCnd6ttgOl1vcR2WnEwVlAzGOlfzpiEXTYcETI8mQ7fFWKDbqBc8j8HUXkC1m-vTfupzncjDkp3Um4L19eepQ5GoW15rXexRjq-nCOV9bA5k5fgqnazLWY0n2gNXH5AU6NHvm2PFf9CxQSu-3HD7gF2VLOzF_VcfSUWO-hhRIX5sigpkOjS1yKs4EOPTNt_Ma40YWLmjYKHjAddPd6EBUuzDJBAL1wat6J1qPO_wEexlvi)](https://mermaid.live/edit#pako:eNqVVU2P2jAQ_SuWTyCtKy3HSIu0ZXtAbSXURT3l4sYTsJo4ke1IRcB_r-MP1vGahc3JzLx5M29mbI646hjgAu8k7fdo-1IKZL7N9_Vstnou0G8QtOZou9nM56VwTjX8ceiqGZQGGexTH0hNWirobgSg6FsrNYAcM6xcvDMUNkkOupUG9qvrtEojGi7-gmREjwhCRbXvZELxCpUEHVFYWSGQMxCa64NnkCNinjCsjBJe84pqsDTPNs0sMt9VSIT_4dBrn9ypyRNeCuQWFHGCYNnG2xKmqb8OgjUQ9cAZbrRhynE7sSfLtT8vOD8JLzRJnzAcfViBQtx5ir9URft-6rGz6ETNdz9pH69WsKXTzHXDlgS0fgyFkF52_w7k8ZzHLRLcIsGZnuY77I-XW4menpYnxXdCnd6ttgOl1vcR2WnEwVlAzGOlfzpiEXTYcETI8mQ7fFWKDbqBc8j8HUXkC1m-vTfupzncjDkp3Um4L19eepQ5GoW15rXexRjq-nCOV9bA5k5fgqnazLWY0n2gNXH5AU6NHvm2PFf9CxQSu-3HD7gF2VLOzF_VcfSUWO-hhRIX5sigpkOjS1yKs4EOPTNt_Ma40YWLmjYKHjAddPd6EBUuzDJBAL1wat6J1qPO_wEexlvi)

We will set this up step by step below.

## Steps

### Prerequisites

Please install the following tools before continuing:
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/),
[kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl),
[helm](https://helm.sh/docs/intro/install/),
[cmctl](https://cert-manager.io/docs/usage/cmctl/#installation),
[linkerd](https://linkerd.io/2.11/getting-started/#step-1-install-the-cli),
`openssl` (optional).


### Prepare a test cluster

kind is a tool for running local Kubernetes clusters using Docker.
Follow the [Kind: Quick Start Documentation](https://kind.sigs.k8s.io/docs/user/quick-start/) to install kind on your computer,
and check that it is executable, as follows:

```terminal
$ kind version
kind v0.14.0 go1.18.2 linux/amd64
```

Then [Create a cluster](https://kind.sigs.k8s.io/docs/user/quick-start/#creating-a-cluster) as follows:

```shell
kind create cluster
```

You should see a progress log. E.g.:

```terminal
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.24.0) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Thanks for using kind! 😊
```

### Install cert-manager

Next [install cert-manager using helm](https://cert-manager.io/docs/installation/helm/), as follows:

```shell
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --version v1.8.0
```


Check that the cert-manager API is ready:

```shell
cmctl version
cmctl check api
```

### Create the linkerd-identity-trust-roots CA certificate

This is the first of two intermediate CA certificates used by linkerd.
This is the certificate that we want to be signed by Venafi TPP,
so in this step you will set up a [Venafi TPP ClusterIssuer](https://cert-manager.io/docs/configuration/venafi/).

Start by creating a Secret containing the Venafi TPP credentials: username and password.
This Secret MUST be in the cert-manager namespace because it will be used by a *Cluster*Issuer.

```shell
kubectl create secret generic \
       tpp-secret \
       --namespace=cert-manager \
       --from-literal=username=${TPP_USERNAME} \
       --from-literal=password=${TPP_PASSWORD}
```

> :warning: You should not use username-password authentication in production. Use oauth access-token instead.
> Read more about this in the [Venafi TPP documenation for cert-manager](https://cert-manager.io/docs/configuration/venafi/))

Next create a ClusterIssuer configured with the connection settings for your Venafi TPP server

```yaml
# tpp-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: tpp-issuer
spec:
  venafi:
    zone: \VED\Policy\Certificates\k8s\cluster1  # <- Substitute with your desired policy folder
    tpp:
      url: ${TPP_URL} # <- Substitute with your TPP server API URL
      credentialsRef:
        name: tpp-secret
```

```shell
kubectl apply -f tpp-issuer.yaml
```

You can check the ClusterIssuer status using the following commands:

```shell
kubectl wait --for=condition=Ready clusterissuers.cert-manager.io tpp-issuer
kubectl describe clusterissuers.cert-manager.io tpp-issuer
```

Now create a Certificate called linkerd-trust-anchor and associate it with the tpp-issuer:

```yaml
# linkerd-trust-anchor.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: linkerd-trust-anchor
  namespace: cert-manager
spec:
  isCA: true
  commonName: root.linkerd.cluster.local
  secretName: linkerd-identity-trust-roots
  duration: 720h
  privateKey:
    rotationPolicy: Always
    algorithm: ECDSA
  usages:
  - cert sign
  - crl sign
  - server auth
  - client auth
  issuerRef:
    name: tpp-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

```shell
kubectl apply -f linkerd-trust-anchor.yaml
```

Check the status of the Certificate and the content of the resulting Secret:

```shell
cmctl status certificate -n cert-manager linkerd-trust-anchor
cmctl inspect secret -n cert-manager linkerd-identity-trust-roots
```

### Create the linkerd-identity-issuer CA certificate

This is the second intermediate CA certificate which is used by the linkerd identity component.
This certificate must be signed by the first, so we configure another ClusterIssuer (a CA Issuer),
which uses the private key of the first certificate to sign other certificates.

```yaml
# linkerd-trust-anchor-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: linkerd-trust-anchor
spec:
  ca:
    secretName: linkerd-identity-trust-roots
```

```shell
kubectl apply -f linkerd-trust-anchor-issuer.yaml
```

Check that this ClusterIssuer is Ready before continuing:

```shell
kubectl wait --for=condition=Ready clusterissuers.cert-manager.io linkerd-trust-anchor
kubectl describe clusterissuer.cert-manager.io linkerd-trust-anchor
```

Now we can begin pre-populating the linkerd namespace with the TLS certificates that the `linkerd install` commands needs.
First create the namespace:
```shell
kubectl create ns linkerd
```

Now create a Certificate referencing the linkerd-trust-anchor ClusterIssuer:

```yaml
# linkerd-identity.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: linkerd-identity
  namespace: linkerd
spec:
  secretName: linkerd-identity-issuer
  duration: 48h
  renewBefore: 25h
  issuerRef:
    name: linkerd-trust-anchor
    kind: ClusterIssuer
  commonName: identity.linkerd.cluster.local
  dnsNames:
  - identity.linkerd.cluster.local
  isCA: true
  privateKey:
    rotationPolicy: Always
    algorithm: ECDSA
  usages:
  - cert sign
  - crl sign
  - server auth
  - client auth
```

```shell
kubectl apply -f linkerd-identity.yaml
```

Check the Certificate and the contents of the Secret:

```terminal
cmctl status certificate -n linkerd linkerd-identity
cmctl inspect secret -n linkerd linkerd-identity-issuer
```

### Create the linkerd-identity-trust-roots ConfigMap using `trust`

Now we need to copy just the `tls.crt` file into a ConfigMap called linkerd-identity-trust-roots,
which is the ConfigMap that linkerd expects to find in every namespace and which it will mount into the Pods that are injected with the linkerd proxy,
so that the proxies can verify each others mTLS certificates.

Begin by [Installing trust using Helm](https://cert-manager.io/docs/projects/trust/#installation) as follows:

```
helm upgrade -i -n cert-manager cert-manager-trust jetstack/cert-manager-trust --wait
```

Trust installs a CRD called Bundle which is used to configure the source Secret and the destination ConfigMap and file.
Create a bundle to copy the `tls.crt` file to a ConfigMap with the linkerd specific file name: `ca-bundle.crt`:

```yaml
# linkerd-identity-trust-roots-bundle.yaml
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: linkerd-identity-trust-roots
spec:
  sources:
  - secret:
      name: "linkerd-identity-trust-roots"
      key: "tls.crt"
  target:
    configMap:
      key: "ca-bundle.crt"
```

```shell
kubectl apply -f linkerd-identity-trust-roots-bundle.yaml
```


Check that the ConfigMap has been created and has the public CA certificate content:

```
kubectl describe bundles.trust.cert-manager.io linkerd-identity-trust-roots
kubectl -n linkerd describe cm linkerd-identity-trust-roots
kubectl -n linkerd get cm linkerd-identity-trust-roots -o jsonpath='{.data.ca-bundle\.crt}' | openssl x509 -in - -noout -text
```

### Install linkerd

Now we're ready to [Install linkerd](https://linkerd.io/2.11/getting-started/).

We use the `linkerd install` command with the following two command line flags,
which tell it to use the existing TLS certificates and CA bundles,
rather than creating them:

```shell
linkerd install --identity-external-issuer --set identity.externalCA=true | kubectl apply -f -
```

Now run `linkerd check` to follow the progress of the installation, it should take 2-3 minutes:

```shell
linkerd check
```

> :warning: You may see a warning like:
>
> × trust anchors are using supported crypto algorithm
>    Invalid trustAnchors:
>        * 70576693952137681083586275855297161308 venafidemo-TPP-CA must use ECDSA for public key algorithm, instead RSA was used
>    see https://linkerd.io/2.11/checks/#l5d-identity-trustAnchors-use-supported-crypto for hints
>
> This is due to the `linkerd check` command being too strict about the use of the RSA key algorithm used by the Venafi TPP CA.,
> and the warning can be ignored.
> See [linkerd2#7771](https://github.com/linkerd/linkerd2/issues/7771) for more information.

### Install a linkerd demo app

Now that linkerd is installed, test it by installing the emojivoto demo app and use `linkerd viz` to verify that the components are communicating using mTLS.


Install `linkerd viz` as follows:

```shell
linkerd viz install | kubectl apply -f -
linkerd check
```

Install emojivoto as follows:

```shell
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml \
  | linkerd inject - | kubectl apply -f -
```

Watch the TLS traffic flowing between the emojivoto components, as follows:

```shell
linkerd viz tap deployment  -n emojivoto web
```

And finally you can connect to the emojivoto web UI using a tunnel:

```shell
kubectl -n emojivoto port-forward svc/web-svc 8080:80
```

Point your web browser at http://localhost:8080

<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Index: skip
SMA-Description: Using demos of PKI for certificate management with Linkerd (OUT OF DATE)
-->

# Enterprise PKI in the cloud-native world with Linkerd and cert-manager

Migrating an existing enterprise PKI to Kubernetes can be daunting — there are
so many moving parts to achieving trust across boundaries! From bootstrapping
certificates to terminating TLS at the ingress level, all the way down to
securing communication between workloads, supporting identity management
quickly becomes non-trivial. In this hands-on workshop, members of the
cert-manager and Linkerd teams will show you how to combine the two projects to
manage identity while providing mTLS between your workloads, greatly reducing
the burden on platform teams. You'll learn how to integrate with a CA from an
external PKI, and use it to bootstrap zero-trust across all cluster boundaries.

There are two similar demos that make use of different external issuers. The
presenter's recommendation is that you first go through the materials in the
[pki-workshop-venafi-tpp] directory to get an idea for how cert-manager and
Linkerd can be used together to bootstrap identity and mTLS in a Kubernetes
environment. A good follow-up that the reader can use as a hands-on exercise
can be found in the steps substantiated in the [pki-workshop-vault] directory.

[pki-workshop-vault]: ./pki-workshop-vault/STEPS.md
[pki-workshop-venafi-tpp]: ./pki-workshop-venafi-tpp/README.md

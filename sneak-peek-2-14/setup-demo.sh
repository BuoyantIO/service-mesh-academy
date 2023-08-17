#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2022 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2022 Buoyant Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.  You may obtain
# a copy of the License at
#
#     http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Next up: install Emissary-ingress 3.1.0 as the ingress. This is mostly following
# the quickstart, but we force every Deployment to one replica to reduce the load
# on k3d.

#@SHOW

gen_anchor () {
    rm -rf trust-anchor.crt trust-anchor.key

    step certificate create \
         --profile root-ca --no-password --insecure \
         --not-after='87600h' \
         root.linkerd.cluster.local \
         trust-anchor.crt trust-anchor.key
}

gen_issuer () {
    domain=$1

    rm -rf "issuer-${domain}.crt" "issuer-${domain}.key"

    step certificate create \
         --profile intermediate-ca --no-password --insecure \
         --ca trust-anchor.crt --ca-key trust-anchor.key \
         --not-after='2160h' \
         identity.linkerd.${domain} \
         "issuer-${domain}.crt" "issuer-${domain}.key"
}

#### LINKERD_INSTALL_START

gen_anchor
gen_issuer face
gen_issuer smiley
gen_issuer color

for ctx in face smiley color; do \
    domain="${ctx}" ;\
    linkerd --context=$ctx install --crds | kubectl --context $ctx apply -f - ;\
    linkerd --context=$ctx install \
        --cluster-domain "$domain" \
        --identity-trust-anchors-file trust-anchor.crt \
        --identity-issuer-certificate-file "issuer-${domain}.crt" \
        --identity-issuer-key-file "issuer-${domain}.key" \
        | kubectl --context $ctx apply -f - ;\
done

for ctx in face smiley color; do \
    linkerd --context=$ctx multicluster install | kubectl --context $ctx apply -f - ;\
done

for ctx in face smiley color; do \
    linkerd --context=$ctx check ;\
done

# Link clusters.

SMILEY_APISERVER=$(kubectl --context smiley get svc -n kube-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
linkerd --context=smiley multicluster link \
        --cluster-name smiley \
        --api-server-address="https://${SMILEY_APISERVER}:6443" \
    | kubectl --context=face apply -f -

COLOR_APISERVER=$(kubectl --context color get svc -n kube-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
linkerd --context=color multicluster link \
        --cluster-name color \
        --api-server-address="https://${COLOR_APISERVER}:6443" \
    | kubectl --context=face apply -f -

#### EMISSARY_INSTALL_START

# Install Emissary only in the face cluster.
kubectl config use-context face

EMISSARY_CRDS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-crds.yaml
EMISSARY_INGRESS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-emissaryns.yaml

kubectl create namespace emissary && \
curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_CRDS | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    kubectl apply -f -
kubectl wait --timeout=90s --for=condition=available deployment emissary-apiext -n emissary-system

curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_INGRESS | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    linkerd inject - | \
    kubectl apply -f -

kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes
#### EMISSARY_INSTALL_END

# Finally, configure Emissary for HTTP - not HTTPS! - routing to our cluster.
#### EMISSARY_CONFIGURE_START
kubectl apply -f emissary-yaml
#### EMISSARY_CONFIGURE_END

#@SHOW

# Once that's done, install Faces, being sure to inject it into the mesh.
# Install its ServiceProfiles and Mappings too: all of these things are in
# the k8s directory.

#### FACES_INSTALL_START

# In the face cluster, install the Faces GUI, the face workload, the smiley-routing stuff,
# and the color workload.

kubectl --context face create ns faces
linkerd --context face inject k8s/01-face/faces-gui.yaml | kubectl --context face apply -f -
linkerd --context face inject k8s/01-face/faces-mc.yaml | kubectl --context face apply -f -

# In the smiley cluster, install just the smiley workload.

kubectl --context smiley create ns faces
linkerd --context smiley inject k8s/01-smiley/smiley-workload.yaml | kubectl --context smiley apply -f -

# In the color workload, install just the color workload.

kubectl --context color create ns faces
linkerd --context color inject k8s/01-color/color-workload.yaml | kubectl --context color apply -f -

# Finally, install all the mappings in the face cluster.

kubectl --context face apply -f k8s/01-face/faces-gui-mapping.yaml
kubectl --context face apply -f k8s/01-face/face-mapping.yaml
kubectl --context face apply -f k8s/01-face/smiley-mapping.yaml
kubectl --context face apply -f k8s/01-face/color-mapping.yaml

#### FACES_INSTALL_END

# After that, wait for the Faces application to be ready.
for ctx in face smiley color; do \
    kubectl --context $ctx -n faces wait --for condition=available --timeout=90s deploy --all ;\
done

REMAINING=60 ;\
while true; do \
    printf "." ;\
    status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/faces/) ;\
    if [ "$status" = "200" ]; then \
        echo "Faces ready!" ;\
        break ;\
    fi ;\
    REMAINING=$((REMAINING-1)) ;\
    if [ "$REMAINING" -le 0 ]; then \
        echo "Faces not ready after 60 seconds" ;\
        exit 1 ;\
    fi ;\
    sleep 1 ;\
done

# Start off with just the smiley service mirrored.

kubectl --context smiley -n faces label svc/smiley mirror.linkerd.io/exported=remote-discovery
# kubectl --context smiley -n faces label svc/smiley2 mirror.linkerd.io/exported=remote-discovery
# kubectl --context color -n faces label svc/color mirror.linkerd.io/exported=remote-discovery
# kubectl --context color -n faces label svc/color2 mirror.linkerd.io/exported=remote-discovery

#!/bin/env bash
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

# clear

# Create three K3d clusters for the Faces application.

# Ditch any old clusters...
k3d cluster delete face &>/dev/null
k3d cluster delete smiley &>/dev/null
k3d cluster delete color &>/dev/null

#@SHOW

# Expose ports 80 and 443 to the local host, so that our ingress can work.
# Also, don't install traefik, since we'll be putting Linkerd on instead.
k3d cluster create face \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
    --agents=0 \
    --servers=1 \
    --network=face-network \
    --k3s-arg '--disable=local-storage,traefik,metrics-server@server:*;agents:*' \
    --k3s-arg '--cluster-domain=face@server:*' \
    --k3s-arg '--cluster-cidr=10.23.0.0/24@server:*'

# Note that we do NOT map 80 & 443 here; no point and they're taken.
k3d cluster create smiley \
    --agents=0 \
    --servers=1 \
    --network=face-network \
    --k3s-arg '--disable=local-storage,metrics-server@server:*;agents:*' \
    --k3s-arg '--cluster-domain=smiley@server:*' \
    --k3s-arg '--cluster-cidr=10.23.1.0/24@server:*'

# # Note that we do NOT map 80 & 443 here; no point and they're taken.
k3d cluster create color \
    --agents=0 \
    --servers=1 \
    --network=face-network \
    --k3s-arg '--disable=local-storage,metrics-server@server:*;agents:*' \
    --k3s-arg '--cluster-domain=color@server:*' \
    --k3s-arg '--cluster-cidr=10.23.2.0/24@server:*'

kubectl config delete-context face >/dev/null 2>&1
kubectl config rename-context k3d-face face
kubectl config delete-context smiley >/dev/null 2>&1
kubectl config rename-context k3d-smiley smiley
kubectl config delete-context color >/dev/null 2>&1
kubectl config rename-context k3d-color color

face_cidr=
face_router=
smiley_cidr=
smiley_router=
color_cidr=
color_router=

REMAINING=60 ;\
echo "Getting face cluster network info..." ;\
while true; do \
    face_cidr=$(kubectl --context face get node k3d-face-server-0 -o jsonpath='{.spec.podCIDR}') ;\
    face_router=$(kubectl --context face get node k3d-face-server-0 -o jsonpath='{.status.addresses[?(.type=="InternalIP")].address}') ;\
    if [ -n "$face_cidr" -a -n "$face_router" ]; then break; fi ;\
    REMAINING=$(( $REMAINING - 1 )) ;\
    printf "." ;\
    sleep 1 ;\
done ;\
if [ $REMAINING -eq 0 ]; then \
    echo "Timed out waiting for face network info" ;\
    exit 1 ;\
else \
    printf "\n" ;\
fi

REMAINING=60 ;\
echo "Getting smiley cluster network info..." ;\
while true; do \
    smiley_cidr=$(kubectl --context smiley get node k3d-smiley-server-0 -o jsonpath='{.spec.podCIDR}') ;\
    smiley_router=$(kubectl --context smiley get node k3d-smiley-server-0 -o jsonpath='{.status.addresses[?(.type=="InternalIP")].address}') ;\
    if [ -n "$smiley_cidr" -a -n "$smiley_router" ]; then break; fi ;\
    REMAINING=$(( $REMAINING - 1 )) ;\
    printf "." ;\
    sleep 1 ;\
done ;\
if [ $REMAINING -eq 0 ]; then \
    echo "Timed out waiting for smiley network info" ;\
    exit 1 ;\
else \
    printf "\n" ;\
fi

REMAINING=60 ;\
echo "Getting color cluster network info..." ;\
while true; do \
    color_cidr=$(kubectl --context color get node k3d-color-server-0 -o jsonpath='{.spec.podCIDR}') ;\
    color_router=$(kubectl --context color get node k3d-color-server-0 -o jsonpath='{.status.addresses[?(.type=="InternalIP")].address}') ;\
    if [ -n "$color_cidr" -a -n "$color_router" ]; then break; fi ;\
    REMAINING=$(( $REMAINING - 1 )) ;\
    printf "." ;\
    sleep 1 ;\
done ;\
if [ $REMAINING -eq 0 ]; then \
    echo "Timed out waiting for color network info" ;\
    exit 1 ;\
else \
    printf "\n" ;\
fi

echo "face cluster: route ${smiley_cidr} via ${smiley_router}, ${color_cidr} via ${color_router}"
docker exec -it k3d-face-server-0 ip route add ${smiley_cidr} via ${smiley_router}
docker exec -it k3d-face-server-0 ip route add ${color_cidr} via ${color_router}

echo "smiley cluster: route ${face_cidr} via ${face_router}, ${color_cidr} via ${color_router}"
docker exec -it k3d-smiley-server-0 ip route add ${face_cidr} via ${face_router}
docker exec -it k3d-smiley-server-0 ip route add ${color_cidr} via ${color_router}

echo "color cluster: route ${face_cidr} via ${face_router}, ${smiley_cidr} via ${smiley_router}"
docker exec -it k3d-color-server-0 ip route add ${face_cidr} via ${face_router}
docker exec -it k3d-color-server-0 ip route add ${smiley_cidr} via ${smiley_router}

# Wait for the traefik (ugh) service IP addresses to be ready for the smiley
# and color clusters.

for ctx in smiley color; do \
    echo "Waiting for traefik service in $ctx..." ;\
    REMAINING=60 ;\
    while [ $REMAINING -gt 0 ]; do \
        APISERVER=$(kubectl --context $ctx get svc -n kube-system traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null) ;\
        if [ -n "$APISERVER" ]; then break; fi ;\
        REMAINING=$(( $REMAINING - 1 )) ;\
        printf "." ;\
        sleep 1 ;\
    done ;\
    if [ $REMAINING -eq 0 ]; then \
        echo "Timed out waiting for traefik service in $ctx" ;\
        exit 1 ;\
    else \
        printf "\n" ;\
    fi ;\
done

#@SKIP
#@wait

# if [ -f images.tar ]; then k3d image import -c ${CLUSTER} images.tar; fi
# #@wait

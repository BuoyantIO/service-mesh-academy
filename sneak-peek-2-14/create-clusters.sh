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

cycle_cluster () {
    port_args=

    case "$1" in
        --map-ports)
            port_args='-p 80:80@loadbalancer -p 443:443@loadbalancer'
            shift
            ;;
        --*)
            echo "Unknown option $1" >&2
            exit 1
            ;;
    esac

    ctx="$1"
    cidr="$2"

    k3d cluster delete $ctx >/dev/null 2>&1

    k3d cluster create $ctx \
        $port_args \
        --agents=0 \
        --servers=1 \
        --network=face-network \
        --k3s-arg '--disable=local-storage,traefik,metrics-server@server:*;agents:*' \
        --k3s-arg "--cluster-cidr=${cidr}@server:*"
        # --k3s-arg "--cluster-domain=${ctx}@server:*"

    kubectl config delete-context $ctx >/dev/null 2>&1
    kubectl config rename-context k3d-$ctx $ctx
}

get_network_info () {
    ctx="$1"
    REMAINING=60
    echo "Getting $ctx cluster network info..." >&2

    while true; do
        cidr=$(kubectl --context $ctx get node k3d-$ctx-server-0 -o jsonpath='{.spec.podCIDR}')
        router=$(kubectl --context $ctx get node k3d-$ctx-server-0 -o jsonpath='{.status.addresses[?(.type=="InternalIP")].address}')

        echo "$ctx: cidr=$cidr router=$router" >&2

        if [ -n "$cidr" -a -n "$router" ]; then break; fi
        REMAINING=$(( $REMAINING - 1 ))
        printf "." >&2
        sleep 1
    done

    if [ $REMAINING -eq 0 ]; then
        echo "Timed out waiting for $ctx network info" >&2
        exit 1
    else
        printf "\n" >&2
        echo "$cidr $router"
    fi
}

#@SKIP

# Create the three K3d clusters for the Faces application.

cycle_cluster --map-ports north "10.23.0.0/24"
cycle_cluster             east  "10.23.1.0/24"
cycle_cluster             west  "10.23.2.0/24"

#@SHOW

# Grab network info for each cluster...

north_net=$(get_network_info north)
east_net=$(get_network_info east)
west_net=$(get_network_info west)

north_cidr=$(echo $north_net | cut -d' ' -f1)
north_router=$(echo $north_net | cut -d' ' -f2)
east_cidr=$(echo $east_net | cut -d' ' -f1)
east_router=$(echo $east_net | cut -d' ' -f2)
west_cidr=$(echo $west_net | cut -d' ' -f1)
west_router=$(echo $west_net | cut -d' ' -f2)

echo "north cluster: route ${east_cidr} via ${east_router}, ${west_cidr} via ${west_router}"
docker exec -it k3d-north-server-0 ip route add ${east_cidr} via ${east_router}
docker exec -it k3d-north-server-0 ip route add ${west_cidr} via ${west_router}

echo "east cluster: route ${north_cidr} via ${north_router}, ${west_cidr} via ${west_router}"
docker exec -it k3d-east-server-0 ip route add ${north_cidr} via ${north_router}
docker exec -it k3d-east-server-0 ip route add ${west_cidr} via ${west_router}

echo "west cluster: route ${north_cidr} via ${north_router}, ${east_cidr} via ${east_router}"
docker exec -it k3d-west-server-0 ip route add ${north_cidr} via ${north_router}
docker exec -it k3d-west-server-0 ip route add ${east_cidr} via ${east_router}

#@SKIP
#@wait

# if [ -f images.tar ]; then k3d image import -c ${CLUSTER} images.tar; fi
# #@wait

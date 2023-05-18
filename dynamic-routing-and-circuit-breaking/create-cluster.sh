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

clear

# Create a K3d cluster to run the Faces application.
CLUSTER=${CLUSTER:-faces}
# echo "CLUSTER is $CLUSTER"

# Ditch any old cluster...
k3d cluster delete $CLUSTER &>/dev/null

#@SHOW

# Expose ports 80 and 443 to the local host, so that our ingress can work.
# Also, don't install traefik, since we'll be putting Linkerd on instead.
k3d cluster create $CLUSTER \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
    --k3s-arg '--disable=traefik@server:*;agents:*'

#@wait
#@HIDE

# if [ -f images.tar ]; then k3d image import -c ${CLUSTER} images.tar; fi
# #@wait

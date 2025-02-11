# SPDX-FileCopyrightText: 2024 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2024 Buoyant Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.  You may obtain
# a copy of the License at
#
#       http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Make sure that we have what we need in our $PATH. Makefile-style escapes are
# required here.

set -e

if [ -z "$DASH0_AUTH_TOKEN" ]; then \
    echo "DASH0_AUTH_TOKEN is not set" >&2; \
    exit 1; \
fi

if [ -z "$DASH0_OTLP_ENDPOINT" ]; then \
    echo "DASH0_OTLP_ENDPOINT is not set" >&2; \
    exit 1; \
fi

check () {
    cmd="$1"
    url="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing: $cmd (see $url)" >&2
        exit 1
    fi
}

check bat "https://github.com/sharkdp/bat"
check jq "https://github.com/jqlang/jq#installation"
check yq "https://github.com/mikefarah/yq?tab=readme-ov-file#install"
check linkerd "https://linkerd.io/2/getting-started/"
check kubectl "https://kubernetes.io/docs/tasks/tools/"

set +e

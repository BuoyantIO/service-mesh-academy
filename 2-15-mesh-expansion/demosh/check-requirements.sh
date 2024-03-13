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

check () {
    cmd="$1"
    url="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing: $cmd (see $url)" >&2
        exit 1
    fi
}

check_certs () {
    if [ ! -f certs/ca.crt -o ! -f certs/ca.key -o ! -f certs/issuer.crt -o ! -f certs/issuer.key ]; then
        echo "You need to generate certificates in the certs/ directory" >&2
        echo "before running this demo." >&2
        echo "" >&2

        if command -v "step" >/dev/null 2>&1; then
            echo "You can run sh ./setup-certs.sh to use the step CLI to create certs" >&2
            echo "for the demo." >&2
        else
            echo "Visit https://smallstep.com/docs/step-cli/installation" >&2
            echo "to get the step CLI, after which you can use setup-certs.sh" >&2
            echo "to create certs for the demo." >&2
        fi
        exit 1
    fi
}

check linkerd "https://linkerd.io/2/getting-started/"
check kubectl "https://kubernetes.io/docs/tasks/tools/"
check bat "https://github.com/sharkdp/bat"
check helm "https://helm.sh/docs/intro/quickstart/"
check yq "https://github.com/mikefarah/yq?tab=readme-ov-file#install"

# Make sure we have certificates.

check_certs

set +e

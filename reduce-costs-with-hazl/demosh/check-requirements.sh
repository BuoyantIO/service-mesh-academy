set -e

# Make sure that we have what we need in our $PATH.

check () {
    cmd="$1"
    url="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing: $cmd (see $url)" >&2
        exit 1
    fi
}

# check linkerd "https://linkerd.io/2/getting-started/"
check kubectl "https://kubernetes.io/docs/tasks/tools/"
check k3d "https://k3d.io/"
check step "https://smallstep.com/docs/step-cli/installation"
check bat "https://github.com/sharkdp/bat"
check helm "https://helm.sh/docs/intro/quickstart/"

if [ -z "$BUOYANT_LICENSE" -o -z "$API_CLIENT_ID" -o -z "$API_CLIENT_SECRET" ]; then \
    echo "Missing: BUOYANT_LICENSE, API_CLIENT_ID, or API_CLIENT_SECRET" >&2 ;\
    exit 1 ;\
fi

set +e
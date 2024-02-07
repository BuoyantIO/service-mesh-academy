set -e

# Make sure that we have what we need in our $PATH. Makefile-style escapes are
# required here.

check () {
    cmd="$1"
    url="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing: $cmd (see $url)" >&2
        exit 1
    fi
}

check linkerd "https://linkerd.io/2/getting-started/"
check kubectl "https://kubernetes.io/docs/tasks/tools/"
check step "https://smallstep.com/docs/step-cli/installation"
check bat "https://github.com/sharkdp/bat"
check helm "https://helm.sh/docs/intro/quickstart/"
check yq "https://github.com/mikefarah/yq?tab=readme-ov-file#install"

set +e

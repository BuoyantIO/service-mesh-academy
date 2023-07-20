set -e

check_ns () {
    kubectl get ns "$1" >/dev/null 2>&1
}

# We need an empty cluster with at least three Nodes.

if ! check_ns kube-system; then \
    echo "No cluster found. Please create one." >&2 ;\
    exit 1 ;\
fi

if check_ns linkerd; then \
    echo "Cluster is not empty. Please create an empty cluster." >&2 ;\
    exit 1 ;\
fi

# Make sure that we have what we need in our $PATH. Makefile-style escapes are
# required here.
missing= ;\
\
for cmd in bat kubectl linkerd step helm; do \
    if ! command -v $cmd >/dev/null 2>&1; then \
        missing="$missing $cmd" ;\
    fi ;\
done ;\

if [ -n "$missing" ]; then \
    echo "Missing commands:$missing" >&2 ;\
    exit 1 ;\
fi

set +e


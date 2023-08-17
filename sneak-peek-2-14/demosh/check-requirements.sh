set -e

check_ns () {
    kubectl get ns "$1" >/dev/null 2>&1
}

# Make sure that we have what we need in our $PATH. Makefile-style escapes are
# required here.
missing= ;\
\
for cmd in bat jq yq kubectl linkerd; do \
    if ! command -v $cmd >/dev/null 2>&1; then \
        missing="$missing $cmd" ;\
    fi ;\
done ;\

if [ -n "$missing" ]; then \
    echo "Missing commands:$missing" >&2 ;\
    exit 1 ;\
fi

# We need three clusters, linked together.

contexts=$(kubectl config get-contexts -o name | sort | tr '\012' ' ' | sed -e 's/ $//')

if [ "$contexts" != "color face smiley" ]; then \
    echo "Please run create-clusters.sh to set up the face, color, and smiley clusters." >&2 ;\
    exit 1 ;\
fi

gateways=$(linkerd --context face mc gateways -o json | jq -r '.[] | @text "\(.clusterName):\(.alive)"' | sort | tr '\012' ' ' | sed -e 's/ $//')

if [ "$gateways" != "color:true smiley:true" ]; then \
    echo "Please run create-clusters.sh to set up and link the face, color, and smiley clusters." >&2 ;\
    exit 1 ;\
fi

set +e

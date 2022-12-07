# First, check clusters. Note that we _must_ use Makefile-style escapes for
# the newlines here in order for this to work with demosh.

set -e

missing= ;\
for cluster in east west; do \
    if ! k3d cluster get "$cluster" >/dev/null 2>&1; then \
        missing="$missing $cluster" ;\
    fi ;\
done ;\
\
if [ -n "$missing" ]; then \
    echo "Missing clusters:$missing" >&2 ;\
    echo "See CREATE.md for more." >&2 ;\
    exit 1 ;\
fi

# Next, check things we need in the PATH. Again, Makefile-style escapes are
# required here.
missing= ;\
\
for cmd in kubectl step linkerd; do \
    if ! command -v $cmd >/dev/null 2>&1; then \
        missing="$missing $cmd" ;\
    fi ;\
done ;\
\
if [ -n "$missing" ]; then \
    echo "Missing commands:$missing" >&2 ;\
    exit 1 ;\
fi

set +e

set -e

# Make sure that we have what we need in our $PATH. Makefile-style escapes are
# required here.
missing= ;\
\
for cmd in kubectl kubectx linkerd; do \
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

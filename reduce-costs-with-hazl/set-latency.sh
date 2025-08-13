#!/bin/bash

NAMESPACE="faces"
LATENCY=""
DO_COLOR=false
DO_SMILEY=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --color)
            DO_COLOR=true
            ;;
        --smiley)
            DO_SMILEY=true
            ;;
        *)
            LATENCY="$arg"
            ;;
    esac
done

if [[ -z "$LATENCY" ]]; then
    echo "Usage: $0 [--color] [--smiley] <latency>"
    exit 1
fi

# If neither flag is set, do both
if ! $DO_COLOR && ! $DO_SMILEY; then
    DO_COLOR=true
    DO_SMILEY=true
fi

for zone in a b c; do
    if $DO_COLOR; then
        echo kubectl -n "$NAMESPACE" set env deployment/"color-zone-$zone" DELAY_BUCKETS="$LATENCY"
        kubectl -n "$NAMESPACE" set env deployment/"color-zone-$zone" DELAY_BUCKETS="$LATENCY"
    fi

    if $DO_SMILEY; then
        echo kubectl -n "$NAMESPACE" set env deployment/"smiley-zone-$zone" DELAY_BUCKETS="$LATENCY"
        kubectl -n "$NAMESPACE" set env deployment/"smiley-zone-$zone" DELAY_BUCKETS="$LATENCY"
    fi
done

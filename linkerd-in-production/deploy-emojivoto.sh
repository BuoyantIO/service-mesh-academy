#!/bin/bash

set -eu

kubectl create ns emojivoto

kubectl annotate ns emojivoto linkerd.io/inject=enabled

kubectl apply -f https://run.linkerd.io/emojivoto.yml
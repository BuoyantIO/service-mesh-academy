#!/bin/bash

# Install emojivoto example
curl -sL https://run.linkerd.io/emojivoto.yml \
| linkerd inject - \
| kubectl apply -f - 

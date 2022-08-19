#!/bin/env bash
# shellcheck source=demo-magic.sh
. demo-magic.sh
. demo-magic-extras.sh

DEMO_CMD_COLOR=$BLACK
DEMO_COMMENT_COLOR=$PURPLE
PROMPT_WAIT=false

clear

# Show basics about the cluster.
pei "kubectl get nodes"
pei "kubectl get ns | sort"
wait
clear

# Make sure that linkerd is OK.
pei "linkerd check"
wait
clear

# OH NO! Something's wrong with Emojivoto.
show "# OH NO SOMETHING IS WRONG WITH EMOJIVOTO!"
show ""
pi "# ...so what shall we do?"
wait
clear

# Check basic namespace stats...
pei "linkerd viz stat namespace"
wait
clear

# ...then drill down by deployment.
pe "linkerd viz stat deployment -n emojivoto"
wait
clear

pe "linkerd viz top -n emojivoto deploy/web"
clear

pe "linkerd viz top -n emojivoto deploy/voting"
clear

# Next, drill into the seemingly-broken doughnut vote.
pe "linkerd viz tap deployment/web -n emojivoto --to deployment/voting --path / | less"
clear

pe "linkerd viz tap deployment/web -n emojivoto --to deployment/voting --path /emojivoto.v1.VotingService/VoteDoughnut | less"
clear

pe "linkerd viz tap deployment/web -n emojivoto --to deployment/voting --path /emojivoto.v1.VotingService/VoteDoughnut -o json | less"
clear

# Adding ServiceProfiles can make this much faster.
show "This was slower than it should have been, because linkerd wasn't already tracking things."

# Getting ServiceProfiles from protobuf is really easy.
pe "linkerd profile --proto protos/Emoji.proto emoji-svc -n emojivoto"
wait
pe "linkerd profile --proto protos/Emoji.proto emoji-svc -n emojivoto | kubectl apply -f -"
wait
pe "linkerd profile --proto protos/Voting.proto voting-svc -n emojivoto | kubectl apply -f -"
wait
clear

# Happily, we can have linkerd-viz tap traffic and build ServiceProfiles that way
# too.
pe "linkerd viz profile -n emojivoto web-svc --tap deploy/web --tap-duration 10s > /tmp/web-profile.yaml"
pei "cat /tmp/web-profile.yaml"
wait
pe "kubectl apply -f /tmp/web-profile.yaml"
wait
clear

# Go look at everything at http://viz.example.com. Drill in and click on the
# "Route Metrics" tabs.
show "Let's go check out the dashboard!"

# OK. Now it's books' turn.
clear

show "# OH NO NOW SOMETHING IS WRONG WITH BOOKS!"
show ""
pi "# ...so what shall we do this time?"
clear

# Here we can start with routes metrics from the CLI. Note that if you don't
# specify "--to", you'll get only routes coming INTO your service or deployment.
pe "linkerd viz -n booksapp routes svc/webapp"
wait

pe "linkerd viz -n booksapp routes deploy/webapp --to svc/authors"
wait

pe "linkerd viz -n booksapp routes deploy/webapp --to svc/books"
wait

pe "linkerd viz -n booksapp routes deploy/books --to svc/authors"
wait

# Switch over to the browser and look at everything at http://viz.example.com
# again. Also check out https://linkerd.io/2.11/features/service-profiles/ for
# docs on ServiceProfile, which will lead you to...
clear
wait

# ...adding isRetryable for the failing HEAD request.
show "Add isRetryable: true to the books ServiceProfile"
pe "kubectl -n booksapp edit sp/authors.booksapp.svc.cluster.local"
wait
clear

# Watch to see the metrics improve! Note "-o wide" here.
pe "watch linkerd viz -n booksapp routes deploy/books --to svc/authors -o wide"
# wait
clear

# We don't use "-o wide" here, so we only see the effective success rate.
pe "watch linkerd viz -n booksapp routes deploy/webapp --to svc/books"
# wait
clear

# Done! Thanks for reading!

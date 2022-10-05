#!/bin/env bash

##########
## Observability with Linkerd

######## SETUP
# This uses demo-magic by Paxton Hare: https://github.com/paxtonhare/demo-magic/
# A copy of demo-magic.sh from there is included here; demo-magic-extras.sh is
# from Flynn (GitHub @kflynn).

# shellcheck source=demo-magic.sh
. demo-magic.sh
. demo-magic-extras.sh

DEMO_CMD_COLOR=$BLACK
DEMO_COMMENT_COLOR=$PURPLE
PROMPT_WAIT=false

# This show_* stuff allows using environment variable hooks to control what's
# shown when livecasting the demo: for example, "show_terminal" will execute
# the command in $DEMO_HOOK_TERMINAL if it's set, and do nothing if not.
# So if you don't set the environment variables, the show_* commands will all
# be noops.

show_terminal () { run_hook TERMINAL "$@"; }
show_browser  () { run_hook BROWSER "$@"; }
show_video    () { run_hook VIDEO "$@"; }
show_slides   () { run_hook SLIDES "$@"; }
slide_advance () { run_hook ADVANCE "$@"; }

# The START hook is here to allow waiting at the start of the demo for slides,
# intros, whatever. Again, it's a no-op if DEMO_HOOK_START isn't set.
run_hook START

# This is a good place to switch to the terminal.
clear
show_terminal --nowait

# Finally, by default we'll use emoji.example.com, viz.example.com, etc.
# If you want to use a different domain, set the DEMO_DOMAIN environment
# variable to the domain you want to use.

if [ -z "$DEMO_DOMAIN" ]; then
  DEMO_DOMAIN=example.com
fi

######## THE WORKSHOP

# To run the workshop, you'll need
#
# * a Kubernetes cluster and the `kubectl` command
#    * you can run `create-cluster.sh` to create a suitable `k3d` cluster
#    * or `setup-cluster.sh` to set up a cluster that's already running
#
# * arrange for "emoji.example.com", "books.example.com", and "viz.example.com"
#   to resolve to your cluster's ingress
#    * if you use create-cluster.sh to set up a k3d cluster, this is most
#      easily done by pointing all three to 127.0.0.1, perhaps by editing
#      /etc/hosts

# Show basics about the cluster.
show "# We already have a cluster set up. Let's look at it."
pei "kubectl get nodes"
pei "kubectl get ns | sort"
wait
clear

# Show how we installed things.
show "# Here's how we installed Linkerd:"
sed -n '/LINKERD_INSTALL_START/,/LINKERD_INSTALL_END/p' setup-cluster.sh | sed '1d;$d' | egrep -v '^#'
show ""
show "# ...and Grafana, since we need to do that by hand with Linkerd 2.12:"
sed -n '/GRAFANA_INSTALL_START/,/GRAFANA_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'
wait

clear
show "# Here's how we installed Emojivoto and Booksapp, including mesh injection:"
sed -n '/EMOJIVOTO_INSTALL_START/,/EMOJIVOTO_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'
show ""
sed -n '/BOOKS_INSTALL_START/,/BOOKS_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'
wait

clear
show "# And here's how we installed a single-replica Emissary-ingress,"
show "# including mesh injection:"
sed -n '/EMISSARY_INSTALL_START/,/EMISSARY_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'
show ""
show "# We had to configure Emissary for HTTP (not HTTPS!) routing too:"
sed -n '/EMISSARY_CONFIGURE_START/,/EMISSARY_CONFIGURE_END/p' setup-cluster.sh | sed '1d;$d'

wait
clear

show "# At this point, things should be working. Start by making sure that linkerd"
show "# is OK:"
pei "linkerd check"
wait
clear

# OH NO! Something's wrong with Emojivoto.
show "# OH NO SOMETHING IS WRONG WITH EMOJIVOTO!"
show ""
pi "# ...so what shall we do?"
wait
clear

show "# Let's start by checking basic stats for all of our namespaces."
pei "linkerd viz stat namespace"
wait
clear

show "# emojivoto is indeed showing some errors. Let's look at all the"
show "# deployments in that namespace."
pe "linkerd viz stat deployment -n emojivoto"
wait
clear

show "# The web and voting deployments look unhappy; let's look at each"
show "# of them individually."
pe "linkerd viz top -n emojivoto deploy/web"
clear

pe "linkerd viz top -n emojivoto deploy/voting"
clear

# show "# Let's hide the sources so the success rate always stays onscreen."
# pe "linkerd viz top -n emojivoto --hide-sources deploy/voting"
# clear

show "# It looks clear that voting for doughnuts is causing problems."
show "# So let's drill into that a bit."
pe "linkerd viz tap deploy/web -n emojivoto --to deploy/voting | less"
clear

show "# In fact, let's just look at the doughnut votes."
pe "linkerd viz tap deploy/web -n emojivoto --to deploy/voting --path /emojivoto.v1.VotingService/VoteDoughnut | less"
clear

show "# We can also use the JSON output formatter to get a more detailed view."
pe "linkerd viz tap deploy/web -n emojivoto --to deploy/voting --path /emojivoto.v1.VotingService/VoteDoughnut -o json | less"
clear

show "# We can also do this from the web browser."
wait
show_browser
show_terminal --nowait
clear

# Adding ServiceProfiles can make this much faster.
show "# This was slower than it should have been, because linkerd wasn't"
show "# already tracking things. We can make that better with ServiceProfiles."
show ""
wait

show "# We can use linkerd profile to generate a ServiceProfile from a protobuf."
show "# Let's do that for the Emoji service."
pei "linkerd profile --proto protos/Emoji.proto emoji-svc -n emojivoto"
wait
show ""
show "# We can apply that to the cluster..."
pei "linkerd profile --proto protos/Emoji.proto emoji-svc -n emojivoto | kubectl apply -f -"
wait
show ""
show "# ...and then repeat for the Voting service."
pe "linkerd profile --proto protos/Voting.proto voting-svc -n emojivoto | kubectl apply -f -"
wait
clear

show "# The Web service, though, isn't a gRPC service: it has no protobuf."
show "# Instead, we'll have linkerd-viz tap its traffic for ten seconds, and"
show "# build a ServiceProfile for it based on what it sees."
pei "linkerd viz profile -n emojivoto web-svc --tap deploy/web --tap-duration 10s > /tmp/web-profile.yaml"
pei "cat /tmp/web-profile.yaml"
wait
pe "kubectl apply -f /tmp/web-profile.yaml"
wait
clear

show "# Let's go back to the browser and drill into the 'Route Metrics' tabs."
wait
show_browser
show_terminal --nowait
clear

show "# OH NO NOW SOMETHING IS WRONG WITH BOOKS!"
show ""
pi "# ...so what shall we do this time?"
wait
clear

show "# The booksapp already has ServiceProfiles, so we can go straight to route"
show "# metrics from the CLI. Note that if you don't specify \"--to\", you'll get"
show "# only routes coming INTO your service or deployment."
pe "linkerd viz -n booksapp routes svc/webapp"
wait
show ""
show "# So there are some issues with requests coming into the webapp service."
show "# How about from webapp to the other services?"
pe "linkerd viz -n booksapp routes deploy/webapp --to svc/authors"
show ""
pe "linkerd viz -n booksapp routes deploy/webapp --to svc/books"
wait
show ""
show "# Hmmm. Does the books service talk to the authors service?"
pe "linkerd viz -n booksapp routes deploy/books --to svc/authors"
wait

clear
show "# Of course, we can do all this from the web browser too, once again"
show "# using the 'Route Metrics' tabs."
wait
show_browser
clear
show_terminal --nowait

show "# Let's add isRetryable: true to the books ServiceProfile"
pe "kubectl -n booksapp edit sp/authors.booksapp.svc.cluster.local"
wait
clear

show "# Now let's watch to see the metrics improve! Note the '-o wide' here:"
show "# that lets us see both the effective success rate (taking retries into"
show "# account) and the actual success rate (not taking retries into account)."
pe "watch linkerd viz -n booksapp routes deploy/books --to svc/authors -o wide"
# wait
clear

show "# Here, we don't bother with '-o wide', so we only see the effective"
show "# success rate."
pe "watch linkerd viz -n booksapp routes deploy/webapp --to svc/books"
# wait
clear

show "# And there you have it -- there's still a problem, but we were able"
show "# to make everything happy for the users."
wait
show_slides

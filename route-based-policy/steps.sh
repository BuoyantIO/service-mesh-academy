#!/bin/bash
# shellcheck source=demo-magic.sh
. demo-magic.sh
. demo-magic-extras.sh

DEMO_CMD_COLOR=$BLACK
DEMO_COMMENT_COLOR=$PURPLE
PROMPT_WAIT=false

# This show_* stuff allows using environment variable hooks to
# control what's shown when livecasting the demo. If you don't
# set the environment variables, they'll be noops.

run_hook () {
  # set -x
  hookname="DEMO_HOOK_${1}"
  hook=$(eval "echo \$$hookname")
  nowait="$2"

  if [ -n "$hook" ]; then $hook; fi
  if [ -z "$nowait" ]; then wait; fi
  # set +x
}

show_terminal () { run_hook TERMINAL "$@"; }
show_browser  () { run_hook BROWSER "$@"; }
show_video    () { run_hook VIDEO "$@"; }
show_slides   () { run_hook SLIDES "$@"; }

show_slides --nowait

clear
show "Waiting..."
wait

clear
show_terminal --nowait

# Show basics about the cluster.
show "# We already have a cluster set up. Let's look at it."
pei "kubectl get nodes"
pei "kubectl get ns | sort"
wait
clear

# Show how we installed things.
show "# Here's how we installed Linkerd:"
sed -n '/LINKERD_INSTALL_START/,/LINKERD_INSTALL_END/p' create-cluster.sh | sed '1d;$d'
show ""
show "# ...and Grafana, since we need to do that by head with Linkerd 2.12:"
sed -n '/GRAFANA_INSTALL_START/,/GRAFANA_INSTALL_END/p' create-cluster.sh | sed '1d;$d'
wait

clear
show "# Here's how we installed Booksapp, including mesh injection:"
sed -n '/BOOKS_INSTALL_START/,/BOOKS_INSTALL_END/p' create-cluster.sh | sed '1d;$d'
wait

clear
show "# And here's how we installed a single-replica Emissary-ingress,"
show "# including mesh injection:"
sed -n '/EMISSARY_INSTALL_START/,/EMISSARY_INSTALL_END/p' create-cluster.sh | sed '1d;$d'
show ""
show "# We had to configure Emissary for HTTP (not HTTPS!) routing too:"
sed -n '/EMISSARY_CONFIGURE_START/,/EMISSARY_CONFIGURE_END/p' create-cluster.sh | sed '1d;$d'

wait
clear

show "# At this point, things should be working. Let's start by looking at the books app"
show "# in the browser."
wait

show_browser
clear
show_terminal --nowait

show "# We can also use linkerd viz to look deeper into the books app."
pei "linkerd viz stat deploy -n booksapp"
wait 

pe "linkerd viz top deploy -n booksapp"
clear

show "# OK. Time to break everything!"
pe 'kubectl annotate ns booksapp config.linkerd.io/default-inbound-policy=deny'
wait
clear

show "# So, nothing should work now, right?"
pe "linkerd viz stat deploy -n booksapp"
wait 

show ""
show "# Huh. It's still working? Let's try the browser."
wait

show_browser
clear
show_terminal --nowait

show "# Anyone remember the gotcha that's biting us now?"
wait

show ""
show "# Right. We have to restart the pods to make our change to the"
show "# default policy take effect."
pe 'kubectl rollout restart -n booksapp deploy'
pe 'watch "kubectl get pods -n booksapp"'
clear

show "# At this point, things should not work. We'll use the browser to verify that."
wait

show_browser
clear
show_terminal --nowait

show "# OK, let's start allowing things, but minimally. First we allow linkerd-viz"
show "# and Prometheus. We start with a Server definition..."
bat manifests/booksapp/admin_server.yaml
wait

clear
show "# ...then we define an AuthorizationPolicy using MeshTLSAuthentication."
show "#"
show "# Another question as we look at this: the AuthorizationPolicy doesn't"
show "# reference the Server we just created. Why do we need it?"
bat manifests/booksapp/allow_viz.yaml
wait

clear
show "# Let's apply these."
pei "kubectl apply -f manifests/booksapp/admin_server.yaml"
pei "kubectl apply -f manifests/booksapp/allow_viz.yaml"
wait 
clear

show "# If we tap the traffic deployment, we can see that it is getting 403s."
pe "linkerd viz tap -n booksapp deploy/traffic"

clear
show "# We can also see, in the browser, that viz gets a little happier."
wait

show_browser
clear
show_terminal --nowait

show "# To really see things correctly we need to allow app traffic too. Again, we'll start"
show "# with Servers..."
wait
bat manifests/booksapp/{authors,books,webapp}_server.yaml

clear
show "# ...and continue with an AuthorizationPolicy using MeshTLSAuthentication."
bat manifests/booksapp/allow_namespace.yaml
wait

clear
show "# Another question: why don't we have a Server for the traffic generator?"
wait
show ""
show "# Right. It doesn't have any ports defined: it's outbound-only. Policy for"
show "# its traffic is managed by the defining it for the services it's trying"
show "# to talk to."
show ""
show "# So let's apply all this stuff."
pei "kubectl apply -f manifests/booksapp/authors_server.yaml"
pei "kubectl apply -f manifests/booksapp/books_server.yaml"
pei "kubectl apply -f manifests/booksapp/webapp_server.yaml"
pei "kubectl apply -f manifests/booksapp/allow_namespace.yaml"
wait 
clear

show "# At this point we should see actual traffic showing up in viz..."
# pe "linkerd viz stat deploy -n booksapp"
# wait 

pe "linkerd viz top deploy -n booksapp"

clear
show "# ...and viz should work better in the browser again too."
wait

show_browser
clear
show_terminal --nowait

show "# So far, so good. We didn't try actually using the books app from the"
show "# browser, though. Does that work?"
wait

show_browser
clear
show_terminal --nowait

show "# No. Let's fix that using route-based policy -- we definitely don't want"
show "# to allow anything from the browser to the webapp. So let's define an"
show "# HTTPRoute for the webapp that only allows what we want..."
bat manifests/booksapp/webapp_ingress_route.yaml
wait

clear
show "# ...and an AuthorizationPolicy that allows only our ingress."
bat manifests/booksapp/webapp_ingress_policy.yaml
wait

clear
show "# Let's apply these."
pei "kubectl apply -f manifests/booksapp/webapp_ingress_route.yaml"
pei "kubectl apply -f manifests/booksapp/webapp_ingress_policy.yaml"
wait

clear
show "# Oh wait. We're missing something..."
wait
show ""
show "# Right. We just broke probes, so let's re-allow them."
wait
bat manifests/booksapp/webapp_probe.yaml
clear
show "# Let's apply that too..."
pei "kubectl apply -f manifests/booksapp/webapp_probe.yaml"
wait

clear
show "# ...and now we should see the books app working in the webapp too."
wait

show_browser
clear
show_terminal --nowait

show "# That's actually working a little bit TOO well. We seem to be allowing..."
show "# everything, really. Let's take another look at that HTTPRoute -- especially"
show '# the path.'
bat manifests/booksapp/webapp_ingress_route.yaml
wait
show ""
show "# When you specify a path in an HTTPRoute, the default is for it to be a"
show "# prefix match -- and every path has a prefix of /, so we're actually allowing"
show "# literally all HTTP traffic from the ingress. That's not good."
wait

clear
show "# Instead, let's make that an exact match instead."
bat manifests/booksapp/webapp_ingress_route_2.yaml
wait
pei "kubectl apply -f manifests/booksapp/webapp_ingress_route_2.yaml"
wait
show ""
show "# OK, how is that in the browser?"
wait

show_browser
clear
show_terminal --nowait

show "# Errr. That's a little restrictive. Let's allow CSS, authors, and books as prefix"
show "# matches."
bat manifests/booksapp/webapp_ingress_route_3.yaml
wait
pei "kubectl apply -f manifests/booksapp/webapp_ingress_route_3.yaml"
wait
show ""
show "# That should be better. Hopefully. Let's check viewing and editing things this time."
wait

show_browser
clear
show_terminal --nowait

show "# So editing doesn't work; let's at least allow editing authors. One more note as"
show "# we do this: you needn't have all your routes in a single HTTPRoute. Here's a new"
show "# HTTPRoute and AuthorizationPolicy that allows editing authors (also demonstrating"
show "# regular-expression matching)."
bat manifests/booksapp/webapp_ingress_edit.yaml
wait
pei "kubectl apply -f manifests/booksapp/webapp_ingress_edit.yaml"
wait
show ""
show "# At this point, editing authors should work, but editing books should still fail."
wait

show_browser
clear
show_terminal --nowait

show "# Finally, at this point things are a bit complex. We can use 'linkerd viz authz'"
show "# to see all the authorization policies that affect our webapp, for example."
pe "linkerd viz authz -n booksapp deploy/webapp"
show ""
show "# Note that you actually have to use HTTPRoutes and AuthorizationPolicies before"
show "# they'll show up here."

wait
clear
show "# Homework, should you choose to accept it:"
show "# - Allow editing books too!"
show "# - Add route-based policy to the authors and books services too -- right now,"
show "#   they're blindly trusting the ingress to protect them, and they needn't."
wait

show_slides --nowait

#!/bin/bash

# set -e

# This show_* stuff allows using environment variable hooks to
# control what's shown when livecasting the demo. If you don't
# set the environment variables, they'll be noops.

#!hook show_terminal TERMINAL
#!hook show_browser BROWSER
#!hook show_video VIDEO
#!hook show_slides SLIDES

## #!macro browser_then_terminal
## #!  #@wait
## #!  #@show_browser
## #!  #@wait
## #!  #@clear
## #!  #@show_terminal
## #!end

#!macro wait_clear
#!  #@wait
#!  #@echo clear
#!end

show_slides

clear
echo Waiting...

## #@wait_clear
#@wait
#@clear
show_terminal

#@SHOW

## Show basics about the cluster.
# We already have a cluster set up. Let's look at it.
kubectl get nodes

kubectl get ns | sort
## wait_clear
#@wait
#@clear

## Show how we installed things.
# Here's how we installed Linkerd:

#@immed
sed -n '/LINKERD_INSTALL_START/,/LINKERD_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'

# ...and Grafana, since we need to do that by head with Linkerd 2.12:

#@immed
sed -n '/GRAFANA_INSTALL_START/,/GRAFANA_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'

#@wait
#@clear
# Here's how we installed Booksapp, including mesh injection:

#@immed
sed -n '/BOOKS_INSTALL_START/,/BOOKS_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'

#@wait
#@clear
# And here's how we installed a single-replica Emissary-ingress,
# including mesh injection:

#@immed
sed -n '/EMISSARY_INSTALL_START/,/EMISSARY_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'

# We had to configure Emissary for HTTP (not HTTPS!) routing too:

#@immed
sed -n '/EMISSARY_CONFIGURE_START/,/EMISSARY_CONFIGURE_END/p' setup-cluster.sh | sed '1d;$d'

#@wait
#@clear
# At this point, things should be working. Let's start by looking at the books app
# in the browser.
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# We can also use linkerd viz to look deeper into the books app.
# 
# linkerd viz stat shows stats.
linkerd viz stat deploy -n booksapp
#@wait 

# linkerd viz top shows the most common calls.
linkerd viz top deploy -n booksapp
#@clear

# OK. Time to break everything!
kubectl annotate ns booksapp config.linkerd.io/default-inbound-policy=deny

#@wait
#@clear
# So, nothing should work now, right?
linkerd viz stat deploy -n booksapp
#@wait 

#@echo
# Huh. It's still working? Let's try the browser.
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# Anyone remember the gotcha that's biting us now?
#@wait

#@echo
# Right. We have to restart the pods to make our change to the default
# policy take effect.
kubectl rollout restart -n booksapp deploy
watch "kubectl get pods -n booksapp"
#@clear

# At this point, things should not work. We'll use the browser to verify that
# (both by trying the app, and by looking at viz for the booksapp namespace).
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# OK, let's start allowing things, but minimally. First we allow linkerd-viz
# and Prometheus. We start with a Server definition...
bat manifests/booksapp/admin_server.yaml

#@wait
#@clear
# ...then we define an AuthorizationPolicy using MeshTLSAuthentication.
#
# Another question as we look at this: the AuthorizationPolicy doesn't
# reference the Server we just created. Why do we need it?
bat manifests/booksapp/allow_viz.yaml

#@wait
#@clear
# Let's apply these.
kubectl apply -f manifests/booksapp/admin_server.yaml
kubectl apply -f manifests/booksapp/allow_viz.yaml
#@wait
#@clear

#@SHOW

# If we tap the traffic deployment, we can see that it is getting 403s.
##@failok
linkerd viz tap -n booksapp deploy/traffic

#@clear
# We can also see, in the browser, that viz gets a little happier.
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# To really see things correctly we need to allow app traffic too. Again, we'll start
# with Servers...
#@wait
bat manifests/booksapp/{authors,books,webapp}_server.yaml

#@clear
# ...and continue with an AuthorizationPolicy using MeshTLSAuthentication.
bat manifests/booksapp/allow_namespace.yaml

#@wait
#@clear
# Another question: why don't we have a Server for the traffic generator?
#@wait
#@echo
# Right. It doesn't have any ports defined: it's outbound-only. Policy for
# its traffic is managed by the defining it for the services it's trying
# to talk to.

# So let's apply all this stuff.
kubectl apply -f manifests/booksapp/authors_server.yaml
kubectl apply -f manifests/booksapp/books_server.yaml
kubectl apply -f manifests/booksapp/webapp_server.yaml
kubectl apply -f manifests/booksapp/allow_namespace.yaml
#@wait 
#@clear

# At this point we should see actual traffic showing up in viz...
## linkerd viz stat deploy -n booksapp
## wait 

linkerd viz top deploy -n booksapp

#@clear
# ...and viz should work better in the browser again too.
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# So far, so good. We didn't try actually using the books app from the
# browser, though. Does that work?
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# No. Let's fix that using route-based policy -- we definitely don't want
# to allow any random thing that the browser might send to actually get
# to the webapp. So let's define an HTTPRoute for the webapp that only
# allows what we want...
bat manifests/booksapp/webapp_ingress_route.yaml

#@wait
#@clear
# ...and an AuthorizationPolicy that allows only our ingress.
bat manifests/booksapp/webapp_ingress_policy.yaml

#@wait
#@clear
# Let's apply these.
kubectl apply -f manifests/booksapp/webapp_ingress_route.yaml
kubectl apply -f manifests/booksapp/webapp_ingress_policy.yaml

#@wait
#@clear
# Oh wait. We're missing something...
#@wait
#@echo
# Right. We just broke probes, so let's re-allow them.
#@wait
bat manifests/booksapp/webapp_probe.yaml
#@clear
# Let's apply that too...
kubectl apply -f manifests/booksapp/webapp_probe.yaml

#@wait
#@clear
# ...and now we should see the books app working in the webapp too.
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# That's actually working a little bit TOO well. We seem to be allowing...
# everything, really. Let's take another look at that HTTPRoute -- especially
# the path.
bat manifests/booksapp/webapp_ingress_route.yaml
#@wait

# When you specify a path in an HTTPRoute, the default is for it to be a
# prefix match -- and every path has a prefix of /, so we're actually allowing
# literally all HTTP traffic from the ingress. That's not good.

#@wait
#@clear
# Instead, let's make that an exact match instead.
bat manifests/booksapp/webapp_ingress_route_2.yaml
#@wait
kubectl apply -f manifests/booksapp/webapp_ingress_route_2.yaml
#@wait

# OK, how is that in the browser?
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# Errr. That's a little restrictive. Let's allow CSS, authors, and books as prefix
# matches.
bat manifests/booksapp/webapp_ingress_route_3.yaml
#@wait
kubectl apply -f manifests/booksapp/webapp_ingress_route_3.yaml
#@wait

# That should be better. Hopefully. Let's check viewing and editing things this time.
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# So editing doesn't work; let's at least allow editing authors. One more note as
# we do this: you needn't have all your routes in a single HTTPRoute. Here's a new
# HTTPRoute and AuthorizationPolicy that allows editing authors (also demonstrating
# regular-expression matching).
bat manifests/booksapp/webapp_ingress_edit.yaml
#@wait
kubectl apply -f manifests/booksapp/webapp_ingress_edit.yaml
#@wait

# At this point, editing authors should work, but editing books should still fail.
#@wait
#@show_browser
#@wait
#@clear
#@show_terminal

# Finally, at this point things are a bit complex. We can use 'linkerd viz authz'
# to see all the authorization policies that affect our webapp, for example.
linkerd viz authz -n booksapp deploy/webapp
#@echo
# Note that you actually have to use HTTPRoutes and AuthorizationPolicies before
# they'll show up here.

#@wait
#@clear
# Homework, should you choose to accept it:
# - Allow editing books too!
# - Add route-based policy to the authors and books services too -- right now,
#   they're blindly trusting the ingress to protect them, and they needn't.
#@wait

#@show_slides

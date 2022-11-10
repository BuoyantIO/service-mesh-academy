#!/bin/bash

# set -e

# All the #@ comments are instructions to the "dsh" shell runner
# (https://github.com/kflynn/dsh/ for now). You can run this
# script with bash and it will work, but running it with dsh is
# much more interactive as you follow along.
#
# IMPORTANT: when running dsh, to quit, type capital Q while it's
# waiting for you to hit ENTER to continue.
#
# First up: import the macros and such that we use for livestreaming.
#@import dsh-start.sh

# After that, let's get this show on the road. The #@SHOW directive
# tells dsh to start actually displaying comments and running commands
# interactively. So comments after this (as long as they don't start
# with ##) will be shown to the user during the presentation.

#@SHOW

# We already have a cluster set up. Let's look at it.
kubectl get nodes

kubectl get ns | sort
#@wait_clear

# Here's how we installed Linkerd:

#@immed
sed -n '/LINKERD_INSTALL_START/,/LINKERD_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'

# ...and Grafana, since we need to do that by head with Linkerd 2.12:

#@immed
sed -n '/GRAFANA_INSTALL_START/,/GRAFANA_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'

#@wait_clear
# Here's how we installed Booksapp, including mesh injection:

#@immed
sed -n '/BOOKS_INSTALL_START/,/BOOKS_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'

#@wait_clear
# And here's how we installed a single-replica Emissary-ingress,
# including mesh injection:

#@immed
sed -n '/EMISSARY_INSTALL_START/,/EMISSARY_INSTALL_END/p' setup-cluster.sh | sed '1d;$d'

# We had to configure Emissary for HTTP (not HTTPS!) routing too:

#@immed
sed -n '/EMISSARY_CONFIGURE_START/,/EMISSARY_CONFIGURE_END/p' setup-cluster.sh | sed '1d;$d'

#@wait_clear
# At this point, things should be working. Let's start by looking at the books app
# in the browser.

#@browser_then_terminal

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

#@wait_clear
# So, nothing should work now, right?
linkerd viz stat deploy -n booksapp

#@wait 

# Huh. It's still working? Let's try the browser.
#@browser_then_terminal
# Anyone remember the gotcha that's biting us now?
#@wait

# Right. We have to restart the pods to make our change to the default
# policy take effect.
kubectl rollout restart -n booksapp deploy
watch "kubectl get pods -n booksapp"
#@clear

# At this point, things should not work. We'll use the browser to verify that
# (both by trying the app, and by looking at viz for the booksapp namespace).
#@browser_then_terminal
# OK, let's start allowing things, but minimally. First we allow linkerd-viz
# and Prometheus. We start with a Server definition...
bat manifests/booksapp/admin_server.yaml

#@wait_clear
# ...then we define an AuthorizationPolicy using MeshTLSAuthentication.
#
# Another question as we look at this: the AuthorizationPolicy doesn't
# reference the Server we just created. Why do we need it?
bat manifests/booksapp/allow_viz.yaml

#@wait_clear
# Let's apply these.
kubectl apply -f manifests/booksapp/admin_server.yaml
kubectl apply -f manifests/booksapp/allow_viz.yaml
#@wait_clear

#@SHOW

# If we tap the traffic deployment, we can see that it is getting 403s.
##@failok
linkerd viz tap -n booksapp deploy/traffic

#@clear
# We can also see, in the browser, that viz gets a little happier.
#@browser_then_terminal
# To really see things correctly we need to allow app traffic too. Again, we'll start
# with Servers...
#@wait
bat manifests/booksapp/{authors,books,webapp}_server.yaml

#@clear
# ...and continue with an AuthorizationPolicy using MeshTLSAuthentication.
bat manifests/booksapp/allow_namespace.yaml

#@wait_clear
# Another question: why don't we have a Server for the traffic generator?
#@wait

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
#@browser_then_terminal
# So far, so good. We didn't try actually using the books app from the
# browser, though. Does that work?
#@browser_then_terminal
# No. Let's fix that using route-based policy -- we definitely don't want
# to allow any random thing that the browser might send to actually get
# to the webapp. So let's define an HTTPRoute for the webapp that only
# allows what we want...
bat manifests/booksapp/webapp_ingress_route.yaml

#@wait_clear
# ...and an AuthorizationPolicy that allows only our ingress.
bat manifests/booksapp/webapp_ingress_policy.yaml

#@wait_clear
# Let's apply these.
kubectl apply -f manifests/booksapp/webapp_ingress_route.yaml
kubectl apply -f manifests/booksapp/webapp_ingress_policy.yaml

#@wait_clear
# Oh wait. We're missing something...
#@wait

# Right. We just broke probes, so let's re-allow them.
#@wait
bat manifests/booksapp/webapp_probe.yaml
#@clear
# Let's apply that too...
kubectl apply -f manifests/booksapp/webapp_probe.yaml

#@wait_clear
# ...and now we should see the books app working in the webapp too.
#@browser_then_terminal
# That's actually working a little bit TOO well. We seem to be allowing...
# everything, really. Let's take another look at that HTTPRoute -- especially
# the path.
bat manifests/booksapp/webapp_ingress_route.yaml
#@wait

# When you specify a path in an HTTPRoute, the default is for it to be a
# prefix match -- and every path has a prefix of /, so we're actually allowing
# literally all HTTP traffic from the ingress. That's not good.

#@wait_clear
# Instead, let's make that an exact match instead.
bat manifests/booksapp/webapp_ingress_route_2.yaml
#@wait
kubectl apply -f manifests/booksapp/webapp_ingress_route_2.yaml
#@wait

# OK, how is that in the browser?
#@browser_then_terminal
# Errr. That's a little restrictive. Let's allow CSS, authors, and books as prefix
# matches.
bat manifests/booksapp/webapp_ingress_route_3.yaml
#@wait
kubectl apply -f manifests/booksapp/webapp_ingress_route_3.yaml
#@wait

# That should be better. Hopefully. Let's check viewing and editing things this time.
#@browser_then_terminal
# So editing doesn't work; let's at least allow editing authors. One more note as
# we do this: you needn't have all your routes in a single HTTPRoute. Here's a new
# HTTPRoute and AuthorizationPolicy that allows editing authors (also demonstrating
# regular-expression matching).
bat manifests/booksapp/webapp_ingress_edit.yaml
#@wait
kubectl apply -f manifests/booksapp/webapp_ingress_edit.yaml
#@wait

# At this point, editing authors should work, but editing books should still fail.
#@browser_then_terminal
# Finally, at this point things are a bit complex. We can use 'linkerd viz authz'
# to see all the authorization policies that affect our webapp, for example.
linkerd viz authz -n booksapp deploy/webapp

# Note that you actually have to use HTTPRoutes and AuthorizationPolicies before
# they'll show up here.

#@wait_clear
# Homework, should you choose to accept it:
# - Allow editing books too!
# - Add route-based policy to the authors and books services too -- right now,
#   they're blindly trusting the ingress to protect them, and they needn't.
#@wait

#@show_slides

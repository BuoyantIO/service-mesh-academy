alias k=kubectl

########################
## Multicluster Setup ##
########################

# In west
#########
k config use-context west
# Install emojivoto
k apply -f https://run.linkerd.io/emojivoto.yml
# Check it's working
k -n emojivoto port-forward svc/web-svc 8080:80
# Delete all but vote-bot
k -n emojivoto delete deploy voting web emoji
# Install linkerd and the viz and multicluster extensions
linkerd install | k apply -f -
linkerd viz install | k apply -f -
linkerd mc install | k apply -f -
# Get the trust-root
k -n linkerd get cm linkerd-identity-trust-roots -oyaml > west-root.crt
vim west-root.crt
# Create certs for east
step certificate create root.linkerd.cluster.local root.crt root.key --profile root-ca --no-password --insecure
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key --profile intermediate-ca --not-after 8760h --no-password --insecure --ca root.crt --ca-key root.key
cat west-root.crt root.crt > bundle.crt
# Upgrade linkerd with bundled root
linkerd upgrade --identity-trust-anchors-file=./bundle.crt | k apply -f -

# In east
#########
k config use-context east
# Install linkerd and the multicluster extension, inject emojivoto
linkerd install \
  --identity-trust-anchors-file bundle.crt \
  --identity-issuer-certificate-file issuer.crt \
  --identity-issuer-key-file issuer.key | \
  k apply -f -
linkerd mc install | k apply -f -
linkerd inject https://run.linkerd.io/emojivoto.yml | k apply -f -
# Check LB and the gateway auth
k -n linkerd-multicluster get svc
k -n linkerd-multicluster get serverauthorizations.policy.linkerd.io  linkerd-gateway -oyaml
# Delete vote-bot and export web
k -n emojivoto delete deploy vote-bot
k -n emojivoto label svc web-svc mirror.linkerd.io/exported=true
# Create link
linkerd mc link --cluster-name east > link.yml
vim link.yml
# Check the token used for connecting to east's kube-api service
k -n linkerd-multicluster get secret
# we can also use this to add more service accounts
linkerd mc allow

# In west
#########
k config use-context west
# Apply link and check multicluster connection, new service and endpoint
k apply -f link.yml
# Check the cluster-credentials-east secret
k -n linkerd-multicluster get secret cluster-credentials-east -ojson | jq .data.kubeconfig | tr -d '"' | base64 -d
# Check the connection between clusters was established
linkerd mc gateways
k -n emojivoto get svc
k -n emojivoto get ep
# Vote-bot can't yet reach east
k -n emojivoto logs -f vote-bot-xxx vote-bot
# Create curl deployment for tests
k create deployment curl --image curlimages/curl
# Add this for the pod to continue running:
# command: [ "/bin/sh", "-c", "--" ]
# args: [ "sleep infinity" ]
k edit deploy curl
# Attempt connecting to the gateway from outside the mesh
k exec -ti curl-8468dbf5fd-tp4wj sh
curl http://web-svc-east.emojivoto.svc.cluster.local
# In a separate window, check the connection denial on east
k --context east -n linkerd-multicluster logs -f linkerd-gateway-6c4658f9d8-5fjm8 linkerd-proxy
# Inject curl and try again
k get deploy curl -oyaml | linkerd inject - | k apply -f -
k exec -ti curl-xxx -c curl sh
curl http://web-svc-east.emojivoto.svc.cluster.local
# Edit vote-bot to inject and change WEB_HOST, and then check logs again
k -n emojivoto edit deploy vote-bot
k -n emojivoto logs -f vote-bot-xxx vote-bot

##############
## Failover ##
##############

# Reinstall emojivoto
linkerd inject https://run.linkerd.io/emojivoto.yml | k apply -f -
# Install the linkerd-smi extension (ONLY REQUIRED IF RUNNING 2.12!)
helm repo add linkerd-smi https://linkerd.github.io/linkerd-smi
helm repo up
helm install linkerd-smi -n linkerd-smi --create-namespace linkerd-smi/linkerd-smi
# Install traffic-split resource and tail the web-svc log in both clusters
vim traffic-split.yml
k apply -f traffic-split.yml
k -n emojivoto logs -f voting-xxx voting-svc
k --context east -n emojivoto logs -f voting-xxx voting-svc
# Switch all traffic to east
k -n emojivoto edit ts web-svc
# Switch all traffic back to west
k -n emojivoto edit ts web-svc
# Install the linkerd-failover extension
helm repo add linkerd-edge https://helm.linkerd.io/edge
helm repo up
helm install linkerd-failover -n linkerd-failover --create-namespace --devel linkerd-edge/linkerd-failover
# Scale down web-svc on west
k -n emojivoto scale --replicas 0 deploy web
# Check changes on the traffic-split
k -n emojivoto get ts web-svc -oyaml
# Scale back web-svc on west
k -n emojivoto scale --replicas 1 deploy web
# Check changes on the traffic-split
k -n emojivoto get ts web-svc -oyaml

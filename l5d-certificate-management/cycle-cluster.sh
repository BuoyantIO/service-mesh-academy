k3d cluster delete certs
k3d cluster create certs \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
    --k3s-arg '--no-deploy=traefik@server:*;agents:*'
kubectl ns default

docker network create kind \
    --subnet "192.168.155.0/24" \
    --gateway "192.168.155.1" \
    --subnet "fc00:f853:ccd:e793::/64" \
    -o "com.docker.network.bridge.enable_ip_masquerade=true" \
    -o "com.docker.network.driver.mtu=1500"

set -x

ctlptl delete -f clusters.yaml
docker network rm kind egress

#!python

import yaml
import base64

ca_crt = open('certs/ca.crt').read()
issuer_crt = open('certs/issuer.crt').read()
issuer_key = open('certs/issuer.key').read()

secret = {
    'apiVersion': 'v1',
    'kind': 'Secret',
    'metadata': {
        'name': 'linkerd-identity-issuer',
        'namespace': 'linkerd',
    },
    'type': 'kubernetes.io/tls',
    'data': {
        'ca.crt': base64.b64encode(ca_crt.encode()).decode(),
        'tls.crt': base64.b64encode(issuer_crt.encode()).decode(),
        'tls.key': base64.b64encode(issuer_key.encode()).decode(),
    },
}

print("---")
print(yaml.safe_dump(secret, default_flow_style=False))

#!python

import sys

import yaml
import os

# This madness is how you force PyYAML to be polite about multiline strings.
yaml.SafeDumper.org_represent_str = yaml.SafeDumper.represent_str

def repr_str(dumper, data):
    if '\n' in data:
        return dumper.represent_scalar(u'tag:yaml.org,2002:str', data, style='|')
    return dumper.org_represent_str(data)

yaml.add_representer(str, repr_str, Dumper=yaml.SafeDumper)

VERSION=sys.argv[1]

if not VERSION:
    sys.stderr.write("Usage: %s linkerd-version\n" % sys.argv[0])
    sys.stderr.write("Example: %s enterprise-2.15.2\n" % sys.argv[0])
    sys.exit(1)

ca_crt = open('certs/ca.crt').read()

control_plane = {
    'apiVersion': 'linkerd.buoyant.io/v1alpha1',
    'kind': 'ControlPlane',
    'metadata': {
        'name': 'linkerd-control-plane',
    },
    'spec': {
        'components': {
            'linkerd': {
                'version': VERSION,
                'license': os.environ["BUOYANT_LICENSE"],
                'controlPlaneConfig': {
                    'proxy': {
                        'image': {
                            'version': VERSION,
                        },
                    },
                    'identityTrustAnchorsPEM': ca_crt,
                    'identity': {
                        'issuer': {
                            'scheme': 'kubernetes.io/tls',
                        },
                    },
                },
            },
        },
    },
}

print("---")
print(yaml.safe_dump(control_plane, default_flow_style=False))

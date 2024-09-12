import sys

import os
import json
import yaml

config = json.load(sys.stdin)

if (not config or
    not config[0] or
    not config[0].get('IPAM') or
    not config[0]['IPAM'].get('Config')):
    sys.stderr.write("No IPAM configuration found in docker inspect output\n")
    sys.exit(1)

v4_ranges = []
v6_ranges = []
dual_ranges = []

for config in config[0]['IPAM']['Config']:
    subnet = config.get('Subnet')

    if not subnet:
        sys.stderr.write(f"No subnet found in IPAM configuration {config}\n")
        sys.exit(1)

    address, bits = subnet.split('/')
    bits = int(bits)

    if address.endswith("::"):
        # IPv6
        if bits < 64:
            sys.stderr.write(f"Subnet {subnet} is too small for IPv6\n")
            sys.exit(1)

        # Choose two /96 ranges, one for our v6-only cluster and one for
        # our dualstack cluster.
        base = address[:-1]

        v6_ranges.append(f"{base}6::/96")
        dual_ranges.append(f"{base}10::/96")
    elif address.endswith(".0"):
        # IPv4
        if bits < 24:
            sys.stderr.write(f"Subnet {subnet} is too small for IPv4\n")
            sys.exit(1)

        base = address[:-1]  # Pull off the 0

        v4_ranges.append(f"{base}64/28")    # 0x40
        dual_ranges.append(f"{base}160/28")  # 0xA0
    else:
        sys.stderr.write(f"Unknown subnet format {subnet}\n")
        sys.exit(1)

for file, ranges in [
    ( "sma-v4/metallb.yaml", v4_ranges ),
    ( "sma-v6/metallb.yaml", v6_ranges ),
    ( "sma-dual/metallb.yaml", dual_ranges ),
]:
    config_in = yaml.safe_load_all(open(file).read())
    config_out = []

    for doc in config_in:
        if doc.get('kind') == 'IPAddressPool':
            doc['spec']['addresses'] = ranges

        config_out.append(doc)

    try:
        with open(file, 'w') as f:
            yaml.dump_all(config_out, f)
    except Exception as e:
        sys.stderr.write(f"Failed to write {file}: {e}\n")

    print(f"{os.path.dirname(file)}:")
    print("- " + "\n- ".join(ranges) + "\n")

import sys

import json
import subprocess
import argparse

def get_node_info(ctx):
    nodename = f"{ctx}-control-plane"

    command = ["kubectl", "--context", ctx, "get", "node", nodename, "-o", "json"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    output = process.communicate()

    if process.returncode != 0:
        print(f"Error: {output[1].decode().strip()}")
        sys.exit(1)

    return json.loads(output[0].decode())

parser = argparse.ArgumentParser(description='Get node information')
group = parser.add_mutually_exclusive_group(required=True)
group.add_argument('--cidr', action='store_true', help='CIDR')
group.add_argument('--nodeip', action='store_true', help='Node IP')
group = parser.add_mutually_exclusive_group(required=True)
group.add_argument('--v4', action='store_true', help='IPv4')
group.add_argument('--v6', action='store_true', help='IPv6')
parser.add_argument('context', help='Context', type=str)
args = parser.parse_args()

info = get_node_info(args.context)

if args.cidr:
    cidrs = info['spec']['podCIDRs']

    for cidr in cidrs:
        if args.v4 and '.' in cidr:
            print(cidr)
        elif args.v6 and ':' in cidr:
            print(cidr)
elif args.nodeip:
    nodeip = info['status']['addresses']

    for address in nodeip:
        if address['type'] == 'InternalIP':
            nodeip = address['address']

            if args.v4 and '.' in nodeip:
                print(nodeip)
            elif args.v6 and ':' in nodeip:
                print(nodeip)

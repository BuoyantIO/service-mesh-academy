#!/usr/bin/env python

import sys

import subprocess
import os
import time

def collect_metrics():
    command = ["linkerd", "dg", "proxy-metrics", "-n", "faces", "deploy/face"]
    result = subprocess.run(command, capture_output=True, text=True)
    lines = result.stdout.splitlines()

    print(len(lines))

    http_metrics = []
    grpc_metrics = []

    for line in lines:
        if line.startswith("outbound_http_route_request_statuses_total"):
            metrics = parse_metrics(line)
            metrics["metric_type"] = "HTTP"
            http_metrics.append(metrics)
        elif line.startswith("outbound_grpc_route_request_statuses_total"):
            metrics = parse_metrics(line)
            metrics["metric_type"] = "GRPC"
            grpc_metrics.append(metrics)

    return http_metrics, grpc_metrics


def parse_metrics(line):
    metrics = {}

    count = int(line.split()[-1])
    metrics["count"] = count

    parts = line.strip().split("{", 1)[1].rsplit("}", 1)[0].split(",")

    for part in parts:
        key, value = part.split("=")
        metrics[key] = value.strip('"').strip()

    return metrics

counts = {}
last = {}
lastavg = {}

def output(dest, route, count, time_per_sample):
    output_line = f"\033[90m---.--  {dest} {route}\033[0m"

    key = f"{dest} {route}"

    if key not in last:
        last[key] = count
    else:
        # We have a last value. Put the delta between this value and the last
        # value in counts.

        if key not in counts:
            counts[key] = []

        counts[key].append(count - last[key])
        last[key] = count

        while len(counts[key]) > 10:
            counts[key].pop(0)

        average = sum(counts[key]) / float(len(counts[key]) * time_per_sample)
        lastavg[key] = average

        color = "\033[90m"

        output_line = f"{color} 0.00/s {dest} via {route}\033[0m"

        if (key not in lastavg) or (average > 0.01):
            if not (("OK" in key) or ("200" in key)):
                color = "\033[91m"
            else:
                color = "\033[92m"

            output_line = f"{average:5.2f}/s {color}{dest}\033[0m via {route}"

    print(output_line)
    # print(f"count:   {count}")
    # print(f"counts:  {counts.get(key, [])}")
    # print(f"last:    {last[key]}")
    # print(f"avg:     ---.--")
    # print(f"lastavg: {lastavg.get(key, '---.--')}")

time_per_sample = 5

while True:
    http_metrics, grpc_metrics = collect_metrics()

    os.system("clear")
    os.system("date")
    print()

    metric_count = 0

    for metric in http_metrics:
        count = metric["count"]
        hostname = metric["hostname"]
        http_status = metric["http_status"]
        route_name = metric["route_name"]
        parent_port = metric["parent_port"]
        error = metric["error"]

        errstr = f" ({error})" if error else ""

        dest = f"HTTP: {hostname} {http_status}"
        route = f"{route_name} {parent_port}{errstr}"

        metric_count += 1
        output(dest, route, count, time_per_sample)
        # break

    for metric in grpc_metrics:
        count = metric["count"]
        hostname = metric["hostname"]
        grpc_status = metric["grpc_status"]
        route_name = metric["route_name"]
        parent_port = metric["parent_port"]
        error = metric["error"]

        errstr = f" ({error})" if error else ""

        dest = f"gRPC: {hostname} {grpc_status}"
        route = f"{route_name} {parent_port}{errstr}"

        metric_count += 1
        output(dest, route, count, time_per_sample)
        # break

    if metric_count == 0:
        print("No egress metrics found.")

    time.sleep(time_per_sample)
    # _ = sys.stdin.readline()

# # HELP outbound_http_route_request_statuses Completed request-response streams.
# # TYPE outbound_http_route_request_statuses counter
# outbound_http_route_request_statuses_total{parent_group="",parent_kind="default",parent_namespace="",parent_name="egress-fallback",parent_port="",parent_section_name="",route_group="",route_kind="default",route_namespace="",route_name="egress-fallback",hostname="smiley",http_status="200",error=""} 8182
# outbound_http_route_request_statuses_total{parent_group="",parent_kind="default",parent_namespace="",parent_name="egress-fallback",parent_port="",parent_section_name="",route_group="",route_kind="default",route_namespace="",route_name="egress-fallback",hostname="color",http_status="200",error=""} 8200
# outbound_http_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="80",parent_section_name="",route_group="",route_kind="default",route_namespace="",route_name="http-egress-deny",hostname="smiley",http_status="403",error=""} 22
# outbound_http_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="80",parent_section_name="",route_group="gateway.networking.k8s.io",route_kind="HTTPRoute",route_namespace="faces",route_name="allow-smiley-center",hostname="smiley",http_status="200",error=""} 416
# outbound_http_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="80",parent_section_name="",route_group="gateway.networking.k8s.io",route_kind="HTTPRoute",route_namespace="faces",route_name="allow-smiley-center",hostname="smiley",http_status="",error="FAIL_FAST"} 4
# outbound_http_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="80",parent_section_name="",route_group="gateway.networking.k8s.io",route_kind="HTTPRoute",route_namespace="faces",route_name="allow-smiley",hostname="smiley",http_status="200",error=""} 1423
# outbound_http_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="80",parent_section_name="",route_group="gateway.networking.k8s.io",route_kind="HTTPRoute",route_namespace="faces",route_name="allow-smiley-center",hostname="smiley",http_status="",error="LOAD_SHED"} 28
# # HELP outbound_grpc_route_request_statuses Completed request-response streams.
# # TYPE outbound_grpc_route_request_statuses counter
# outbound_grpc_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="8000",parent_section_name="",route_group="",route_kind="default",route_namespace="",route_name="grpc-egress-deny",hostname="color",grpc_status="PERMISSION_DENIED",error=""} 22
# outbound_grpc_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="8000",parent_section_name="",route_group="gateway.networking.k8s.io",route_kind="GRPCRoute",route_namespace="faces",route_name="allow-color-center",hostname="color",grpc_status="OK",error=""} 416
# outbound_grpc_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="8000",parent_section_name="",route_group="gateway.networking.k8s.io",route_kind="GRPCRoute",route_namespace="faces",route_name="allow-color-center",hostname="color",grpc_status="UNKNOWN",error="FAIL_FAST"} 4
# outbound_grpc_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="8000",parent_section_name="",route_group="gateway.networking.k8s.io",route_kind="GRPCRoute",route_namespace="faces",route_name="allow-color",hostname="color",grpc_status="OK",error=""} 1423
# outbound_grpc_route_request_statuses_total{parent_group="policy.linkerd.io",parent_kind="EgressNetwork",parent_namespace="linkerd-egress",parent_name="all-egress",parent_port="8000",parent_section_name="",route_group="gateway.networking.k8s.io",route_kind="GRPCRoute",route_namespace="faces",route_name="allow-color-center",hostname="color",grpc_status="UNKNOWN",error="LOAD_SHED"} 28
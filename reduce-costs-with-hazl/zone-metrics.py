import sys

import re
import subprocess
import time

from collections import defaultdict

RED = "\033[31m"
GREEN = "\033[32m"
GREY = "\033[90m"
RESET = "\033[0m"

# Here are some example lines:
# request_total{direction="outbound",authority="color.faces.svc.cluster.local",target_addr="10.42.1.10:8000",target_ip="10.42.1.10",target_port="8000",tls="true",server_id="default.faces.serviceaccount.identity.linkerd.cluster.local",dst_control_plane_ns="linkerd",dst_deployment="color-west",dst_namespace="faces",dst_pod="color-west-5f98568cc-t6zt7",dst_pod_template_hash="5f98568cc",dst_service="color",dst_serviceaccount="default",dst_zone="zone-west"} 963
# outbound_http_balancer_adaptive_load_average{parent_group="core",parent_kind="Service",parent_namespace="faces",parent_name="smiley",parent_port="80",parent_section_name="",backend_group="core",backend_kind="Service",backend_namespace="faces",backend_name="smiley",backend_port="80",backend_section_name=""} 1.4595755706605527

interesting_metrics = [
    "request_total",
    "outbound_http_balancer_adaptive_load_average",
    "outbound_http_balancer_adaptive_load_band_low",
    "outbound_http_balancer_adaptive_load_band_high",
]

reInterestingMetric = re.compile(r"(" + "|".join(interesting_metrics) + r"){([^}]+)} (\d+(\.\d+)?)$")


class Load:
    def __init__(self, average, low, high):
        self.average = average
        self.low = low
        self.high = high

    def __str__(self):
        elements = []

        if self.low is not None:
            elements.append("%.2f <" % self.low)

        elements.append("%.2f" % self.average)

        if self.high is not None:
            elements.append("< %.2f" % self.high)

        return " ".join(elements)

    def __truediv__(self, scalar):
        return Load(
            self.average / scalar if self.average is not None else None,
            self.low / scalar if self.low is not None else None,
            self.high / scalar if self.high is not None else None,
        )

def parse_labels(label_str):
    labels = {}

    for item in label_str.split(','):
        if '=' in item:
            k, v = item.split('=', 1)
            labels[k.strip()] = v.strip().strip('"')

    return labels

def get_metrics(context=None):
    try:
        cmd = [ "linkerd" ]

        if context:
            cmd.extend(["--context", context])

        cmd.extend(["diagnostics", "proxy-metrics", "-n", "faces", "deploy/face"])
        output = subprocess.check_output(cmd, text=True)
    except subprocess.CalledProcessError as e:
        print("Error running linkerd:", e)
        return []

    metrics = defaultdict(lambda: defaultdict(dict))

    for line in output.splitlines():
        if line.startswith("#") or not line.strip():
            continue

        matches = reInterestingMetric.match(line)

        if not matches:
            continue

        metric_name, label_string, value_string, _ = matches.groups()
        metric_name = metric_name.strip()
        labels = parse_labels(label_string)

        if metric_name == "request_total":
            # Traffic stats and routing info
            direction = labels.get("direction", "")
            tls = labels.get("tls", "")

            if (direction != "outbound") or (not tls):
                continue

            dst_pod = labels.get("dst_pod", "")
            dst_zone = labels.get("dst_zone", "")

            workload = "unknown"

            if dst_pod and dst_zone:
                if dst_pod.startswith("color-"):
                    workload = "color"
                elif dst_pod.startswith("smiley-"):
                    workload = "smiley"

            workload_metrics = metrics[workload]
            zone_metrics = workload_metrics[dst_zone]
            total_metrics = workload_metrics["total"]

            value = int(value_string.strip())

            # Kludge
            if "total" not in total_metrics:
                total_metrics["total"] = 0

            total_metrics["total"] += value

            if dst_pod not in zone_metrics:
                zone_metrics[dst_pod] = 0

            zone_metrics[dst_pod] += value
        else:
            # print(line)
            value = float(value_string.strip())

            # HAZL load info
            workload = labels.get("parent_name", "unknown")
            workload_metrics = metrics[workload]

            which = metric_name[len("outbound_http_balancer_adaptive_load_"):]
            # print(f"{which}: {value}")

            workload_metrics["load"][which] = value

    return metrics

def print_metrics(metrics, prev_metrics, grey_count):
    for workload in sorted(metrics.keys()):
        workload_metrics = metrics[workload]
        prev_workload_metrics = prev_metrics.get(workload, {})
        total = workload_metrics.get("total", {}).get("total", 0)
        prev_total = prev_workload_metrics.get("total", {}).get("total", 0)

        delta_total = total - prev_total

        output_lines = []
        active_endpoints = 0

        for zone in sorted(workload_metrics.keys()):
            if (zone == "total") or (zone == "load"):
                continue

            prev_for_zone = prev_workload_metrics.get(zone, {})

            for pod in sorted(workload_metrics[zone].keys()):
                line_key = f"{workload}:{zone}:{pod}"

                if pod not in prev_for_zone:
                    output_lines.append("%s    %8s -> %-32s%s" % (GREEN, zone, pod, RESET))
                    grey_count[line_key] = 0
                    continue

                prev_count = prev_for_zone.get(pod, 0)
                current_count = workload_metrics[zone][pod]
                diff = current_count - prev_count

                if diff != 0:
                    diff_pct = (diff / delta_total * 100) if delta_total >= 0 else 0
                    output_lines.append("    %8s -> %-32s %8d (%3d%%)" % (zone, pod, diff, diff_pct))
                    grey_count[line_key] = 0
                    active_endpoints += 1
                else:
                    grey_count[line_key] = grey_count.get(line_key, 0) + 1
                    if grey_count[line_key] <= 2:
                        output_lines.append("%s    %8s -> %-32s%s" % (GREY, zone, pod, RESET))

        load_metrics = workload_metrics.get("load", {})

        header = workload

        raw_low = -1
        raw_high = -1
        raw_avg = -1

        output = []

        if "average" in load_metrics:
            raw_avg = load_metrics["average"]

            raw_low = load_metrics.get("band_low", None)
            raw_high = load_metrics.get("band_high", None)

            raw = Load(raw_avg, raw_low, raw_high)

            output = [ f"raw: {raw}" ]

            scaled = raw

            if active_endpoints > 0:
                scaled /= active_endpoints

                output.extend([ f"scaled: {scaled}" ])

        print()

        if output:
            print(f"{header} ({' -- '.join(output)})")
        else:
            print(header)

        for line in output_lines:
            print(line)

def main():
    prev_metrics = defaultdict(lambda: defaultdict(dict))
    grey_count = {}

    while True:
        current_metrics = get_metrics()

        subprocess.run("clear")
        print(time.strftime("%Y-%m-%d %H:%M:%S"))

        print_metrics(current_metrics, prev_metrics, grey_count)

        prev_metrics = current_metrics
        time.sleep(3)

if __name__ == "__main__":
    main()

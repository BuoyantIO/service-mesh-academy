import subprocess
import time
from collections import defaultdict

RED = "\033[31m"
GREEN = "\033[32m"
GREY = "\033[90m"
RESET = "\033[0m"

METRICS_OF_INTEREST = {
    "outbound_http_route_backend_requests_total": "HTTP",
    "outbound_grpc_route_backend_requests_total": "gRPC",
}

LABELS_OF_INTEREST = {
    "parent_name",
    "parent_port",
    "parent_kind",
}

def parse_labels(label_str):
    labels = {}

    for item in label_str.split(','):
        if '=' in item:
            k, v = item.split('=', 1)
            labels[k.strip()] = v.strip().strip('"')

    return labels

def get_metrics(context):
    try:
        output = subprocess.check_output(
            ["linkerd", "--context", context, "diagnostics", "proxy-metrics", \
                        "-n", "faces", "deploy/face"],
            text=True
        )
    except subprocess.CalledProcessError as e:
        print("Error running linkerd:", e)
        return []

    metrics = defaultdict(lambda: defaultdict(dict))

    for line in output.splitlines():
        if line.startswith("#") or not line.strip():
            continue

        if '{' not in line or '}' not in line:
            continue

        metric_name, rest = line.split("{", maxsplit=1)
        label_string, value = rest.split("}", maxsplit=1)

        metric_name = metric_name.strip()
        value = value.strip()

        if metric_name in METRICS_OF_INTEREST:
            protocol = METRICS_OF_INTEREST[metric_name]

            # Extract labels
            labels = parse_labels(label_string)

            name = labels.get("parent_name", "unknown")
            port = labels.get("parent_port", "unknown")

            full_name = f"{name}:{port}"

            backend_name = labels.get("backend_name", name)
            backend_port = labels.get("parent_port", "unknown")

            full_backend_name = f"{backend_name}:{backend_port}"

            protocol_metrics = metrics[protocol]
            source_metrics = protocol_metrics[full_name]

            if full_backend_name in source_metrics:
                source_metrics[full_backend_name] += int(value)
            else:
                source_metrics[full_backend_name] = int(value)

    return metrics

def print_metrics(metrics, prev_metrics):
    for protocol in sorted(metrics.keys()):
        print(f"  {protocol}:")

        for source in sorted(metrics[protocol].keys()):
            prev_for_source = prev_metrics.get(protocol, {}).get(source, {})

            for backend in sorted(metrics[protocol][source].keys()):
                if backend not in prev_for_source:
                    print("%s    %32s -> %-32s%s" % (GREEN, source, backend, RESET))
                    continue

                prev_count = prev_for_source.get(backend, 0)
                current_count = metrics[protocol][source][backend]
                diff = current_count - prev_count

                if diff != 0:
                    print("    %32s -> %-32s %8d" % (source, backend, diff))
                else:
                    print("%s    %32s -> %-32s%s" % (GREY, source, backend, RESET))

def main():
    prev_metrics = defaultdict(lambda: defaultdict(dict))

    while True:
        current_metrics = {
            "east": get_metrics("east"),
            "west": get_metrics("west"),
        }

        subprocess.run("clear")
        print(time.strftime("%Y-%m-%d %H:%M:%S"))

        print("EAST:")
        print_metrics(current_metrics["east"], prev_metrics["east"])
        print("\nWEST:")
        print_metrics(current_metrics["west"], prev_metrics["west"])

        prev_metrics = current_metrics
        time.sleep(5)

if __name__ == "__main__":
    main()

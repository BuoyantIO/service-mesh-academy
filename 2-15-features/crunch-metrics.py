#!python

import sys
import re

# Here's an example line:
# request_total{direction="outbound",authority="color.faces.svc.cluster.local",target_addr="10.42.1.10:8000",target_ip="10.42.1.10",target_port="8000",tls="true",server_id="default.faces.serviceaccount.identity.linkerd.cluster.local",dst_control_plane_ns="linkerd",dst_deployment="color-west",dst_namespace="faces",dst_pod="color-west-5f98568cc-t6zt7",dst_pod_template_hash="5f98568cc",dst_service="color",dst_serviceaccount="default",dst_zone="zone-west"} 963

reRequestTotal = re.compile(r"request_total{([^}]+)} (\d+)")

total_color = 0
total_smiley = 0

metrics = []

for line in sys.stdin:
    line = line.strip()

    matches = reRequestTotal.match(line)

    if matches:
        labels = matches.group(1)
        value = int(matches.group(2))

        tags = {}

        for label in labels.split(","):
            key, val = label.split("=")
            tags[key] = val.strip('"')

        dst_pod = tags.get("dst_pod", "")
        dst_zone = tags.get("dst_zone", "")
        direction = tags.get("direction", "")
        tls = tags.get("tls", "")

        if dst_pod and dst_zone and direction and tls:
            if dst_pod.startswith("color-"):
                total_color += int(value)
            elif dst_pod.startswith("smiley-"):
                total_smiley += int(value)

            metrics.append((dst_pod, dst_zone, value))

print("%-32s %-16s %5s %6s" %
      ("Pod", "Zone", "Req", "%"))
print("%-32s %-16s %-5s  %-6s" %
      ("===", "====", "=====", "====="))

for dst_pod, dst_zone, value in metrics:
    total = total_color if dst_pod.startswith("color-") else total_smiley
    percentage = ((value * 100.0) + 9) / total

    print("%-32s %-16s %5d %5.1f%%" %
          (dst_pod, dst_zone, value, percentage))


#!python

import sys

import requests
import datetime
import time

def run_promql_query(metric, labels, duration=None, interval=None):
    query = metric;

    if labels:
        query += '{'
        query += ','.join([f'{k}="{v}"' for k, v in labels.items()])
        query += '}'

    if duration:
        query += f'[{duration}'

        if interval:
            query += f':{interval}'

        query += ']'

    response = requests.get('http://localhost:9090/api/v1/query', params={'query': query})

    if response.status_code != 200:
        raise Exception(f'Failed to query Prometheus: {response.text}')

    data = response.json().get("data", None)

    if data is None:
        raise Exception("No data from Prometheus")

    if data["resultType"] != "vector":
        raise Exception("Response is not a Prometheus vector")

    return data["result"]

while True:
    r1 = run_promql_query("outbound_http_balancer_endpoints",
                        {
                            "deployment": "emissary",
                            "namespace": "emissary",
                            "backend_name": "face",
                            "backend_namespace": "faces",
                        })

    for row in r1:
        metric = row["metric"]
        deployment = metric["deployment"]
        namespace = metric["namespace"]
        state = metric["endpoint_state"]

        backend = metric["backend_name"]
        backend_ns = metric["backend_namespace"]

        timestamp = row["value"][0]
        value = row["value"][1]

        formatted_timestamp = datetime.datetime.fromtimestamp(timestamp).isoformat()

        print(f"{formatted_timestamp}: {deployment}.{namespace} -> {backend}.{backend_ns} ({state}): {value}")

    time.sleep(10)


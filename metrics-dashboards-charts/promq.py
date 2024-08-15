#!python

# SPDX-FileCopyrightText: 2024 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0

import sys

import json
import requests
import datetime
import time

# Class for a Prometheus query. This is pretty much just here to make it
# simpler to set up the query once, then repeatedly call it.
class PrometheusQuery:
    def __init__(self, query: str) -> None:
        self.query = query

    def run(self) -> dict:
        # print(f"---\n{self.query}")
        response = requests.get('http://localhost:9090/api/v1/query',
                                params={'query': self.query})

        if response.status_code != 200:
            raise Exception(f'Failed to query Prometheus: {response.text}')

        data = response.json().get("data", None)

        if data is None:
            raise Exception("No data from Prometheus")

        # print(json.dumps(data, indent=2))

        if ((data["resultType"] != "vector") and
            (data["resultType"] != "matrix")):
            raise Exception("Response is not a Prometheus vector or matrix")

        return data["result"]


# Run a single query set.
def get_one_row(queries):
    values = {}
    timestamp = None

    for name, query in queries.items():
        result = query.run()

        if len(result) == 0:
            continue

        # print(f"{name}: {result}")

        # The way we're doing the queries, we'll get an array of
        # values, but it'll only have one [timestamp, value] entry.
        rowvalues = result[0]["values"][0]
        values[name] = float(rowvalues[1])

        # All the timestamps across all our queries should be the
        # same (that's why we're using a range query rather than an
        # instantaneous query).
        rowts = rowvalues[0]

        if timestamp is None:
            timestamp = rowts
        elif timestamp != rowts:
            raise Exception("Timestamp mismatch")

    return (timestamp, values)

def main():
    # Building a query for total gRPC requests from deployment `web` to
    # parent `voting-svc` in the `emojivoto` namespace, with a 1-minute
    # duration.

    total_requests = '''
        sum by (parent_name, parent_namespace) (
            rate(
                outbound_grpc_route_backend_response_statuses_total{
                    deployment="web",
                    namespace="emojivoto",
                    parent_name="voting-svc",
                    parent_namespace="emojivoto"
                }[1m]
            )
        )
    '''

    # Same, but only for successful requests.

    successful_requests = '''
        sum by (parent_name, parent_namespace) (
            rate(
                outbound_grpc_route_backend_response_statuses_total{
                    deployment="web",
                    namespace="emojivoto",
                    parent_name="voting-svc",
                    parent_namespace="emojivoto",
                    grpc_status="OK"
                }[1m]
            )
        )
    '''

    # Finally, divide those two to get the success rate.

    success_rate = f'({successful_requests} / {total_requests})'

    # Set up PrometheusQuery objects for each query. We're deliberately turning
    # this into range queries so that Prometheus will sync all their timestamps
    # for us, and we pick the duration and the resolution to be the same so we get
    # just a single value.
    #
    # (I should probably go vet with the Prometheus folks that this is
    # more-or-less OK. [ ;) ])

    queries = {
        "total": PrometheusQuery(total_requests + "[10s:10s]"),
        "success": PrometheusQuery(successful_requests + "[10s:10s]"),
        "rate": PrometheusQuery(success_rate + "[10s:10s]"),
    }

    print("Timestamp            Total     OK    OK %")
    print("---------            -----  -----  ------")
    while True:
        timestamp, values = get_one_row(queries)

        then = datetime.datetime.fromtimestamp(timestamp).isoformat()

        req = values["total"]
        ok = values["success"]
        rate = values["rate"] * 100.0

        print("%s:  %3.2f   %3.2f  %6.2f" % (then, req, ok, rate))

        time.sleep(10)

if __name__ == '__main__':
    main()

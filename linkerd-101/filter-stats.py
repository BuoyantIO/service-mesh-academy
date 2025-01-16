#!/usr/bin/env python

import sys

end_latency_p50 = None
start_timeouts = None

for line in sys.stdin:
    line = line.rstrip()

    # The header will look like this:
    # NAME  SERVICE    ROUTE         TYPE       BACKEND      SUCCESS   RPS  LATENCY_P50  LATENCY_P95  LATENCY_P99  TIMEOUTS  RETRIES
    #
    # We have enough room to show things without wrapping if we drop the
    # LATENCY_P95 and LATENCY_P99 columns.

    if not end_latency_p50:
        # First line.
        start_latency_p50 = line.find("LATENCY_P50")

        if start_latency_p50 < 0:
            print("ERROR: Could not find LATENCY_P50 in header.")
            sys.exit(1)

        end_latency_p50 = start_latency_p50 + len("LATENCY_P50")

        start_timeouts = line.find("TIMEOUTS")

        if start_timeouts < 0:
            print("ERROR: Could not find TIMEOUTS in header.")
            sys.exit(1)

    # OK, if we make it here, we should be good to go.
    print(line[:end_latency_p50] + " ... " + line[start_timeouts:])

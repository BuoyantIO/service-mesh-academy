while sleep 1 ; do
clear ; for i in east central west ; do echo "Metrics for orders-"$i": " ; echo ; linkerd dg proxy-metrics deploy/orders-$i -n orders | \
grep 'request_total' | \
awk -F'[ ,}]' '{
    pod="";
    zone="";
    requests=0;
    for(i=1;i<=NF;i++) {
        if($i ~ /^dst_pod=/) pod=substr($i, 9);
        else if($i ~ /^dst_zone=/) zone=substr($i, 10);
        else if($i ~ /^[0-9]+$/) requests=$i
    }
    if($0 ~ /direction="outbound"/ && $0 ~ /tls="true"/ && pod != "" && zone != "")
        print "Pod: " pod " | Zone: " zone ": " requests
}' ; echo ; done ; done

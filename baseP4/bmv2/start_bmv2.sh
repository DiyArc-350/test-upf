#!/bin/bash
set -e
find_if() { ip -o -4 addr show | awk -v ip="$1" '$4 ~ "^"ip"/" {print $2}'; }
N3=$(find_if 10.0.3.10)
N6=$(find_if 10.0.6.10)
for i in "$N3" "$N6"; do
  ip addr flush dev "$i"
  command -v ethtool >/dev/null && ethtool -K "$i" tx off rx off gro off gso off tso off || true
done
exec simple_switch_grpc -i 1@"$N3" -i 2@"$N6" --device-id 1 --no-p4 \
  -- --grpc-server-addr 0.0.0.0:50001 --priority-queues 4

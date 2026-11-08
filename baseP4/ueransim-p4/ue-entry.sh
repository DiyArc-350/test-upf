#!/bin/sh
cd /UERANSIM/build
./nr-ue -c /config/ue.yaml &
for i in $(seq 1 60); do
  ip link show uesimtun0 >/dev/null 2>&1 && break
  sleep 1
done
ip route add 10.0.6.0/24 dev uesimtun0 2>/dev/null || true
wait

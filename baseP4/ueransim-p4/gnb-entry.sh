#!/bin/sh
dev=$(ip -o -4 addr show | awk '/ 10\.0\.3\.2\//{print $2}')
ip neigh replace 10.0.3.1 lladdr 02:00:00:00:03:0a dev "$dev" nud permanent
cd /UERANSIM/build
exec ./nr-gnb -c /config/gnb.yaml

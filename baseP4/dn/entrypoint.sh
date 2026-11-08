#!/bin/sh
arp -s 10.0.6.1 02:00:00:00:06:0a
ip route add 10.10.10.0/24 via 10.0.6.1
iperf3 -s -p 5201 -D
iperf3 -s -p 5202 -D
exec tail -f /dev/null

"""Fake gNB: send GTP-U uplink, expect the ICMP reply back as GTP-U downlink."""
import time
from scapy.all import Ether, IP, UDP, ICMP, AsyncSniffer, sendp
from scapy.contrib.gtp import GTP_U_Header

IFACE, ME_IP = "eth0", "10.0.3.50"
BMV2_N3_MAC = "02:00:00:00:03:0a"
UE_IP, DN_IP = "10.10.10.2", "10.0.6.2"

sniffer = AsyncSniffer(
    iface=IFACE,
    lfilter=lambda p: p.haslayer(IP) and p.haslayer(UDP)
    and p[IP].dst == ME_IP and p[UDP].dport == 2152)
sniffer.start()
time.sleep(1)

pkt = (Ether(dst=BMV2_N3_MAC) / IP(src=ME_IP, dst="10.0.3.1") /
       UDP(sport=2152, dport=2152) / GTP_U_Header(teid=1) /
       IP(src=UE_IP, dst=DN_IP) / ICMP())
sendp(pkt, iface=IFACE, verbose=False)
time.sleep(3)

got = [p for p in sniffer.stop() if p.haslayer(GTP_U_Header)]
if got:
    for p in got:
        print("downlink:", p.summary())
    print("OK: uplink decap and downlink encap both work")
else:
    print("FAIL: no downlink GTP-U received (check bmv2 logs, dn route/ARP, entries)")

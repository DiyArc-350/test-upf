"""Push the pipeline and install fixed test entries (no PFCP needed)."""
import sys, time
import p4runtime_sh.shell as sh

for _ in range(30):
    try:
        sh.setup(device_id=1, grpc_addr="bmv2:50001", election_id=(0, 1),
                 config=sh.FwdPipeConfig("/p4/upf.p4info.txt", "/p4/upf.json"))
        break
    except Exception as e:
        print("waiting for bmv2:", e)
        time.sleep(2)
else:
    sys.exit("bmv2 not reachable")

BMV2_N3, BMV2_N6 = "02:00:00:00:03:0a", "02:00:00:00:06:0a"
DN_MAC, TEST_MAC = "02:00:00:00:06:02", "02:00:00:00:03:32"

# uplink: GTP-U teid 1 to 10.0.3.1 -> decap -> N6 (port 2) -> DN
te = sh.TableEntry("MyIngress.uplink")(action="MyIngress.uplink_decap")
te.match["teid"] = "1"
te.match["tunnel_dst"] = "10.0.3.1"
te.action["port"] = "2"
te.action["src_mac"] = BMV2_N6
te.action["dst_mac"] = DN_MAC
te.insert()

# downlink: UE 10.10.10.2 -> encap teid 2 toward test "gNB" 10.0.3.50 -> N3 (port 1)
te = sh.TableEntry("MyIngress.downlink")(action="MyIngress.downlink_encap")
te.match["ue_ip"] = "10.10.10.2"
te.action["teid"] = "2"
te.action["gnb_ip"] = "10.0.3.50"
te.action["qfi"] = "1"
te.action["port"] = "1"
te.action["src_mac"] = BMV2_N3
te.action["dst_mac"] = TEST_MAC
te.insert()

print("pipeline loaded, 2 entries installed")
sh.teardown()

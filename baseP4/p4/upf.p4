/* Minimal GTP-U UPF for BMv2 (v1model). No QoS yet: decap uplink, encap downlink. */
#include <core.p4>
#include <v1model.p4>

const bit<16> GTPU_PORT   = 2152;
const bit<8>  PROTO_UDP   = 17;
const bit<9>  PORT_N3     = 1;
const bit<9>  PORT_N6     = 2;
const bit<32> UPF_N3_IP   = 0x0A000301;   // 10.0.3.1 (virtual UPF address on N3)

header ethernet_t { bit<48> dst; bit<48> src; bit<16> etype; }
header ipv4_t {
    bit<4> version; bit<4> ihl; bit<8> tos; bit<16> len; bit<16> id;
    bit<3> flags; bit<13> frag; bit<8> ttl; bit<8> proto; bit<16> csum;
    bit<32> src; bit<32> dst;
}
header udp_t { bit<16> sport; bit<16> dport; bit<16> len; bit<16> csum; }
header gtpu_t {
    bit<3> version; bit<1> pt; bit<1> spare; bit<1> e; bit<1> s; bit<1> pn;
    bit<8> msgtype; bit<16> len; bit<32> teid;
}
header gtpu_opt_t { bit<16> seq; bit<8> npdu; bit<8> next_ext; }
header gtpu_psc_t {                       // PDU Session Container (carries QFI)
    bit<8> len; bit<4> pdu_type; bit<4> spare; bit<1> ppp; bit<1> rqi; bit<6> qfi;
    bit<8> next_ext;
}

struct headers {
    ethernet_t ethernet;
    ipv4_t     ipv4;        // outer on uplink, the only IP header on downlink
    udp_t      udp;
    gtpu_t     gtpu;
    gtpu_opt_t gtpu_opt;
    gtpu_psc_t gtpu_psc;
    ipv4_t     inner_ipv4;
}
struct metadata { }

parser MyParser(packet_in packet, out headers hdr, inout metadata meta,
                inout standard_metadata_t standard_metadata) {
    state start { transition parse_ethernet; }
    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etype) { 0x0800: parse_ipv4; default: accept; }
    }
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        // only look for GTP-U on packets arriving from the gNB
        transition select(hdr.ipv4.proto, standard_metadata.ingress_port) {
            (PROTO_UDP, PORT_N3): parse_udp;
            default: accept;
        }
    }
    state parse_udp {
        packet.extract(hdr.udp);
        transition select(hdr.udp.dport) { GTPU_PORT: parse_gtpu; default: accept; }
    }
    state parse_gtpu {
        packet.extract(hdr.gtpu);
        transition select(hdr.gtpu.msgtype, hdr.gtpu.e ++ hdr.gtpu.s ++ hdr.gtpu.pn) {
            (8w0xff, 3w0): parse_inner;
            (8w0xff, _):   parse_gtpu_opt;
            default: accept;
        }
    }
    state parse_gtpu_opt {
        packet.extract(hdr.gtpu_opt);
        transition select(hdr.gtpu_opt.next_ext) { 0x85: parse_gtpu_psc; default: parse_inner; }
    }
    state parse_gtpu_psc { packet.extract(hdr.gtpu_psc); transition parse_inner; }
    state parse_inner    { packet.extract(hdr.inner_ipv4); transition accept; }
}

control MyVerifyChecksum(inout headers hdr, inout metadata meta) { apply { } }

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    counter(2, CounterType.packets) pkt_cnt;      // 0 = uplink, 1 = downlink

    action drop() { mark_to_drop(standard_metadata); }

    action uplink_decap(bit<9> port, bit<48> src_mac, bit<48> dst_mac) {
        hdr.ipv4 = hdr.inner_ipv4;
        hdr.inner_ipv4.setInvalid();
        hdr.udp.setInvalid();
        hdr.gtpu.setInvalid();
        hdr.gtpu_opt.setInvalid();
        hdr.gtpu_psc.setInvalid();
        hdr.ethernet.src = src_mac;
        hdr.ethernet.dst = dst_mac;
        standard_metadata.egress_spec = port;
        pkt_cnt.count(0);
    }

    action downlink_encap(bit<32> teid, bit<32> gnb_ip, bit<6> qfi, bit<9> port,
                          bit<48> src_mac, bit<48> dst_mac) {
        bit<16> inner_len = hdr.ipv4.len;
        hdr.inner_ipv4 = hdr.ipv4;

        hdr.ipv4.version = 4; hdr.ipv4.ihl = 5; hdr.ipv4.tos = 0;
        hdr.ipv4.len = inner_len + 44;            // 20 ip + 8 udp + 8 gtp + 8 opt/psc
        hdr.ipv4.id = 0; hdr.ipv4.flags = 0; hdr.ipv4.frag = 0;
        hdr.ipv4.ttl = 64; hdr.ipv4.proto = PROTO_UDP; hdr.ipv4.csum = 0;
        hdr.ipv4.src = UPF_N3_IP; hdr.ipv4.dst = gnb_ip;

        hdr.udp.setValid();
        hdr.udp.sport = GTPU_PORT; hdr.udp.dport = GTPU_PORT;
        hdr.udp.len = inner_len + 24; hdr.udp.csum = 0;

        hdr.gtpu.setValid();
        hdr.gtpu.version = 1; hdr.gtpu.pt = 1; hdr.gtpu.spare = 0;
        hdr.gtpu.e = 1; hdr.gtpu.s = 0; hdr.gtpu.pn = 0;
        hdr.gtpu.msgtype = 0xff; hdr.gtpu.len = inner_len + 8; hdr.gtpu.teid = teid;

        hdr.gtpu_opt.setValid();
        hdr.gtpu_opt.seq = 0; hdr.gtpu_opt.npdu = 0; hdr.gtpu_opt.next_ext = 0x85;

        hdr.gtpu_psc.setValid();
        hdr.gtpu_psc.len = 1; hdr.gtpu_psc.pdu_type = 0; hdr.gtpu_psc.spare = 0;
        hdr.gtpu_psc.ppp = 0; hdr.gtpu_psc.rqi = 0; hdr.gtpu_psc.qfi = qfi;
        hdr.gtpu_psc.next_ext = 0;

        hdr.ethernet.src = src_mac;
        hdr.ethernet.dst = dst_mac;
        standard_metadata.egress_spec = port;
        pkt_cnt.count(1);
    }

    table uplink {
        key = { hdr.gtpu.teid: exact @name("teid"); hdr.ipv4.dst: exact @name("tunnel_dst"); }
        actions = { uplink_decap; drop; }
        const default_action = drop();
        size = 1024;
    }
    table downlink {
        key = { hdr.ipv4.dst: exact @name("ue_ip"); }
        actions = { downlink_encap; drop; }
        const default_action = drop();
        size = 1024;
    }

    apply {
        if (hdr.gtpu.isValid() && hdr.inner_ipv4.isValid()) {
            uplink.apply();
        } else if (hdr.ipv4.isValid() && standard_metadata.ingress_port == PORT_N6) {
            downlink.apply();
        } else {
            drop();
        }
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t standard_metadata) { apply { } }

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
    apply {
        update_checksum(hdr.ipv4.isValid(),
            { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.tos, hdr.ipv4.len, hdr.ipv4.id,
              hdr.ipv4.flags, hdr.ipv4.frag, hdr.ipv4.ttl, hdr.ipv4.proto,
              hdr.ipv4.src, hdr.ipv4.dst },
            hdr.ipv4.csum, HashAlgorithm.csum16);
    }
}

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.udp);
        packet.emit(hdr.gtpu);
        packet.emit(hdr.gtpu_opt);
        packet.emit(hdr.gtpu_psc);
        packet.emit(hdr.inner_ipv4);
    }
}

V1Switch(MyParser(), MyVerifyChecksum(), MyIngress(), MyEgress(),
         MyComputeChecksum(), MyDeparser()) main;

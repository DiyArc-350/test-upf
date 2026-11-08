FROM alpine:latest
RUN apk add --no-cache iperf3 iproute2 net-tools tshark
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]

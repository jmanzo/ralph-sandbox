# Egress proxy for the ralph sandbox.
#
# The sandbox sits on a Docker network created with --internal, which has no
# route off the host. This container is attached to BOTH that internal network
# and a normal bridge network, so it is the only path out. Every outbound TCP
# connection is therefore a CONNECT request this proxy can accept or refuse,
# and UDP/ICMP have nowhere to go at all.
FROM alpine:3.20

RUN apk add --no-cache tinyproxy ca-certificates

COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf

# The allowlist is bind-mounted at runtime so `ralph policy` takes effect on a
# proxy restart, with no image rebuild. This copy is only a fallback.
COPY default.allowlist /etc/tinyproxy/allowlist

EXPOSE 8888
ENTRYPOINT ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]

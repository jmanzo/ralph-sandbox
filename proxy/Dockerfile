# Egress proxy for the ralph sandbox.
#
# The sandbox sits on a Docker network created with --internal, which has no
# route off the host. This container is attached to BOTH that internal network
# and a normal bridge network, so it is the only path out. Every outbound TCP
# connection is therefore a CONNECT request this proxy can accept or refuse,
# and UDP/ICMP have nowhere to go at all.
# Pinned by digest for the same reason as the sandbox image; Dependabot
# moves it.
FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc

RUN apk add --no-cache tinyproxy ca-certificates

COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY entrypoint.sh /usr/local/bin/ralph-proxy-entrypoint

# The allowlist is bind-mounted at runtime so `ralph policy` takes effect on a
# proxy restart, with no image rebuild. This copy is only a fallback.
COPY default.allowlist /etc/tinyproxy/allowlist

EXPOSE 8888
ENTRYPOINT ["/usr/local/bin/ralph-proxy-entrypoint"]

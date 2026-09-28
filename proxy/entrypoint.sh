#!/bin/sh
# Render the one line of tinyproxy.conf that depends on the runtime: which
# clients the proxy will serve at all. `ralph` passes the sandbox network's
# subnet in ALLOW_FROM, so a container on the egress bridge (which this proxy
# is also attached to) cannot use it as a way out. Space-separated, one Allow
# line each.
set -eu

conf=/tmp/tinyproxy.conf
cp /etc/tinyproxy/tinyproxy.conf "$conf"

if [ -z "${ALLOW_FROM:-}" ]; then
  echo "ralph-proxy: ALLOW_FROM is not set; serving any client" >&2
  ALLOW_FROM=0.0.0.0/0
fi
for net in $ALLOW_FROM; do
  printf 'Allow %s\n' "$net" >> "$conf"
done

exec tinyproxy -d -c "$conf"

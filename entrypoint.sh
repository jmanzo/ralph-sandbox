#!/usr/bin/env bash
# Sandbox entrypoint. Seeds the workspace in clone mode, then hands off.
set -euo pipefail

SOURCE_DIR=/run/sandbox/source

# Clone mode: the host workspace is mounted read-only at $SOURCE_DIR and the
# agent works in a private copy at /workspace. Seed it once, then leave it
# alone so the agent's work survives restarts.
if [ -d "$SOURCE_DIR" ] && [ ! -e /workspace/.ralph-seeded ]; then
  echo "==> seeding private workspace from read-only source" >&2
  # -a preserves times/modes; the trailing dot copies dotfiles too.
  cp -a "$SOURCE_DIR/." /workspace/ 2>/dev/null || true
  touch /workspace/.ralph-seeded
fi

exec "$@"

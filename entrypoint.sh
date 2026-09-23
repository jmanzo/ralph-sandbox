#!/usr/bin/env bash
# Sandbox entrypoint. Seeds the workspace in clone mode, then hands off.
set -euo pipefail

SOURCE_DIR=/run/sandbox/source

# The home volume is mounted over /home/sandboxuser, which hides whatever the
# image put there. A volume created before an agent's config directory existed
# will never grow one on its own -- Docker only seeds a named volume from the
# image when it is empty -- and codex refuses to start without CODEX_HOME. So
# create them here, on every start, where an upgraded install is covered too.
mkdir -p "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "${CODEX_HOME:-$HOME/.codex}" 2>/dev/null || true
if [ ! -f "${CODEX_HOME:-$HOME/.codex}/config.toml" ]; then
  printf '[telemetry]\ndisabled = true\n' > "${CODEX_HOME:-$HOME/.codex}/config.toml" 2>/dev/null || true
fi


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

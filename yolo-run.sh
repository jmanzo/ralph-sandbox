#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ralph-sandbox}"
# Persists the container's home: login credentials, config, caches.
HOME_VOLUME="${HOME_VOLUME:-ralph-sandbox-home}"
WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "==> building $IMAGE (first run only)"
  docker build -t "$IMAGE" "$(dirname "$0")"
fi

docker volume inspect "$HOME_VOLUME" >/dev/null 2>&1 || docker volume create "$HOME_VOLUME" >/dev/null

# --shell drops into bash instead of launching the agent
if [ "${1:-}" = "--shell" ]; then
  shift
  set -- /bin/bash "$@"
else
  set -- claude --dangerously-skip-permissions "$@"
fi

exec docker run --rm -it \
  --name "agent-sandbox-$$" \
  --hostname sandbox \
  -v "$WORKSPACE_DIR:/workspace" \
  -v "$HOME_VOLUME:/home/sandboxuser" \
  -w /workspace \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  -e TERM="${TERM:-xterm-256color}" \
  "$IMAGE" "$@"

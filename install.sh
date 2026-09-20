#!/usr/bin/env bash
# Symlink `ralph` into a directory on your PATH.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$BIN_DIR"
ln -sf "$ROOT/ralph" "$BIN_DIR/ralph"
echo "linked $BIN_DIR/ralph -> $ROOT/ralph"

case ":$PATH:" in
  *":$BIN_DIR:"*) echo "run 'ralph help' to get started" ;;
  *) echo
     echo "$BIN_DIR is not on your PATH. Add this to your shell profile:"
     echo "  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

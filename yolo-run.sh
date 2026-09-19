#!/usr/bin/env bash
# Backwards-compatible shim. `ralph` is the real entrypoint.
exec "$(dirname "${BASH_SOURCE[0]}")/ralph" run "$@"

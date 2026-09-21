Follow `AGENTS.md` at the repository root. It is the single set of
instructions for every agent working here and is kept in one place on
purpose; do not add rules to this file.

The short version:

- The sandbox boundary is the product. Nothing new enters the container
  (mounts, environment variables, networks, allowlist hosts) without README
  text saying so and a CI test in `.github/workflows/ci.yml`.
- `ralph` and `install.sh` must run on bash 3.2 (macOS). ASCII only in
  anything that runs. shellcheck warning-free. `set -euo pipefail` stays.
- A `RALPH_*` variable is declared once at the top of `ralph`, and documented
  in `docs/configuration.md` and `ralph help`.
- Comments explain why, not what. Match the voice of `loop.sh` and `README.md`.
- Conventional Commits, one change per commit. Never rewrite history.
- Leave `templates/` alone unless the task is about them.

# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). `ralph
version` prints the release you are running.

## [Unreleased]

Everything below is what will become the first tagged release.

### Added

- The sandbox: a Docker image running Claude Code and Codex as an
  unprivileged user, with the host Docker daemon never mounted.
- Deny-by-default egress through a tinyproxy sidecar on an internal network,
  with an allowlist the user owns (`ralph policy ls|edit|sync|test|reset`).
- Workspace modes matching Docker Sandboxes: `direct`, `clone` (with
  `ralph diff` / `ralph apply`) and `none`.
- Host-side snapshots before every `direct`-mode run: a hidden git ref plus a
  bundle outside the mount, restorable after `rm -rf .git`
  (`ralph snapshot ls|create|restore`).
- Hardened mode (`RALPH_HARDEN=on`), pids/memory/cpu limits.
- The Ralph loop (`ralph init`, `ralph loop`): an orchestrator on `haiku`
  delegating to architect, developer and QA subagents with per-role models
  (`ralph model`), one task per iteration, until the PRD is done.
- Guardrails: stall detection, consecutive-failure limit, three strikes on
  one failure signature, a spend ceiling, an optional iteration cap.
- `PROPOSALS.md`: what the loop noticed but did not build.
- Codex as a one-way fallback when Anthropic hits a usage limit, fails
  repeatedly, or spends its three attempts; `ralph login codex` via device
  code; `ralph loop --provider codex`.
- End-of-run notifications to Slack, Discord and Telegram, posted from the
  host so no webhook enters the sandbox.
- `ralph version`.
- CI: shellcheck, an ASCII-only check, the loop scenarios, image builds on
  amd64 and arm64 with boundary tests, and an informational Trivy scan.
- `SECURITY.md`, `CONTRIBUTING.md`, a code of conduct, issue and PR
  templates, `CODEOWNERS`, Dependabot for actions and image digests.
- `AGENTS.md` as the single set of instructions for coding agents and editor
  assistants working on this repository.

### Changed

- Base images are pinned by digest and both agent CLIs by version, so
  `ralph build` is reproducible. `ralph update` is the command that asks for
  the latest agents.
- The NodeSource setup script is no longer piped into bash at build time;
  the keyring and apt source are written out in the `Dockerfile`.
- The README is a quick start; the reference material moved to `docs/`.

### Fixed

- `RALPH_DOCKER_ARGS` keeps shell quoting, so `-e FOO='a b'` reaches docker
  as one argument.

### Security

- `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` enter the sandbox through a
  mode-600 file mounted read-only, not `docker run -e`, so they are not in
  the container config for `docker inspect` to print.
- The egress proxy only serves clients on the sandbox network. Previously a
  container that joined the egress bridge could use it as a way out.
- GitHub Actions are pinned by commit SHA and the workflow token is
  read-only.

[Unreleased]: https://github.com/jmanzo/ralph-sandbox/commits/main

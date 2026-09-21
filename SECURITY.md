# Security policy

`ralph` is a security boundary: it exists so an agent running with
`--dangerously-skip-permissions` can only reach what you gave it. Reports that
the boundary does not hold are the most valuable thing this project can
receive. Please send them privately first.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting:

**<https://github.com/jmanzo/ralph-sandbox/security/advisories/new>**

Do not open a public issue for anything that could let an agent escape,
exfiltrate, or persist. If the form is unavailable, contact the maintainer
([@jmanzo](https://github.com/jmanzo)) through the address on their GitHub
profile and put `ralph-sandbox security` in the subject.

You will get an acknowledgement within a week. Once the report is confirmed
you will hear what the fix is and when it lands; a fix ships with a changelog
entry and, where it matters, a CI test that would have caught it. There is no
bug bounty. Credit in the changelog is offered and can be declined.

## What is in scope

Anything that contradicts the guarantees in the README, on a default
configuration, without the operator having turned a guardrail off:

- **Egress.** Reaching a host that is not on the allowlist from inside the
  sandbox, by any protocol. Includes DNS tricks, raw IPs, IPv6, UDP, and using
  the proxy from a container that is not the sandbox.
- **Filesystem.** Reading or writing anything on the host outside the
  workspace in `direct` mode, or writing the host workspace at all in `clone`
  mode.
- **Docker.** Reaching the host Docker daemon from inside the sandbox.
- **Snapshots.** An agent in `direct` mode that can make a snapshot fail to
  restore, or reach the bundle store.
- **Credentials.** A webhook URL, bot token or API key reaching the sandbox by
  a path the README says it does not travel; a key that ends up in a place the
  README says it does not (container config, transcripts, snapshots).
- **The loop.** Ending a run as `COMPLETE`, or triggering a provider handover,
  by content in a transcript that the guardrails were designed to ignore.
- **Supply chain.** A build that runs code the `Dockerfile` does not spell
  out, or that resolves to something other than the pinned digests and
  versions.

## What is out of scope

The README's *Known limits* section is the list of things `ralph` does not
claim. In particular:

- Kernel exploits. A container shares the host kernel; the README says so.
- Anything that needs `sudo` inside the sandbox when `RALPH_HARDEN=off`. The
  boundary is the container, not anything within it.
- Anything that needs the operator to have set `RALPH_NETWORK_POLICY=off`,
  `RALPH_MOUNT_SSH=1`, or widened the allowlist.
- The agent doing something destructive *inside* the workspace in `direct`
  mode. That is what the mode is for; snapshots are the mitigation.
- Vulnerabilities in the agents themselves (`claude`, `codex`), in Docker, or
  in tinyproxy. Report those upstream; a note here is welcome if `ralph`
  should work around one.
- Findings from the Trivy scan in CI. It is informational; base image CVEs
  are picked up by Dependabot.

## Supported versions

The `main` branch and the most recent tagged release. Fixes are not
backported.

## How the boundary is tested

Every push runs the CI suite in `.github/workflows/ci.yml`, which includes
tests for raw-IP egress, proxy client restriction, the Docker socket, hardened
mode, clone-mode read-only mounts, and snapshot restore after `rm -rf .git`.
A change to `ralph`, `loop.sh`, `proxy/` or `policy/` should come with a test
of the same kind. See `CONTRIBUTING.md`.

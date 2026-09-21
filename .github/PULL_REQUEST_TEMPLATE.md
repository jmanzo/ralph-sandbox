<!-- One change per PR. If this does two things, please split it. -->

## What this changes

<!-- The behaviour, as the README would describe it. Link the issue if there is one. -->

## Why

<!-- The situation that made it necessary. -->

## Checklist

- [ ] `shellcheck` is warning-free and the shell is ASCII-only (see `CONTRIBUTING.md`)
- [ ] Commits follow Conventional Commits, one change each
- [ ] Docs say what the code now does: README, `docs/`, `ralph help`, `ralph status`
- [ ] A new `RALPH_*` variable has a default at the top of `ralph` and a row in `docs/configuration.md`
- [ ] If this touches the boundary (`proxy/`, `policy/`, the `docker run` line, `entrypoint.sh`): a CI test that fails without the change, and a note on *Known limits* if one of them moved

## Does it change what the sandbox can reach?

<!-- No / Yes: what, and why it is worth it. -->

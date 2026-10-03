# Presets

A preset is what `ralph init --preset NAME` adds on top of the usual
scaffolding: the rules a stack needs, the settings that make the sandbox work
for it, and the hosts it has to reach. It exists so that the second project on
a given stack costs nothing to set up.

```
presets/<name>/
  allowlist        egress rules merged into the user's own policy
  files/           copied into the workspace, path for path
    PRD.md           a PRD skeleton shaped for this stack
    .ralph/
      config.env     the project's ralph settings
      rules.md       the rules every agent in the loop reads
```

`ralph init` lays the preset down first and the templates second, so a file
the preset has its own version of is the one that lands. Then it:

- fills the `Build and test` section of `CLAUDE.md` from `package.json`, if
  that section is still the placeholder;
- adds the project's package manager to `.ralph/config.env` as a build arg,
  with the version from `packageManager` when there is one;
- points `CLAUDE.md` and `AGENTS.md` at `.ralph/rules.md`, by import and by
  instruction respectively, because Codex does not follow imports;
- merges `allowlist` into the user's policy, adding only what is missing and
  printing every host it adds.

Nothing here is secret or clever: a preset is files plus hosts. Writing a new
one means writing `rules.md` honestly -- what the sandbox cannot do on this
stack, and the mistakes that cost the most -- and keeping it short enough that
an agent reads it every iteration without drowning.

`files/.ralph/config.env` may only set what a project is allowed to set; the
list is in `docs/configuration.md`. A preset cannot widen the sandbox.

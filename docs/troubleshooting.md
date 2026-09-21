# Troubleshooting

`ralph status` first: it shows what is actually in effect, including which
provider is logged in and whether the proxy is up.

**`Not logged in - Please run /login`** -- expected on first run.

**Something in the sandbox can't reach the internet** -- most likely the policy.
`ralph policy test <host>`, then `ralph policy edit` to allow it.

**`egress proxy is not accepting connections`** -- `ralph proxy logs` shows the
tinyproxy error. Note `FilterType` must be `ere`; `fqdn` is not supported by the
tinyproxy 1.11.x that Alpine ships.

**Login doesn't stick** -- the home volume was removed or renamed. `ralph status`.

**`CODEX_HOME points to ... but that path does not exist`** -- a home volume
created before codex support was added. The entrypoint now creates it on every
start, so `ralph update` fixes it; you do not need to lose your logins.

**The codex fallback never takes over** -- `ralph login status` (is it signed
in?), then `ralph policy sync` (can it reach `auth.openai.com`?). `ralph loop`
warns about the second before a run starts, and `.ralph/alert.json` records
whether a handover was attempted.

**Files written by the agent are root-owned (Linux hosts)** --
`ralph build --build-arg SANDBOX_UID=$(id -u) --build-arg SANDBOX_GID=$(id -g)`.
macOS does not have this problem.

**Agent version is behind your host** -- the image installs from npm, which can lag
other channels. `ralph update`.


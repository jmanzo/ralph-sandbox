# syntax=docker/dockerfile:1
# Pinned by digest: a tag is whatever the registry says it is today, a digest
# is one specific image. Dependabot moves it. Written out in full rather than
# through a build arg because that is the only form Dependabot can read.
FROM ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3

LABEL org.opencontainers.image.title="ralph-sandbox" \
      org.opencontainers.image.description="Disposable container for running coding agents in autonomous (yolo) mode" \
      org.opencontainers.image.source="https://github.com/jmanzo/ralph-sandbox" \
      org.opencontainers.image.licenses="MIT"

ARG NODE_MAJOR=22
# Extra toolchains for your stack, e.g.:
#   docker build --build-arg EXTRA_APT_PACKAGES="golang-go postgresql-client"
ARG EXTRA_APT_PACKAGES=""
ARG EXTRA_NPM_PACKAGES=""
# The agents are pinned so `ralph build` is reproducible and a release of
# either CLI cannot change the sandbox under an unattended run. `ralph update`
# passes `latest` for both; pass a version yourself to land anywhere else.
ARG CLAUDE_VERSION=2.1.278
ARG CODEX_VERSION=0.155.1

ENV DEBIAN_FRONTEND=noninteractive

# Base toolchain plus the utilities coding agents commonly shell out to.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg sudo \
      build-essential python3 python3-pip python3-venv \
      ripgrep jq less unzip zip nano vim openssh-client rsync \
    && rm -rf /var/lib/apt/lists/*

# Node.js. NodeSource publishes native amd64 and arm64 builds, so this image
# builds and runs on Apple Silicon and x86 alike with no emulation. Their
# setup script is not piped into bash: it does nothing more than the three
# lines below, and a script fetched at build time and run as root is the one
# place a supply-chain change would be invisible in a diff of this file.
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN if [ -n "$EXTRA_APT_PACKAGES" ]; then \
      apt-get update \
      && apt-get install -y --no-install-recommends ${EXTRA_APT_PACKAGES} \
      && rm -rf /var/lib/apt/lists/*; \
    fi

# Both agents. Codex is here whether or not you use it: it is the fallback the
# loop reaches for when Anthropic hits a usage limit, and an unattended run at
# 3am is the wrong time to discover it was never installed.
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
    && npm install -g "@openai/codex@${CODEX_VERSION}" \
    && if [ -n "$EXTRA_NPM_PACKAGES" ]; then npm install -g ${EXTRA_NPM_PACKAGES}; fi \
    && npm cache clean --force

# ubuntu:24.04 ships a stock user at uid 1000. Reclaim that uid so files the
# agent writes into the bind-mounted workspace keep the host user's ownership
# on Linux hosts (Docker Desktop virtualises this on macOS regardless).
ARG SANDBOX_UID=1000
ARG SANDBOX_GID=1000
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g "${SANDBOX_GID}" sandboxuser 2>/dev/null || true; \
    useradd -m -u "${SANDBOX_UID}" -g "${SANDBOX_GID}" -s /bin/bash sandboxuser \
    && echo "sandboxuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sandboxuser \
    && chmod 0440 /etc/sudoers.d/sandboxuser

# /workspace is a bind mount whose owner won't match on every host. This has to
# live in the SYSTEM config: RALPH_MOUNT_GITCONFIG mounts the host's
# ~/.gitconfig over the user's, which would shadow anything set with --global
# and leave every git command failing with "detected dubious ownership".
RUN git config --system --add safe.directory /workspace \
    && git config --system --add safe.directory '*'

# Agents refuse to run in yolo mode as root, so the sandbox user is mandatory,
# not a nicety.
USER sandboxuser
# CODEX_HOME sits under $HOME for the same reason CLAUDE_CONFIG_DIR does: $HOME
# is the Docker volume, so a login survives the container and you sign in once.
ENV HOME=/home/sandboxuser \
    CLAUDE_CONFIG_DIR=/home/sandboxuser/.claude \
    CODEX_HOME=/home/sandboxuser/.codex \
    DISABLE_AUTOUPDATER=1 \
    npm_config_prefix=/home/sandboxuser/.npm-global \
    PATH=/home/sandboxuser/.npm-global/bin:/home/sandboxuser/.local/bin:$PATH

RUN mkdir -p /home/sandboxuser/.claude /home/sandboxuser/.codex /home/sandboxuser/.npm-global

COPY --chown=sandboxuser:sandboxuser entrypoint.sh /usr/local/bin/ralph-entrypoint
# The Ralph loop driver. `ralph loop` runs this instead of handing the agent
# a terminal, so the whole run is one container.
COPY --chown=sandboxuser:sandboxuser loop.sh /usr/local/bin/ralph-loop
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/ralph-entrypoint"]
CMD ["/bin/bash"]

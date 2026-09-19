# syntax=docker/dockerfile:1
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

LABEL org.opencontainers.image.title="ralph-sandbox" \
      org.opencontainers.image.description="Disposable container for running coding agents in autonomous (yolo) mode" \
      org.opencontainers.image.source="https://github.com/jmanzo/ralph-sandbox" \
      org.opencontainers.image.licenses="MIT"

ARG NODE_MAJOR=22
# Extra toolchains for your stack, e.g.:
#   docker build --build-arg EXTRA_APT_PACKAGES="golang-go postgresql-client"
ARG EXTRA_APT_PACKAGES=""
ARG EXTRA_NPM_PACKAGES=""
# Pin the agent for reproducible images, e.g. CLAUDE_VERSION=2.1.197
ARG CLAUDE_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive

# Base toolchain plus the utilities coding agents commonly shell out to.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg sudo \
      build-essential python3 python3-pip python3-venv \
      ripgrep jq less unzip zip nano vim openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Node.js. NodeSource publishes native amd64 and arm64 builds, so this image
# builds and runs on Apple Silicon and x86 alike with no emulation.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN if [ -n "$EXTRA_APT_PACKAGES" ]; then \
      apt-get update \
      && apt-get install -y --no-install-recommends ${EXTRA_APT_PACKAGES} \
      && rm -rf /var/lib/apt/lists/*; \
    fi

# The agent itself.
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
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

# Agents refuse to run in yolo mode as root, so the sandbox user is mandatory,
# not a nicety.
USER sandboxuser
ENV HOME=/home/sandboxuser \
    CLAUDE_CONFIG_DIR=/home/sandboxuser/.claude \
    DISABLE_AUTOUPDATER=1 \
    npm_config_prefix=/home/sandboxuser/.npm-global \
    PATH=/home/sandboxuser/.npm-global/bin:/home/sandboxuser/.local/bin:$PATH

# /workspace is a bind mount whose owner won't match on every host.
RUN git config --global --add safe.directory /workspace \
    && git config --global --add safe.directory '*' \
    && mkdir -p /home/sandboxuser/.claude /home/sandboxuser/.npm-global

WORKDIR /workspace
CMD ["/bin/bash"]

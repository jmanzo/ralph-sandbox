FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Common development dependencies + tools Claude Code shells out to
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git build-essential ca-certificates sudo \
    python3 python3-pip python3-venv \
    ripgrep jq less unzip nano \
    && rm -rf /var/lib/apt/lists/*

# Node.js v20 (NodeSource publishes native arm64 builds)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# The agent itself
RUN npm install -g @anthropic-ai/claude-code

# ubuntu:24.04 already ships a user at uid 1000; reclaim it so files written
# into the bind mount keep sane ownership.
RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -u 1000 -s /bin/bash sandboxuser \
    && echo "sandboxuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sandboxuser \
    && chmod 0440 /etc/sudoers.d/sandboxuser

USER sandboxuser
ENV HOME=/home/sandboxuser
# Global npm install is root-owned, so the in-place updater can never succeed.
ENV DISABLE_AUTOUPDATER=1
ENV CLAUDE_CONFIG_DIR=/home/sandboxuser/.claude

# /workspace is a bind mount whose owner won't match on every host
RUN git config --global --add safe.directory /workspace \
    && mkdir -p /home/sandboxuser/.claude

WORKDIR /workspace
CMD ["/bin/bash"]

FROM ubuntu:24.04

# Prevent interactive prompts during setup
ENV DEBIAN_FRONTEND=noninteractive

# Install core dependencies, build tools, and git
RUN apt-get update && apt-get install -y \
    curl git build-essential ca-certificates sudo \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (v20)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install agent CLIs (e.g., Claude Code, Gemini CLI, Codex CLI, etc.)
RUN npm install -g @anthropic-ai/claude-code

# Set up a non-root user with passwordless sudo
RUN useradd -m -s /bin/bash sandboxuser \
    && echo "sandboxuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER sandboxuser
WORKDIR /workspace

CMD ["/bin/bash"]
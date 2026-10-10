# Hardened self-hosted GitHub Actions runner with Claude Code + common toolchains.
# Builds on amd64 (Intel/AMD) and arm64 (Apple Silicon, Raspberry Pi 5, Graviton).
#
# Security properties (see README "Security model"):
#  - jobs run as an unprivileged user with NO sudo
#  - every download is from a signed apt repo or verified with a pinned SHA-256
#  - all versions are pinned; bump them deliberately
#
# Optional: pin the base image by digest for fully reproducible builds:
#   docker buildx imagetools inspect ubuntu:24.04   -> copy the sha256 digest
#   FROM ubuntu:24.04@sha256:<digest>
FROM ubuntu:24.04

# ---- Pinned versions (update together, then rebuild) -----------------------
ARG RUNNER_VERSION=2.338.0
ARG RUNNER_SHA256_X64=af4b794c1bc41d73d40535e3fe092a39f9679cd8d965954c2aca25a05ca41d32
ARG RUNNER_SHA256_ARM64=628b4a7258487b80c1d3c221095a7ded349f5ae0175fd3dfab708d07428f041b
ARG CLAUDE_CODE_VERSION=2.1.296
ARG NODE_MAJOR=24
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---- Base tools (no sudo on purpose) ---------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git git-lfs jq unzip zip xz-utils gnupg \
      tini openssh-client rsync less \
      build-essential pkg-config make \
      python3 python3-pip python3-venv pipx \
    && rm -rf /var/lib/apt/lists/*

# ---- Signed third-party apt repos (no curl|bash) ---------------------------
# Node.js (NodeSource), GitHub CLI, and Docker CLI. The Docker CLI is only used
# if you mount the host socket, which is off by default.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
       > /etc/apt/sources.list.d/docker.list \
    && chmod a+r /etc/apt/keyrings/* \
    && apt-get update && apt-get install -y --no-install-recommends \
       nodejs gh docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ---- Claude Code CLI, pinned (for your own headless `claude -p` steps) ------
RUN npm install -g --ignore-scripts "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && claude --version

# ---- Add your project's toolchains here (pin versions!) --------------------
# RUN apt-get update && apt-get install -y golang-go && rm -rf /var/lib/apt/lists/*
# RUN apt-get update && apt-get install -y openjdk-21-jdk-headless maven && rm -rf /var/lib/apt/lists/*

# ---- Unprivileged job user ---------------------------------------------------
RUN (userdel -r ubuntu 2>/dev/null || true) \
    && useradd -m -s /bin/bash -u 1000 runner

# ---- GitHub Actions runner: verified download, root-owned, read-only to jobs -
WORKDIR /opt/actions-runner
RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64) ARCH=x64;   SHA="${RUNNER_SHA256_X64}" ;; \
      arm64) ARCH=arm64; SHA="${RUNNER_SHA256_ARM64}" ;; \
      *) echo "unsupported architecture"; exit 1 ;; \
    esac; \
    curl -fsSL -o runner.tgz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"; \
    echo "${SHA}  runner.tgz" | sha256sum -c -; \
    tar xzf runner.tgz && rm runner.tgz; \
    ./bin/installdependencies.sh; \
    rm -rf /var/lib/apt/lists/*; \
    chown -R root:root /opt/actions-runner && chmod -R go-w /opt/actions-runner

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Starts as root ONLY to wipe state, hold the registration token and drop
# privileges; all job code runs as uid 1000 with no capabilities.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

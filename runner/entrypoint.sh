#!/usr/bin/env bash
# Root supervisor for an EPHEMERAL GitHub Actions runner.
#
#  1. Wipes everything the previous job could have written (no persistence).
#  2. Uses the GitHub PAT (root-only) to fetch a short-lived registration token.
#  3. Runs the runner as uid 1000 with a clean environment: job code never sees
#     the PAT, cannot read root's /proc/<pid>/environ, and has no capabilities.
#  4. Runs exactly one job, then exits; Docker restarts the container.
set -euo pipefail

if [ "$(id -u)" != "0" ]; then
  echo "entrypoint must start as root (it drops privileges itself)" >&2
  exit 1
fi

: "${GITHUB_OWNER:?Set GITHUB_OWNER in .env (your GitHub username)}"
: "${GITHUB_REPO:?Set GITHUB_REPO in .env (the private repo name)}"
: "${GITHUB_PAT:?Set GITHUB_PAT in .env (fine-grained token, Administration: read & write)}"

PAT="$GITHUB_PAT"
unset GITHUB_PAT
RUNNER_NAME="${RUNNER_NAME:-factory-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-claude,factory}"
RUNNER_UID=1000
RUNNER_HOME=/home/runner
RUNNER_DIR="$RUNNER_HOME/actions-runner"
API="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners"

# --- 1. Wipe all state from previous jobs ------------------------------------
echo "Wiping previous job state..."
# Anything owned by the job user anywhere on the container filesystem.
find / -xdev -user "$RUNNER_UID" -delete 2>/dev/null || true
rm -rf /tmp/* /tmp/.[!.]* /var/tmp/* /var/tmp/.[!.]* /dev/shm/* 2>/dev/null || true
rm -rf "$RUNNER_HOME"
mkdir -p "$RUNNER_HOME"
cp -a /etc/skel/. "$RUNNER_HOME"/
cp -a /opt/actions-runner "$RUNNER_DIR"          # fresh copy of the verified runner
chown -R "$RUNNER_UID:$RUNNER_UID" "$RUNNER_HOME"
chmod 700 "$RUNNER_HOME"

# --- Helpers -----------------------------------------------------------------
# Call the GitHub API without putting the PAT on any command line (/proc/*/cmdline
# is world-readable). The header is passed to curl on stdin instead.
gh_api_post() {
  printf 'header = "Authorization: Bearer %s"\n' "$PAT" | curl -fsSL -X POST -K - \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$1"
}

# Run a command as the job user with a minimal, clean environment.
EXTRA_GROUPS="$RUNNER_UID"
if [ -S /var/run/docker.sock ]; then
  EXTRA_GROUPS="$EXTRA_GROUPS,$(stat -c '%g' /var/run/docker.sock)"
  echo "WARNING: Docker socket mounted — jobs have root-equivalent access to the host."
fi
as_runner() {
  env -i \
    HOME="$RUNNER_HOME" USER=runner LOGNAME=runner SHELL=/bin/bash LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    setpriv --reuid="$RUNNER_UID" --regid="$RUNNER_UID" --groups="$EXTRA_GROUPS" \
            --inh-caps=-all --no-new-privs \
    "$@"
}

# --- 2. Register -------------------------------------------------------------
echo "Requesting registration token for ${GITHUB_OWNER}/${GITHUB_REPO}..."
REG_TOKEN="$(gh_api_post "${API}/registration-token" | jq -r .token || true)"
if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" = "null" ]; then
  echo "ERROR: no registration token. Check GITHUB_OWNER/GITHUB_REPO and that GITHUB_PAT has 'Administration: Read and write' on this repo, and hasn't expired." >&2
  sleep 60   # avoid hammering the API in a restart loop
  exit 1
fi

cd "$RUNNER_DIR"
# The registration token is short-lived (1 hour) and single-purpose; it is
# consumed here and never reaches the job environment.
as_runner ./config.sh \
  --url "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --work _work \
  --ephemeral \
  --replace \
  --unattended
unset REG_TOKEN

# --- 3. Run one job; deregister on shutdown ------------------------------------
RUNNER_PID=""
cleanup() {
  echo "Shutting down: stopping runner and removing its registration..."
  [ -n "$RUNNER_PID" ] && kill -TERM "$RUNNER_PID" 2>/dev/null && wait "$RUNNER_PID" 2>/dev/null || true
  REMOVE_TOKEN="$(gh_api_post "${API}/remove-token" | jq -r .token || true)"
  if [ -n "$REMOVE_TOKEN" ] && [ "$REMOVE_TOKEN" != "null" ]; then
    as_runner ./config.sh remove --token "$REMOVE_TOKEN" || true
  fi
}
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

as_runner ./run.sh &
RUNNER_PID=$!
wait "$RUNNER_PID"

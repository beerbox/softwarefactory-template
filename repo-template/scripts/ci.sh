#!/usr/bin/env bash
# Universal CI entry point, used by both GitHub Actions and Claude.
# Detects the project type and runs install -> lint -> build -> test.
# Replace the auto-detection with explicit commands once your stack is settled.
set -euo pipefail
cd "$(dirname "$0")/.."

ran=0
step() { echo; echo "==> $*"; }
has_script() { node -e "process.exit(require('./package.json').scripts?.['$1'] ? 0 : 1)" 2>/dev/null; }

# Custom override: if the repo has `make ci`, use it and stop.
if [ -f Makefile ] && grep -qE '^ci:' Makefile; then
  step "make ci"; make ci; exit 0
fi

# --- Node / TypeScript -------------------------------------------------------
if [ -f package.json ]; then
  ran=1
  # corepack uses the exact pnpm/yarn version pinned in package.json "packageManager"
  if   [ -f pnpm-lock.yaml ]; then PM="corepack pnpm"; step "pnpm install"; $PM install --frozen-lockfile
  elif [ -f yarn.lock ];      then PM="corepack yarn"; step "yarn install"; $PM install --immutable
  elif [ -f package-lock.json ]; then PM="npm";          step "npm ci";       npm ci
  else                             PM="npm";          step "npm install";  npm install
  fi
  for s in lint typecheck build test; do
    if has_script "$s"; then step "$PM run $s"; $PM run "$s"; fi
  done
fi

# --- Python ------------------------------------------------------------------
if [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; then
  ran=1
  step "python venv"
  VENV="${RUNNER_TEMP:-/tmp}/ci-venv"     # outside the repo so it never gets committed
  python3 -m venv "$VENV" && . "$VENV/bin/activate"
  python -m pip install -q --upgrade pip
  [ -f requirements.txt ]     && pip install -q -r requirements.txt
  [ -f requirements-dev.txt ] && pip install -q -r requirements-dev.txt
  if [ -f pyproject.toml ] || [ -f setup.py ]; then pip install -q -e ".[dev]" 2>/dev/null || pip install -q -e . ; fi
  pip install -q pytest ruff
  step "ruff check"; ruff check .
  step "pytest"
  set +e; pytest -q; code=$?; set -e
  [ "$code" -eq 5 ] && echo "(no tests collected)" || [ "$code" -eq 0 ] || exit "$code"
fi

# --- Go ----------------------------------------------------------------------
if [ -f go.mod ]; then
  ran=1
  step "go vet";  go vet ./...
  step "go test"; go test ./...
fi

# --- Rust --------------------------------------------------------------------
if [ -f Cargo.toml ]; then
  ran=1
  step "cargo clippy"; cargo clippy --all-targets -- -D warnings
  step "cargo test";   cargo test
fi

# --- Java / Kotlin -----------------------------------------------------------
if [ -f pom.xml ]; then ran=1; step "mvn verify"; mvn -B verify; fi
if [ -f gradlew ];  then ran=1; step "gradle check"; ./gradlew check --no-daemon; fi

# --- Dockerfile at repo root: make sure it still builds ---------------------
if [ -f Dockerfile ] && command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  ran=1; step "docker build"; docker build -q -t ci-check:local .
fi

if [ "$ran" -eq 0 ]; then
  echo "No known project type detected. Edit scripts/ci.sh to add your checks."
fi
echo; echo "✅ CI passed"

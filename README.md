# Software Factory · Claude Code + Docker + GitHub

A universal, security-hardened, private-repo setup where **GitHub issues go in
and reviewed, tested pull requests come out**. Claude Code does the work inside
a Docker container on your own computer (a self-hosted GitHub runner), so it
costs **zero GitHub Actions minutes** and runs on your **Claude Pro** subscription.

```
 Issue + label "claude-ready"
            │
            ▼
 ┌──────────────────────────── your computer (Docker) ─────────────────────────────┐
 │ gate       labeller has write access? secrets configured?                       │
 │ implement  fresh container · READ-ONLY token · Claude codes, tests, commits     │
 │            └─► commits exported as a git bundle (no secrets in this job)        │
 │ publish    NEW clean container · rejects .github/ .claude/ & huge files         │
 │            └─► pushes branch claude/issue-N-… · opens PR "Closes #N"            │
 └─────────────────────────────────────────────────────────────────────────────────┘
            │
            ▼
 PR ──► CI (scripts/ci.sh) ──► Claude review ──► YOU review & merge
  ▲                                                  │
  └──── comment "@claude fix …" for follow-up commits ┘
```

## What's in the kit

| Path | Goes where | Purpose |
|---|---|---|
| `runner/` | stays on your computer | Hardened Docker image + compose file for the self-hosted runner |
| `repo-template/.github/workflows/claude-implement.yml` | your repo | label → implementation → PR |
| `repo-template/.github/workflows/claude.yml` | your repo | `@claude` in comments/reviews |
| `repo-template/.github/workflows/claude-review.yml` | your repo | automatic PR review |
| `repo-template/.github/workflows/ci.yml` | your repo | tests/lint on every PR |
| `repo-template/.github/dependabot.yml` | your repo | keeps pinned actions up to date |
| `repo-template/.github/actionlint.yaml` | your repo | tells linters about the runner labels |
| `repo-template/scripts/ci.sh` | your repo | universal CI script (Node, Python, Go, Rust, Java auto-detect) |
| `repo-template/CLAUDE.md` | your repo | rules Claude follows — **fill it in** |
| `repo-template/.claude/settings.json` | your repo | Claude Code permissions |
| `repo-template/.github/ISSUE_TEMPLATE/factory-task.yml` | your repo | issue form that makes good tasks |

## Requirements

- A computer that can stay on while the factory works (Linux, macOS or Windows with WSL2), with **Docker** installed
- **Claude Pro** (or Max) and Claude Code installed locally: `npm install -g @anthropic-ai/claude-code`
- **GitHub Free** account and a **private** repository (see "Recommended upgrade" below)

---

## Setup (about 25 minutes)

### 1. Lock down the repo's Actions settings
Repo → **Settings → Actions → General**:
- **Workflow permissions** → *Read repository contents and packages permissions* (the workflows grant extra permissions per job, only where needed).
- **Uncheck** *Allow GitHub Actions to create and approve pull requests*.
- **Fork pull request workflows** → leave fork workflows disabled / require approval.

Repo → **Settings → Collaborators**: only people you trust get **Write** access.
Anyone with write access can trigger Claude on your computer.

### 2. Install the Claude GitHub App on the repo
Go to **https://github.com/apps/claude** → *Install* → *Only select repositories* → pick your repo.

### 3. Create the Claude token (uses your Pro subscription)
On your computer:
```bash
claude setup-token
```
Copy the token (starts with `sk-ant-oat…`) — treat it like a password. In GitHub:
repo → **Settings → Secrets and variables → Actions → New repository secret**
- Name: `CLAUDE_CODE_OAUTH_TOKEN` · Value: the token

### 4. Create two fine-grained GitHub tokens
GitHub → avatar → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**.
For both: *Repository access → Only select repositories → this repo*, and an
**expiration of 90 days or less** (put a rotation reminder in your calendar).

| Token | Permissions (nothing else) | Where it goes |
|---|---|---|
| **Runner token** | Administration: **Read and write** | `runner/.env` on your computer only |
| **Factory token** | Contents: **Read and write** · Pull requests: **Read and write** | repo secret `FACTORY_PAT` |

The factory token deliberately has **no Workflows permission**, so nothing the
factory produces can change your pipeline. It is only used in the `publish`
job, which never runs Claude.

### 5. Copy the template into your repo
```bash
cp -r repo-template/. /path/to/your-repo/
cd /path/to/your-repo
chmod +x scripts/ci.sh
# Edit CLAUDE.md now — fill in the TODOs.
git add .github .claude CLAUDE.md scripts
git commit -m "chore: add software factory"
git push
```
Make sure the repo has a `.gitignore` covering `.env`, dependencies and build output.

### 6. Create the trigger label
Repo → **Issues → Labels → New label** → `claude-ready`.
(Or: `gh label create claude-ready --color 7057ff`.) `claude-pr-open` is created automatically.

### 7. Start the runner
```bash
cd runner
cp .env.example .env
chmod 600 .env            # only you can read the runner token
# fill in GITHUB_OWNER, GITHUB_REPO, GITHUB_PAT (runner token)
docker compose up -d --build
docker compose logs -f    # wait for "Listening for Jobs"
```
Check repo → **Settings → Actions → Runners**: `factory-1` should show *Idle*.

### 8. First run
1. **Issues → New issue → 🏭 Factory task**, fill it in, create it.
2. **Read it once more**, then add the **claude-ready** label (labelling = approving Claude to act on that text).
3. The issue gets a "picked this up" comment, then a PR link (usually 5–20 min).
4. On the PR: CI runs and Claude posts a review. Reply `@claude please fix X` for changes.
5. You review the diff and merge. The issue closes automatically.

---

## Daily use

| You want to… | Do this |
|---|---|
| Build a feature / fix a bug | Issue from the template → add `claude-ready` |
| Ask about the code | Comment `@claude how does auth work?` on any issue |
| Change a factory PR | Comment `@claude rename X and add a test for Y` on the PR |
| Fix failing CI | Comment `@claude CI is failing, please fix` on the PR |
| Re-run a failed job | Remove and re-add `claude-ready` |
| Re-review after changes | Comment `@claude review again` |

---

## Security model

### What's protected, and how

| Threat | Protection |
|---|---|
| Strangers triggering jobs on your computer | Private repo only; Claude responds only to users with write access; the factory `gate` job re-checks the labeller's permission; fork workflows off. |
| A job stealing the runner token | Token lives only in a root process; jobs run as uid 1000 with a clean environment, **no sudo, zero Linux capabilities**, `no-new-privileges`, and can't read root's `/proc/*/environ`. The token never appears on a command line. |
| A job leaving malware for the next job | Ephemeral runner: one job per registration, and before every job the container wipes everything the job user could write and restores a fresh copy of the root-owned runner. |
| Prompt injection via issue text making Claude leak or misuse secrets | Claude's implement job has **only a read-only GitHub token** and no publishing secrets. Its commits leave as a git bundle; a separate clean job verifies them and only then uses `FACTORY_PAT`. Git hooks/config Claude might plant are never executed with secrets present. |
| Claude modifying the pipeline or its own permissions | Changes under `.github/` or `.claude/` (and `.gitmodules`, `.gitattributes`) are rejected by `publish`; `FACTORY_PAT` has no Workflows permission; `.claude/settings.json` denies those edits. |
| A PR rewriting its own reviewer's rules | The review job loads `CLAUDE.md` and `.claude/` from the **base** branch, and has read-only contents access. |
| Compromised or changed third-party actions | Every action is pinned to a full commit SHA; Dependabot proposes updates weekly. |
| Tampered downloads in the runner image | Runner tarball verified by pinned SHA-256; Node.js, GitHub CLI and Docker CLI come from GPG-signed apt repos; Claude Code version pinned. |
| Over-broad tokens | `permissions: {}` at workflow level, minimal per-job permissions, fine-grained single-repo PATs with expiry. |
| Resource abuse | Memory, CPU and process limits; job timeouts; log rotation. |

### Residual risks (be aware of these)

- **Claude can see its own Claude token** inside the job (it needs it to run).
  A successful prompt injection could leak it, which would let someone use your
  Claude Pro usage. Mitigations: only label issues you've read, keep the repo
  private, and rotate the token with `claude setup-token` if in doubt.
- **The job has full internet access.** For stronger isolation, run the
  factory on a dedicated VM and restrict outbound traffic to GitHub, npm/PyPI
  and `api.anthropic.com`.
- **`@claude` on PRs uses the Claude GitHub App**, which can push commits. On
  GitHub Free, private repos can't enforce branch protection, so nothing
  technically stops a push to `main`. See the recommended upgrade below.
- **CI runs the PR's code** on your computer (it gets no secrets). That's normal
  for CI, but it's another reason to keep write access to trusted people.
- **Docker socket**: mounting it (commented out in `docker-compose.yml`) gives
  jobs root-equivalent access to your computer and voids most of the above.
  Leave it off, or use rootless Docker / a dedicated VM.
- **Never attach this runner to a public repository.**

### Recommended upgrade: GitHub Pro (about $4/month)
GitHub Pro enables **branch protection on private repos**. Then add a rule for
`main`: require a pull request, require the `CI` check to pass, and block force
pushes. This closes the biggest remaining gap and makes "nothing merges
without passing CI and your review" enforced rather than a habit. With Pro you
can also move `FACTORY_PAT` and `CLAUDE_CODE_OAUTH_TOKEN` into a deployment
**environment** with its own protection rules.

---

## Maintenance (monthly, 10 minutes)

- **Merge Dependabot PRs** for actions after a quick look.
- **Rebuild the runner** to pick up OS security patches:
  `docker compose build --pull --no-cache && docker compose up -d`
- **Bump pinned versions** in `runner/Dockerfile` when needed:
  - `RUNNER_VERSION` + both `RUNNER_SHA256_*` values: copy them from the
    "SHA-256 Checksums" section of the release at
    https://github.com/actions/runner/releases (the runner also self-updates, but
    a current base version keeps start-up fast).
  - `CLAUDE_CODE_VERSION`: `npm view @anthropic-ai/claude-code version`
- **Rotate tokens** before they expire (runner token in `.env`, `FACTORY_PAT` secret).
  Restart the runner after changing `.env`: `docker compose up -d`.

## Living with Claude Pro limits

- One runner = one job at a time. Pro usage is limited in rolling windows and
  is shared with your normal Claude chats.
- Small, well-specified issues are much cheaper than vague big ones. Split anything large.
- The review runs only when a PR opens (not on every push). Add `synchronize` in
  `claude-review.yml` if you want more.
- If a run fails with a usage/rate-limit error, wait for the reset and re-add the label.
- If others start using the factory, switch to an API key (`anthropic_api_key`
  input) instead of your personal subscription token.

## Customising

- **Toolchains:** add Go, Rust, Java… in `runner/Dockerfile` (pin versions), then rebuild.
- **CI:** replace the auto-detection in `scripts/ci.sh` with your real commands,
  or add a `make ci` target (it takes priority).
- **More repos:** one runner per repo on a personal account. Copy the `runner:`
  block in `docker-compose.yml` with its own `.env` file and token.
- **Protected paths:** edit the `BLOCKED` pattern in `claude-implement.yml` to
  protect more (e.g. `^infra/`, `^migrations/`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| Job stuck on "Waiting for a runner" | `docker compose ps` / `logs`; labels must include `claude`. |
| `no registration token` in logs | Runner token needs Administration: Read and write on *this* repo; check spelling and expiry. |
| Gate fails: "does not have write access" | Only collaborators with Write/Maintain/Admin can start the factory. |
| Claude step fails with an auth error | Regenerate with `claude setup-token`, update `CLAUDE_CODE_OAUTH_TOKEN`. |
| Publish fails: "protected paths" | Claude touched `.github/` or `.claude/`. Refine the issue or make that change yourself. |
| PR opens but CI/review don't run | `FACTORY_PAT` missing, expired or lacks Contents / Pull requests write. |
| No comments from `@claude` | Claude GitHub App not installed on the repo. |
| Errors writing files outside the repo | Expected: jobs can only write to their workspace, home and `/tmp`. |

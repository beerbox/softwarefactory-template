# Security review — changes from the first version of the kit

Reviewed against GitHub's "Security hardening for GitHub Actions" and
self-hosted runner guidance, Docker hardening practice, and Claude Code
permission guidance. Workflows were checked with `actionlint`, `shellcheck`
and the `zizmor` Actions security scanner (no template-injection or
credential findings remain; the remaining "self-hosted runner" warnings are
expected for a private-repo runner).

## High

| # | Finding in v1 | Fix in v2 |
|---|---|---|
| H1 | Runner token readable by jobs: the entrypoint ran as the same user as jobs, so a job could read it from `/proc/<pid>/environ`. | Root supervisor holds the token; jobs run as uid 1000 with `env -i` and can't read root's process memory/env. Token never on a command line. |
| H2 | Passwordless `sudo` in the container: any job could become root, read the token, and backdoor the runner. | `sudo` removed; `no-new-privileges`, all capabilities dropped for jobs. |
| H3 | `FACTORY_PAT` was used in the same workspace Claude had controlled: a planted git hook or `core.fsmonitor` setting could steal it. | Split into `implement` (no publishing secrets) → git bundle → `publish` in a fresh container with a clean checkout. Hooks/fsmonitor disabled when packaging. Verified by simulation. |
| H4 | Claude's implement job used the Claude GitHub App token (can push), so a prompt-injected Claude could push straight to `main` (no branch protection on Free). | Implement job uses a read-only `GITHUB_TOKEN`. |
| H5 | The review job loaded `.claude/settings.json` and `CLAUDE.md` from the PR, so a PR could grant its reviewer extra tools. | Rules are taken from the base branch; review token is read-only. |

## Medium

| # | Finding | Fix |
|---|---|---|
| M1 | Actions referenced by mutable tags (`@v1`, `@v5`). | Pinned to full commit SHAs + Dependabot for updates. |
| M2 | `curl \| bash` NodeSource installer; runner tarball not checksum-verified; Claude Code unpinned. | Signed apt repo; pinned runner with SHA-256 check; pinned Claude Code; `npm --ignore-scripts`. |
| M3 | No check of who applied the `claude-ready` label. | `gate` job requires write/maintain/admin permission. |
| M4 | Issue text passed to Claude with no injection guidance. | Prompt treats issue as data; CLAUDE.md rule; README: read before labelling. |
| M5 | Default workflow permissions not denied. | `permissions: {}` at workflow level, minimal per job. |
| M6 | Factory output could touch `.github/`, `.claude/`, add huge files. | `publish` rejects protected paths and files > 5 MB. |
| M7 | No container resource limits on processes or logs. | `pids_limit`, log rotation, caps dropped, memory/CPU limits kept. |
| M8 | State could persist between jobs in the restarted container. | Before each job, everything writable by the job user is wiped and a fresh root-owned runner copy is used. |

## Low

- Checkouts no longer persist credentials where not needed.
- `FACTORY_PAT` reduced to Contents + Pull requests (issue updates use `GITHUB_TOKEN`).
- PAT expiry/rotation, `chmod 600 .env`, repo Actions settings documented.
- `@mentions` in Claude-written PR bodies neutralised.
- pnpm/yarn run via corepack (versions pinned by `packageManager`) instead of `npx --yes`.
- Removed misleading deny rules (`env`, `printenv`) that gave a false sense of security.

## Residual risks (documented in README → Security model)

Claude can see its own Claude token; jobs have internet access; `@claude`
on PRs uses an app token that can push; GitHub Free can't enforce branch
protection on private repos (GitHub Pro fixes this); enabling the Docker socket
voids container isolation.

## Not verified here

The Docker image could not be built in the review environment (no Docker
daemon). Watch the first `docker compose up --build` and the first factory run.

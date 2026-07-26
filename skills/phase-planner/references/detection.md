# Detecting how a repo works

Read the repo, don't interrogate the user. Everything below is observable, and observed facts beat remembered ones — people misremember their own CI, and "we use Copilot" often means "we turned it on once."

Run this per repo. Show the evidence, then let them correct it.

## Default branch → `target_branch`

Read it from the repository. Never assume `main`: `develop`, `master`, and `trunk` are all in the wild, and getting it wrong means every phase branches from the wrong place.

## Workflows → `ci.dispatch`

List the repo's workflows and read the ones that run on `pull_request`.

| Observed | Set |
|---|---|
| A workflow declares `workflow_dispatch` | `dispatch: workflow:<file>` |
| Workflows exist, none declares `workflow_dispatch` | `dispatch: push` |
| No workflows at all | `dispatch: none` |

Note whether push-triggered workflows have `paths-ignore` for `docs/plans/**`. If not, that's a hygiene item — the driver writes three plan commits per phase.

## Check runs on recent PRs → `ci.required`, `ci.allow_none`

**This is the load-bearing one.** What a workflow file declares and what actually reports on a PR are different things — jobs get skipped by conditions, matrices expand into several checks, and external CI appears with no workflow file at all.

Look at the head commits of several recently merged PRs and collect the check run names that actually appear.

| Observed | Set |
|---|---|
| A consistent set of checks | Leave `required: []` (all count) or name them if some are advisory |
| Checks that appear only sometimes | Name the stable ones in `required` — an intermittent check in the required set stalls the gate |
| Advisory checks (coverage, preview deploys, a reviewer's own check) | `ignore_checks`, or name only the real ones in `required` |
| No checks, and no CI configured anywhere | `allow_none: true`, and say so out loud — nothing will be verifying merges |
| No checks, but workflows exist | **Do not set `allow_none: true`.** CI is configured and not reporting, which means it's broken or misrouted. Setting the flag here disables the failsafe permanently to work around a temporary fault. Flag it and ask |

Checks appearing without a corresponding workflow file mean external CI — Xcode Cloud, CircleCI, Buildkite. Set `logs: check-output`, since Actions log APIs won't work for them.

## Who actually reviews → `review.required`

From the same recent PRs, collect review authors and inline-comment authors.

| Observed | Set |
|---|---|
| `copilot-pull-request-reviewer` / `github-copilot` / `copilot` | `required: [{ logins: [all three] }]` |
| A `Claude Code Review` check run | `required: [{ check: "Claude Code Review" }]` |
| A Claude review workflow job | `required: [{ check: "<job name>" }]` |
| Only humans | `required: []`, and mention that gates 4 and 5 still apply to them |
| Nobody reviews | `required: []`, and say plainly that nothing will be checking the driver's work |

**Check whether the reviewer's comments are inline.** Only diff-anchored comments create resolvable threads. A reviewer that posts one top-level summary makes `threads_must_resolve` meaningless — warn rather than silently configure a gate that measures nothing.

**Check whether it re-reviews on push.** Proof-of-review is anchored to the head commit, so a reviewer that only reviews on PR open goes stale the first time the driver pushes a fix, and the gate stalls. If you can't tell, say so — it's better surfaced now than discovered as a mysterious hang.

### `proof`

Default `output`. Set `proof: completed` only when you've seen that reviewer produce a green check with no output on a clean pass — some reviewers are genuinely silent when they find nothing. Explain the trade when you set it: a skipped or no-op job then also counts as a review.

## Toolchain → `verify`

From the repo's files:

| Observed | Set |
|---|---|
| `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml` | `local` |
| An Xcode project, `Package.swift` for an app target | `ci` — macOS and Xcode can't exist in a Linux container |
| Gradle with an Android plugin | `auto` — JVM unit tests can run locally, instrumented ones can't |
| Markdown, config, or docs only | `none` |

For `local`, check whether a `SessionStart` hook exists to install dependencies. Without one the toolchain may be missing, and `local` has **no fallback** — verification simply fails and the phase blocks. If you can't confirm the toolchain will be there, choose `auto` instead, which is the mode that falls back to CI by design.

## When there's nothing to observe

A brand-new repo has no PR history, so most of this returns nothing. Don't invent a config. Say what you couldn't determine and ask — one question now beats a gate that hangs on the first PR.

The safe starting point for an unknown repo depends on whether CI *exists*, which you can tell from the repo even with no PR history:

```yaml
review: { required: [] }     # no reviewer observed
verify: auto                 # try local, fall back
```

Plus, for CI:

- **No workflows and no external CI app** → `ci: { allow_none: true }`. Nothing is configured, so nothing will report.
- **Workflows exist but no PR has exercised them** → **leave `allow_none` at its default of `false`.** A scaffolded repo commonly has `.github/workflows/*` committed and zero merged PRs, which looks identical to "no CI" if you only count check runs. Setting the flag there disables the failsafe permanently for a repo whose CI simply hasn't run yet. Say you couldn't confirm CI reports, and let the first PR settle it.

Then say plainly how much the merge gate is actually checking, and what to add once CI and review are in place.

**Branch protection.** Check whether the default branch accepts direct commits. The planner writes the plan there, and the driver writes every status transition there. If it's protected, say so now and follow the fallback in `SKILL.md` step 5 — discovering it at write time is late, and discovering it mid-plan is worse.

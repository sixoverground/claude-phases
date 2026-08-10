# Detecting how a repo works

Read the repo, don't interrogate the user. Everything below is observable, and observed facts beat remembered ones. People misremember their own CI, and "we use Copilot" often means "we turned it on once."

Run this per repo. Show the evidence, then let them correct it.

## Read current code, not PR history

This file already says that what a workflow *declares* differs from what actually *reports*. The same holds one level up, for the code a plan is written against: **a merged PR describes what was added, not what survived.**

Merged PR bodies, plan files from earlier projects, and design docs are all evidence of intent at a moment in the past. Components get removed, renamed, or rewritten afterward, and nothing goes back to amend the PR that introduced them. A phase scoped around a component that no longer exists reads as perfectly researched right up until the driver tries to build it.

So use PR history to find *where* to look and *what questions to ask*, then open the files. Phase scope, "what the codebase already gives us", and any claim about how something currently works must come from the code on the branch you're targeting.

The failure is not hypothetical: a phase in this project's own first real plan was written around an iOS component taken from a merged PR body, which had since been deleted for causing a hang.

## Default branch → `target_branch`

Read it from the repository. Never assume `main`: `develop`, `master`, and `trunk` are all in the wild, and getting it wrong means every phase branches from the wrong place.

Ask whether phases should target the default branch at all. Work that must land as a unit, a feature nobody wants half-shipped. Targets a long-running feature branch instead. When they say yes, confirm the branch exists in every repo, set `target_branch` on each, and set `plan_branch` to match in the home repo so the plan travels with the feature. See [Where the plan lives](configuration.md#where-the-plan-lives).

## Trigger filters → whether required checks can fire at all

Detection normally asks *which* checks appear. When `target_branch` isn't the default branch, ask a second question: **can they appear on a PR into that branch?**

`on: pull_request:` with a `branches:` filter fires only for PRs whose base is listed. A check seen on every PR into `main` may never appear on a PR into `feature/x`, and the gate then waits forever for something that was never going to run. Read the filter on every workflow behind a name you're about to put in `ci.required` or `review.required[].check`.

Checks with no workflow file. CodeQL default setup, Xcode Cloud, other external providers. Carry their own start conditions, which are usually scoped to the default branch and which you cannot read. Don't require those when targeting a feature branch. Leave them unnamed and they're counted only if they turn up, which is the right behaviour while their scope is unknown. Say in the handoff that they're advisory and worth confirming on the first PR.

## Workflows → `ci.dispatch`

List the repo's workflows and read the ones that run on `pull_request`.

| Observed | Set |
|---|---|
| A workflow declares `workflow_dispatch` | `dispatch: workflow:<file>` |
| Workflows exist, none declares `workflow_dispatch` | `dispatch: push` |
| No workflows at all | `dispatch: none` |

Note whether push-triggered workflows have `paths-ignore` for `docs/plans/**`. If not, that's a hygiene item. The driver writes three plan commits per phase.

## Check runs on recent PRs → `ci.required`, `ci.allow_none`

**This is the load-bearing one.** What a workflow file declares and what actually reports on a PR are different things. Jobs get skipped by conditions, matrices expand into several checks, and external CI appears with no workflow file at all.

Look at the head commits of several recently merged PRs and collect the check run names that actually appear.

| Observed | Set |
|---|---|
| A consistent set of checks | Leave `required: []` (all count) or name them if some are advisory |
| Checks that appear only sometimes | Name the stable ones in `required`, an intermittent check in the required set stalls the gate |
| Advisory checks (coverage, preview deploys, a reviewer's own check) | `ignore_checks`, or name only the real ones in `required` |
| No checks, and no CI configured anywhere | `allow_none: true`, and say so out loud, nothing will be verifying merges |
| No checks, but workflows exist | **Do not set `allow_none: true`.** CI is configured and not reporting, which means it's broken or misrouted. Setting the flag here disables the failsafe permanently to work around a temporary fault. Flag it and ask |

Checks appearing without a corresponding workflow file mean external CI. Xcode Cloud, CircleCI, Buildkite. Set `logs: check-output`, since Actions log APIs won't work for them.

## Who actually reviews → `review.required`

From the same recent PRs, collect review authors and inline-comment authors.

| Observed | Set |
|---|---|
| `copilot-pull-request-reviewer` / `github-copilot` / `copilot` | `required: [{ logins: [all three] }]` |
| A `Claude Code Review` check run | `required: [{ check: "Claude Code Review" }]` |
| A Claude review workflow job | `required: [{ check: "<job name>" }]` |
| Only humans | `required: []`, and mention that gates 4 and 5 still apply to them |
| Nobody reviews | `required: []`, and say plainly that nothing will be checking the driver's work |

**Check whether the reviewer's comments are inline.** Only diff-anchored comments create resolvable threads. A reviewer that posts one top-level summary makes `threads_must_resolve` meaningless. Warn rather than silently configure a gate that measures nothing.

**Check whether it re-reviews on push.** Proof-of-review is anchored to the head commit, so a reviewer that only reviews on PR open goes stale the first time the driver pushes a fix, and the gate stalls. If you can't tell, say so. It's better surfaced now than discovered as a mysterious hang.

### `proof`

Default `output`. Set `proof: completed` only when you've seen that reviewer produce a green check with no output on a clean pass. Some reviewers are genuinely silent when they find nothing. Explain the trade when you set it: a skipped or no-op job then also counts as a review.

## Toolchain → `verify`

From the repo's files:

| Observed | Set |
|---|---|
| `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml` | `local` |
| An Xcode project, `Package.swift` for an app target | `ci`: macOS and Xcode can't exist in a Linux container |
| Gradle with an Android plugin | `auto`: JVM unit tests can run locally, instrumented ones can't |
| Markdown, config, or docs only | `none` |

For `local`, check whether a `SessionStart` hook exists to install dependencies. Without one the toolchain may be missing, and `local` has **no fallback**. Verification simply fails and the phase blocks. If you can't confirm the toolchain will be there, choose `auto` instead, which is the mode that falls back to CI by design.

## When there's nothing to observe

A brand-new repo has no PR history, so most of this returns nothing. Don't invent a config. Say what you couldn't determine and ask. One question now beats a gate that hangs on the first PR.

The safe starting point for an unknown repo depends on whether CI *exists*, which you can tell from the repo even with no PR history:

```yaml
review: { required: [] }     # no reviewer observed
verify: auto                 # try local, fall back
```

Plus, for CI:

- **No workflows and no external CI app** → `ci: { allow_none: true }`. Nothing is configured, so nothing will report.
- **Workflows exist but no PR has exercised them** → **leave `allow_none` at its default of `false`.** A scaffolded repo commonly has `.github/workflows/*` committed and zero merged PRs, which looks identical to "no CI" if you only count check runs. Setting the flag there disables the failsafe permanently for a repo whose CI simply hasn't run yet. Say you couldn't confirm CI reports, and let the first PR settle it.

Then say plainly how much the merge gate is actually checking, and what to add once CI and review are in place.

**Branch protection.** Check whether the **plan branch** accepts direct commits. The default branch, or `plan_branch` if you're setting one. The planner writes the plan there, and the driver writes every status transition there. If it's protected, say so now and follow the fallback in `SKILL.md` step 5. Discovering it at write time is late, and discovering it mid-plan is worse. A feature branch is usually unprotected even when the default branch isn't, so check the branch you'll actually use rather than the repo's headline setting.

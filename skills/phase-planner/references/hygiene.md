# Repo hygiene checklist

Settings that make the difference between a driver that runs unattended and one that stalls. Go through these when writing a plan; each is cheap, and each prevents a failure that's hard to diagnose later.

Flag what's missing. Fix what you can. A workflow edit is a PR. Settings outside the repo need the user.

## Prevents a stalled gate

**Re-review on push.** Proof-of-review is anchored to the head commit. A reviewer that only fires on PR open goes stale the moment the driver pushes a fix, and the gate waits forever on a review that will never come.

- Copilot: enable the "Review new pushes" ruleset
- Managed Claude Code Review: set Review Behavior to **After every push**
- A review workflow: include `synchronize` in its `pull_request` types

**Inline review comments.** Only diff-anchored comments create resolvable threads. A reviewer posting a single top-level summary makes the thread gate vacuous. It will always pass, having measured nothing.

**A reviewer that says something on a clean pass.** If it goes completely silent when it finds nothing, proof-of-review can't distinguish "reviewed and found nothing" from "never ran", and you're forced into `proof: completed`, which accepts a skipped job as a review.

**A reviewer that can diff against the target branch.** Review workflows usually check out a shallow clone, which has no merge base with anything but the default branch. When `target_branch` is a feature branch, `git diff origin/<target>...HEAD` then fails, and most review workflows fall back to reviewing file *contents* at HEAD instead of the change. The gate still passes. The review is just no longer about the diff, and nothing says so.

Watch for it on the first phase PR: a review that describes files rather than changes, or that re-raises things the base branch already contained. The fix is in the workflow, not here. Fetch the target branch with enough depth to have a merge base (`fetch-depth: 0`, or an explicit `git fetch origin <target>`).

## Prevents wasted CI and accidental deploys

**`paths-ignore: ['docs/plans/**']`** on push-triggered workflows. The driver writes three plan commits per phase to the plan branch. Without this they burn CI minutes, and on a repo that deploys from that branch they trigger deploys. The driver also appends `[skip ci]` to plan commits, but `paths-ignore` is belt and braces.

Less of a concern when the plan branch isn't the default branch, since push triggers are often pinned to the default, but preview deploys usually aren't, so check rather than assume.

**`workflow_dispatch`** on the CI workflow, if you want the driver to trigger builds without pushing an empty commit. Optional: without it, the driver triggers CI by pushing, which everyone does anyway.

**A preview environment pinned to a branch the driver deletes.** Vercel, Netlify, Amplify and friends can pin an environment to a named branch. Point one at a phase branch and it dies at the first merge, because the driver deletes phase branches as they land. Point one at the `target_branch` and it survives the plan, then dies when the feature merges and GitHub auto-deletes that branch.

This matters more than a broken preview usually would, because the environment is normally where the user runs UAT. During one plan the staging domain silently kept serving a build from a branch that no longer existed, and an evening went into diagnosing a feature that was working correctly and simply wasn't deployed.

Pin previews to the default branch, or accept that the pin needs moving when the feature lands and say so in the plan. Ask which, rather than assuming there is no preview.

## Prevents clutter and confusion

**Auto-delete merged branches** (Settings → General). The driver creates one branch per phase and does not clean them up after merging, so a twelve-phase plan leaves twelve stale branches. Turning this on makes GitHub do it for you.

**Branch protection.** If the plan branch rejects direct pushes, the driver can't write plan status normally. Either allow the driver's identity to push, or set `plan_writes: plan-pr` so each status change becomes a small auto-merging PR. Detect this before the first phase rather than discovering it mid-run. A feature branch used as `plan_branch` is usually unprotected, which sidesteps this even when the default branch is locked down.

**Don't delete the plan branch while a plan is running.** With `plan_branch` on a feature branch, merging that feature and letting GitHub auto-delete the branch takes the plan with it, and the driver stops rather than guessing. Finish the plan first, or move the plan file to the default branch before the feature merges.

## Makes local verification possible

**A `SessionStart` hook** that installs dependencies, for any repo set to `verify: local`. `local` has no fallback: if the toolchain isn't there, verification fails and the phase blocks. Use `verify: auto` if you'd rather it drop to CI instead.

## Worth mentioning, not blocking

**A `CLAUDE.md`** describing conventions the driver should follow. It reads it like any session, and phases written to match the codebase's existing style need less review.

**A PR template.** The driver fills the body itself, but a template tells it what the repo expects.

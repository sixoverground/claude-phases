# Repo hygiene checklist

Settings that make the difference between a driver that runs unattended and one that stalls. Go through these when writing a plan; each is cheap, and each prevents a failure that's hard to diagnose later.

Flag what's missing. Fix what you can — a workflow edit is a PR. Settings outside the repo need the user.

## Prevents a stalled gate

**Re-review on push.** Proof-of-review is anchored to the head commit. A reviewer that only fires on PR open goes stale the moment the driver pushes a fix, and the gate waits forever on a review that will never come.

- Copilot: enable the "Review new pushes" ruleset
- Managed Claude Code Review: set Review Behavior to **After every push**
- A review workflow: include `synchronize` in its `pull_request` types

**Inline review comments.** Only diff-anchored comments create resolvable threads. A reviewer posting a single top-level summary makes the thread gate vacuous — it will always pass, having measured nothing.

**A reviewer that says something on a clean pass.** If it goes completely silent when it finds nothing, proof-of-review can't distinguish "reviewed and found nothing" from "never ran", and you're forced into `proof: completed`, which accepts a skipped job as a review.

## Prevents wasted CI and accidental deploys

**`paths-ignore: ['docs/plans/**']`** on push-triggered workflows. The driver writes three plan commits per phase to the default branch. Without this they burn CI minutes, and on a repo that deploys from the default branch they trigger deploys. The driver also appends `[skip ci]` to plan commits, but `paths-ignore` is the belt to that's braces.

**`workflow_dispatch`** on the CI workflow, if you want the driver to trigger builds without pushing an empty commit. Optional — without it, it triggers CI by pushing, which everyone does anyway.

## Prevents clutter and confusion

**Auto-delete merged branches** (Settings → General). The driver creates one branch per phase and there is no API to delete them afterward, so a twelve-phase plan leaves twelve stale branches.

**Branch protection.** If the default branch rejects direct pushes, the driver can't write plan status normally. Either allow the driver's identity to push, or set `plan_writes: plan-pr` so each status change becomes a small auto-merging PR. Detect this before the first phase rather than discovering it mid-run.

## Makes local verification possible

**A `SessionStart` hook** that installs dependencies, for any repo set to `verify: local`. Without it the toolchain may be missing and verification silently falls back to CI — slower, and the PR body will say so, but it's an avoidable round trip.

## Worth mentioning, not blocking

**A `CLAUDE.md`** describing conventions the driver should follow. It reads it like any session, and phases written to match the codebase's existing style need less review.

**A PR template.** The driver fills the body itself, but a template tells it what the repo expects.

# Design notes

Why the rules are the way they are. Most of them look like over-engineering until you know what they're defending against, and a rule whose reason has been forgotten tends to get simplified back into a bug.

## The plan file is the state

A Claude Code cloud session is ephemeral. Its container is reclaimed after inactivity, its context compacts as it grows, and it can die at any moment — mid-implementation, between opening a PR and recording it, between merging and advancing.

That single fact drives everything. A fresh session must reconstruct the world from the plan file plus what GitHub reports, with no memory of what came before. Every other decision here is downstream.

### Status is written to the default branch, never inside the phase PR

The predecessor to this project — [cpm](https://github.com/sixoverground/claude-project-manager) — writes phase status *inside* the phase PR. That works there, because cpm is an external poller that tracks the cursor itself; the plan file is documentation.

Here it would be fatal. A status written inside a PR is invisible on the default branch until that PR merges. A fresh session reading the plan would see `Pending` for a phase that already has an open PR, and start it a second time. Resume becomes structurally impossible, and the failure mode is duplicate branches for a single phase — the most confusing state to unpick.

So the driver commits status to the home repo's default branch, before the action it describes: claim before branching, record the PR before waiting on it. Every crash window in [the recovery table](format.md#recovery) closes because of that ordering. It is the thing most worth not "tidying up" later.

### Phase PRs never touch the plan file

One writer means a squash merge can never conflict with its own bookkeeping, however far the default branch has moved. Without it, every phase risks a conflict in the file that records that phase's progress.

It also makes the plan readable as a live dashboard: the default branch always shows current state, not state as of the last merge.

### Driver-ID, and why recency isn't enough

Two drivers on one plan would race, so the obvious guard is "if the heartbeat is recent, someone else is live — refuse."

That guard deadlocks a long-lived session against itself. A driver that writes its heartbeat, sleeps, and wakes on a webhook five minutes later would refuse to continue until its own heartbeat went stale.

So the lock carries identity, not just recency. A driver recognizes its own `Driver-ID` and proceeds; a stranger's recent ID blocks; a stranger's stale ID gets taken over. Small addition, and without it "keep one session running" and "start a fresh session whenever" cannot both be supported.

## The merge gate

### Three questions that were riding on one signal

The reviewer gate started as a single check: *did the required reviewer approve?* That turns out to conflate three separate questions, and separating them is what lets one rule work across reviewers that behave completely differently.

| Question | Answered by |
|---|---|
| Did the reviewer look at **this** commit? | Proof-of-review, anchored to the head SHA |
| Were its findings addressed? | Thread resolution |
| Must the review check itself be green? | The checks gate — name it in `ci.required` |

Keeping them apart is what lets the gate work for a reviewer that signals findings by *failing* and for one that never fails by design. Anthropic's managed Code Review is the second kind: its check always concludes `neutral` so it can never block a merge through branch protection. A gate requiring `success` would wait forever on a reviewer that had already done its job.

### Why `neutral` passes the checks gate

cpm treats `NEUTRAL` as blocking. That's stricter than GitHub itself, which treats `neutral` as a non-failing conclusion — advisory tools use it precisely so they never block a merge. Inheriting cpm's stricter reading would deadlock any repo with an advisory reporter.

### Why zero checks blocks

A repo whose CI silently stopped running looks exactly like a repo with no CI. The failsafe direction is to stop, so zero checks blocks unless `ci.allow_none: true` says otherwise deliberately.

The same reasoning appears in the planner: it distinguishes *no CI exists* from *CI exists and isn't reporting*, because setting `allow_none: true` for the second case permanently disables a failsafe to work around a temporary fault.

## What a green check does not tell you

This is the part worth reading even if you skip the rest, because it was learned the expensive way.

Setting up one Claude review workflow on this repository produced **six runs that all reported `success`** and meant six different things:

| Run | Duration | What actually happened |
|---|---|---|
| 1 | 10s | Skipped: the workflow file differed from the default branch. Reviewed nothing |
| 2 | 8.5 min | Real review. No `--comment` flag, so findings went only to the job log |
| 3 | 20s | Short, no artifacts |
| 4 | 6.3 min | Real review, found a real bug. Reported explicitly that it had no `--comment` |
| 5 | 22s | Aborted waiting on a sub-agent |
| 6 | 9 min | Real review, found four real bugs, and **could not post any of them** — every `gh` call denied at the tool-permission layer |

Six greens. One of them meant "reviewed and clean." None of them was distinguishable from the others in GitHub's UI.

Three rules come from that:

**Proof of review must be an artifact, not an exit code.** A job that exits 0 having reviewed nothing produces a green check indistinguishable from a clean pass. This is why `proof: output` is the default — a check must carry something the reviewer wrote.

**But `proof` has to be configurable, because the strict rule is wrong for some reviewers.** Run 6's reviewer, once fixed, posts inline comments when it has findings and *nothing at all* when it doesn't — no comment, no review at the head SHA, empty check output. Under `proof: output` a clean review would block the merge permanently. Under `proof: completed` it works, at the cost of a skipped job also counting.

No rule reading only the check run separates "reviewed and found nothing" from "never ran." That's not a gap to be closed with a cleverer rule; it's a genuine ambiguity, and the choice of which error to prefer belongs to whoever knows their reviewer.

**A reviewer that cannot run should be loud.** The obvious kindness — skip the job gracefully when a secret is missing — produces a green check that the gate counts as a review. The workflow shipped here has no graceful-skip guard for exactly that reason. Prefer a red check that gets fixed over a green one that means nothing.

### Which error to prefer

Where the two point in opposite directions, this project prefers the false block:

> A false pass is silent and permanent. A false block is loud, and someone notices within a phase.

## Multi-repo

**One plan, one driver, N repos.** The plan lives in `home_repo` and is the only writer, which is what keeps the single-writer invariant intact across a cross-platform project.

**Independent repos run concurrently**, one open PR per repo, gated only by `Depends`. cpm is serial across repos — it skips a project when *any* repo has an open phase PR — which costs roughly 3× the wall-clock on a three-platform project for no correctness benefit.

**Blank `Depends` means "the previous row", not "no dependency."** Parallel rows must name their real dependency explicitly. Leaving it blank chains them, which is the opposite of the intent, and it's an easy mistake to make while writing a plan by hand.

**There is no atomic cross-repo merge.** Three PRs cannot land as one transaction, and no amount of prompt engineering changes that. Plans that need platforms to ship together express it as a dependency plus an explicit cutover phase.

## Where tests run

Running tests in-session is preferred: seconds instead of a CI round-trip, and a failure never costs a PR revision. But a Linux container has node and not Xcode, so `verify` is per repo and honest about it.

The rule that matters is not which mode you pick but that **the PR body records which path actually ran**. "Tests pass" means something different when CI proved it than when the driver did, and a reviewer should not have to guess which they're looking at.

Note that `local` has no fallback — if the toolchain is missing, verification fails and the phase blocks. `auto` is the mode that drops to CI. Conflating them was itself a bug the reviewer caught.

## Things deliberately not done

**Writing status inside the phase PR.** Breaks resume. Non-negotiable.

**Starting cloud sessions from a scheduler.** There's no API for it. cpm can notify that a session died; it cannot resurrect one, and pretending otherwise would be worse than the gap.

**Auto-rerunning CI until green.** One rerun per head commit, disclosed. Beyond that it launders a real failure into a pass.

**Renumbering phases during a replan.** Merged rows are a record of what shipped. Append or subdivide instead.

**A machine-readable status block alongside the human table.** Two sources of truth for one value diverge. The table is the status; front matter is config; Driver State is liveness.

## Known gaps

**Nobody notices a dead session.** A dying session cannot report its own death, so a stalled phase looks the same as a slow one. The natural fix is a watchdog on a cold heartbeat — which is what cpm already is, and the strongest argument for eventually connecting the two projects.

**The head can move between the final gate check and the merge.** `merge_pull_request` accepts no expected-SHA, so the window can be narrowed — re-read the head as the last call before merging — but not closed.

**Rate limits are invisible.** A review consuming a large chunk of a subscription's allowance, re-running on every push, can hit a limit mid-phase. A rate-limited reviewer looks like a stalled gate.

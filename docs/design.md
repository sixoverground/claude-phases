# Design notes

This document explains why `claude-phases` works the way it does. The detailed rules can look excessive without the failure that motivated them, and a rule whose reason is forgotten is easy to simplify back into a bug.

## Design at a glance

Five principles account for most of the system:

| Principle | Consequence |
|---|---|
| A Claude Code session is temporary | The committed plan file is the durable state |
| State must survive a crash at any point | The driver records transitions before or immediately after external actions |
| Only one driver may advance a plan | Driver identity, heartbeats, and blob SHAs form an optimistic lock |
| A green check is weak evidence | Merge readiness is split into independent CI, review, and thread gates |
| YOLO delegates phase merges, not final release judgment | The driver may merge phase PRs, but never the final integration PR |

If you are new to the project, read [The plan file is the state](#the-plan-file-is-the-state), [What a green check does not prove](#what-a-green-check-does-not-prove), and [Finishing a plan](#finishing-a-plan) first. The remaining sections explain edge cases and the real runs that uncovered them.

## The plan file is the state

A Claude Code cloud session is ephemeral. Its container is reclaimed after inactivity, its context compacts as it grows, and it can die at any moment: mid-implementation, between opening a PR and recording it, between merging and advancing.

That fact drives the design. A fresh session must reconstruct the world from the plan file and GitHub, with no memory of what came before.

### Status is written outside the phase PR, on the plan branch

The predecessor to this project, [cpm](https://github.com/sixoverground/claude-project-manager), writes phase status *inside* the phase PR. That works there, because cpm is an external poller that tracks the cursor itself; the plan file is documentation.

Here it would break recovery. A status written inside a PR is invisible until that PR merges. A fresh session would see `Pending` for a phase that already has an open PR and start it again, producing duplicate branches and PRs for one phase.

The driver therefore claims a phase before creating its branch, then records the PR immediately after opening it and before waiting. That ordering closes every crash window in the [recovery table](../skills/phase-planner/references/format.md#recovery).

### The plan branch is not necessarily the default branch

This started out written as "the default branch", and stayed that way until the first attempt to plan a real project. A feature spanning two repos, every phase targeting `feature/calendar`, nothing reaching `main` until the whole thing worked. The plan had to live on the feature branch, and the spec had no way to say so.

The actual requirement is:

> a branch that no phase PR modifies, and that is readable without merging one.

A feature branch satisfies both. So `plan_branch` names it, defaulting to the default branch because that remains the common case.

Usually `plan_branch` is also `target_branch`, so phase PRs merge into the branch containing the plan. This is safe because phase PRs never touch the plan file. A merge still moves the branch, however, so the driver must read the plan blob's SHA again before every state transition.

The planner refuses a `plan_branch` that does not exist. If that branch is deleted during a run, the driver stops and reports it. Falling back to the default branch could make every row appear `Pending` and repeat work that already shipped.

### Phase PRs never touch the plan file

One writer means a squash merge can never conflict with its own bookkeeping, however far the plan branch has moved. Without it, every phase risks a conflict in the file that records that phase's progress.

It also makes the plan readable as a live dashboard: the plan branch always shows current state, not state as of the last merge.

### Driver-ID, and why recency isn't enough

Two drivers on one plan would race, so the obvious guard is "if the heartbeat is recent, someone else is live, refuse."

That guard deadlocks a long-lived session against itself. A driver that writes its heartbeat, sleeps, and wakes on a webhook five minutes later would refuse to continue until its own heartbeat went stale.

So the lock carries identity, not just recency. A driver recognizes its own `Driver-ID` and proceeds; a stranger's recent ID blocks; a stranger's stale ID gets taken over. Small addition, and without it "keep one session running" and "start a fresh session whenever" cannot both be supported.

### Why one plan file rather than a sequence of issues

Breaking a feature into issues is the obvious alternative, and for a lot of work it is the better one. Issues have a UI, notifications, search, cross-references and boards; they hold discussion before work starts; `Closes #12` gives the state transition away for free; and anyone on the team can pick one up. Against a hand-maintained markdown table, that is not a close contest.

The plan file exists because the driver is not a team. It is an ephemeral session with no memory that has to reconstruct the world and then act on it unattended, and that requirement asks for things issues do not offer:

- **Order and dependencies as data.** `Depends` plus a `Status` column that *is* the execution cursor makes "what is startable now" a property of one file. In an issue tracker that ordering lives in a board, or in prose, or in someone's head.
- **A home for state that belongs to no single item.** `Driver-ID`, `Heartbeat`, `YOLO`, `UAT-pending`, and the per-repo CI and review config are all cross-cutting. Issues have nowhere to put them, so a plan built on issues still needs a config file, and then there are two sources of truth, which is the failure this project avoids everywhere else.
- **Multi-repo.** An issue lives in one repository. A feature spanning a backend and two apps has no natural single tracker, while one plan in a home repo coordinates all three.
- **A lock and a compare-and-swap.** `Driver-ID` with a heartbeat is a real lock, and passing the blob `sha` on every write makes plan updates fail rather than clobber. The failing write is only half of it: the loser has to re-run the Driver-ID decision before retrying, or it reapplies its own claim over the winner's and both drivers proceed. Assignees are a much cruder lock and issue edits have no equivalent guard.
- **One read, not a fan-out.** Reconcile runs on every wake. Against a file it is one read; against issues it is N API calls into the same rate limit the reviewer is already consuming.

The line is roughly that **issues scale with people and the plan file scales with autonomy.** Single repo, human watching every step, several contributors picking work up: issues are the better tool there, and this project is heavier than the job deserves.

Worth being clear about what this choice is *not*. The plan file versus issues is a storage decision. The merge gate, proof-of-review, crash recovery and the rules for answering a review are the substance, and all of it would survive a port to issues unchanged. Nobody should read this section as an argument that the gate needs a markdown file.

And running both, the plan file for the driver and issues for visibility, is the one combination to avoid. It is dual-write, it drifts, and the reason is the same one that keeps a machine-readable status block out of the file: two sources of truth for one value diverge. If both are wanted, generate one from the other.

## The merge gate

### Three questions, three signals

The reviewer gate started as a single check: *did the required reviewer approve?* That turns out to conflate three separate questions, and separating them is what lets one rule work across reviewers that behave completely differently.

| Question | Answered by |
|---|---|
| Did the reviewer look at **this** commit? | Proof-of-review, anchored to the head SHA |
| Were its findings addressed? | Thread resolution |
| Must the review check itself be green? | The checks gate, name it in `ci.required` |

Keeping these questions separate supports reviewers with different reporting behavior. Anthropic's managed Code Review, for example, always concludes `neutral`; requiring `success` would wait forever even after it completed.

### Why `neutral` passes the checks gate

cpm treats `NEUTRAL` as blocking. That's stricter than GitHub itself, which treats `neutral` as a non-failing conclusion. Advisory tools use it precisely so they never block a merge. Inheriting cpm's stricter reading would deadlock any repo with an advisory reporter.

### Why zero checks blocks

A repo whose CI silently stopped running looks exactly like a repo with no CI. The failsafe direction is to stop, so zero checks blocks unless `ci.allow_none: true` says otherwise deliberately.

The same reasoning appears in the planner: it distinguishes *no CI exists* from *CI exists and isn't reporting*, because setting `allow_none: true` for the second case permanently disables a failsafe to work around a temporary fault.

### A required check that can never fire

Detection asks which checks appear on recent PRs. That answer is conditional on those PRs' base branch, and nothing about the check run says so.

`on: pull_request:` with a `branches:` filter fires only for the bases listed. Point a plan at a feature branch and a check that ran on all fifty PRs into `main` may run on none of yours. Because the gate waits for a *named* check, and the check never appears, the failure is a permanent hang with nothing red to look at. The hardest shape of failure to diagnose, arriving hours after the plan was written.

Hence the planner refusal, and hence the rule about checks whose triggers you can't read at all. CodeQL default setup, Xcode Cloud, any external provider with its own start conditions. Those are left out of `ci.required` when targeting a feature branch, so they're counted if they appear and waited on if they don't. It's the same failsafe direction as zero-checks, pointed at a different unknown.

## What a green check does not prove

This is the most important limitation in the merge model, and it was learned from real runs.

Setting up one Claude review workflow on this repository produced **six runs that all reported `success`** and meant six different things:

| Run | Duration | What actually happened |
|---|---|---|
| 1 | 10s | Skipped: the workflow file differed from the default branch. Reviewed nothing |
| 2 | 8.5 min | Real review. No `--comment` flag, so findings went only to the job log |
| 3 | 20s | Short, no artifacts |
| 4 | 6.3 min | Real review, found a real bug. Reported explicitly that it had no `--comment` |
| 5 | 22s | Aborted waiting on a sub-agent |
| 6 | 9 min | Real review, found four real bugs, and **could not post any of them**: every `gh` call denied at the tool-permission layer |

All six runs were green, but none meant "reviewed and clean." GitHub's UI did not distinguish them from the seventh run, which finally did complete correctly.

Three rules come from that:

**Proof of review must be an artifact, not an exit code.** A job that exits 0 having reviewed nothing produces a green check indistinguishable from a clean pass. This is why `proof: output` is the default. A check must carry something the reviewer wrote.

**But `proof` has to be configurable, because the strict rule is wrong for some reviewers.** Run 6's reviewer, once fixed, posts inline comments when it has findings and nothing the gate can anchor to when it doesn't. No inline comment, no review at the head SHA, empty check output, only an unanchored top-level PR comment. Under `proof: output` a clean review would block the merge permanently. Under `proof: completed` it works, at the cost of a skipped job also counting.

No rule reading only the check run separates "reviewed and found nothing" from "never ran." That's not a gap to be closed with a cleverer rule; it's a genuine ambiguity, and the choice of which error to prefer belongs to whoever knows their reviewer.

**A reviewer that cannot run should be loud.** The obvious kindness, skipping the job gracefully when a secret is missing, produces a green check that the gate counts as a review. The workflow shipped here has no graceful-skip guard for exactly that reason. Prefer a red check that gets fixed over a green one that means nothing.

### Which error to prefer

Where the two point in opposite directions, this project prefers the false block:

> A false pass is silent and permanent. A false block is loud, and someone notices within a phase.

## Answering a review

A phase ran four review rounds, stopped for permission to keep going, got it, and ran twenty-eight more. The rule it was following was one line: *address it in code, push, then resolve the thread*. Nothing in it was wrong. What it lacked was any test for whether a comment should be acted on, and any instruction to look further than the comment.

### A review comment is evidence, not an order

The driver already had the right rule for problems it finds on its own: stay inside the phase, note the rest in the PR body. A reviewer's finding was held to a different standard, and that inconsistency is the whole leak. Scope discipline that applies to what you notice yourself but not to what a tool suggests isn't scope discipline; it just means the widening arrives through the review channel instead.

The reviewer has read one diff. The phase's scope came from a plan a person agreed to. When those disagree about what this PR is for, the plan wins.

### Fix the pattern, not only the flagged line

A reviewer comments where it happened to find a problem. The same underlying mistake may appear elsewhere in the diff, so changing only the anchored line often produces another round of equivalent findings. The driver reads every open thread, groups related findings, fixes the general case, and pushes once.

### Declining needs a destination

"Out of scope" with nowhere to put the finding means forgotten, and a driver that senses that will implement things rather than lose them. So each outcome has a home: work that belongs to this plan but not this phase goes to **Carried findings** in the plan file, a standalone defect goes to an issue, and a remark that changes nothing goes in the reply.

**The driver appends to that list and never adds a phase.** Turning a finding into a phase means writing scope, acceptance criteria, UAT and dependencies. That is planning, and it belongs to `phase-planner` and the person whose plan it is. A driver that adds phases because a reviewer suggested something is the same runaway that produced twenty-eight rounds, moved up a level where it costs more and is noticed later.

### Two stuck counters, because a moving head is not progress

`stuck.max_cycles` counts a gate failing for the same reason with an **unmoved head**. That is the right shape for a phase waiting on something that never arrives, and it is the wrong shape for the runaway above, which pushed a commit every round. By that counter the phase was making progress thirty-two times in a row.

So `stuck.max_review_rounds` counts the other failure: a phase that moves and gets nowhere. Two counters rather than one generalized counter, because the two states are genuinely different and a rule that tried to cover both would have to define progress, which is the thing in dispute.

**The count is derived, never remembered.** It is the number of distinct head commits a required reviewer has evaluated, re-read every wake, using the same test gate 6 already applies to decide whether a reviewer looked at a commit. Heads rather than review submissions, because answering two reviewers on one commit is one round and costs one push, and because a `check:` entry never submits a review at all, so a submission count would sit at zero for exactly the setups most able to loop. This is not an implementation detail; it is most of why the runaway was invisible. A session that tracks the tally loses it to compaction, and the next session sees one review comment, a rule telling it to answer, and no evidence that twelve rounds came before. Every wake honestly looks like the first one. Anything the driver must not lose has to be re-derivable or written down, and a round count is cheap to re-derive.

The exception proves the rule. Clearing the stop needs a baseline, because a derived count still reads above the threshold the moment after a person says carry on, and the row would block again forever. That baseline is the one number here that cannot be re-derived, so it goes in the plan, which is where everything the driver must not lose already lives.

**The stop is a report, not a question.** The observed failure was approved at four rounds by a person who had no basis to refuse: "shall I continue?" carries no information, so it collects a yes. The threshold therefore produces evidence, and the load-bearing line of it is whether the newest findings are new ground or the same class of finding resurfacing somewhere new. Four rounds of unrelated real bugs and four rounds of one problem in four files are the same number and opposite decisions.

### Why a scope decline resolves the thread and a disagreement does not

The two look similar and are not. Gate 5 holds the merge until every thread resolves, so leaving a declined thread open would stall a phase over work that was never in it, trading a runaway loop for a deadlock. But a thread that says the code is *wrong* is exactly what gate 5 exists to hold for, and resolving it on the driver's own judgment would let it overrule a reviewer by fiat.

So the split follows what the thread claims, not how inconvenient it is: disagreement on the merits stays open for a person, scope goes to the list and the thread closes with a note saying where it went.

## Multi-repo

**One plan, one driver, N repos.** The plan lives in `home_repo` and is the only writer, which is what keeps the single-writer invariant intact across a cross-platform project.

**Independent repos run concurrently**, one open PR per repo, gated only by `Depends`. cpm is serial across repos. It skips a project when *any* repo has an open phase PR, which costs roughly 3× the wall-clock on a three-platform project for no correctness benefit.

**Blank `Depends` means "the previous row", not "no dependency."** Parallel rows must name their real dependency explicitly. Leaving it blank chains them, which is the opposite of the intent, and it's an easy mistake to make while writing a plan by hand.

**There is no atomic cross-repo merge.** Three PRs cannot land as one transaction, and no amount of prompt engineering changes that. Plans that need platforms to ship together express it as a dependency plus an explicit cutover phase.

## Where tests run

Running tests in-session is preferred: seconds instead of a CI round-trip, and a failure never costs a PR revision. But a Linux container has node and not Xcode, so `verify` is per repo and honest about it.

The rule that matters is not which mode you pick but that **the PR body records which path actually ran**. "Tests pass" means something different when CI proved it than when the driver did, and a reviewer should not have to guess which they're looking at.

Note that `local` has no fallback: if the toolchain is missing, verification fails and the phase blocks. `auto` is the mode that drops to CI. Conflating them was itself a bug the reviewer caught.

## Finishing a plan

### The intended result

With YOLO on, each phase opens a PR, clears CI and review, merges, and deletes its branch. After the final phase, the desired result is **one integration PR against the default branch with a UAT checklist ready to run**.

Blockers interrupt that rather than ending it. A phase the driver cannot get green becomes a small PR handed to the developer, and the run resumes unattended once CI clears. The developer is the exception handler, not a participant in the loop.

These finishing rules apply only with YOLO on. With YOLO off, the driver merges nothing, deletes nothing, and opens no integration PR. The developer sees and merges each phase individually.

A leftover phase branch weakens the signal that an existing branch still contains unmerged work. A checklist buried in an automatically merged phase PR is equally easy to miss. That is why the driver deletes merged phase branches and places cumulative UAT on the integration PR.


### The last phase merging is not the same as the feature being done

Phases target a feature branch so nothing reaches the default branch until the whole feature exists. That makes the last merge quietly anticlimactic: the branch is complete, every phase was reviewed against its siblings, and **nobody has been asked to look at the result as a thing**. A driver that goes idle there leaves the actual decision, does this land on `main`, unowned and unstated.

So completion under YOLO opens an **integration PR** from `target_branch` to the default branch, and stops. It is the one PR in the system the driver never merges, even under YOLO, and the asymmetry is the point: YOLO is a judgement that *phase* PRs are safe to land unattended, because the driver wrote them against a scope, verified them, and drove their gates. None of that reasoning transfers to a diff spanning every phase landing on the branch everything else builds on.

**Observed, on a six-phase plan: the driver merged the last phase and went idle without opening it.** Worth recording because the skill already said to, plainly, and the driver had read it. Two things caused it. Completion was the only transition in the skill with no inbound pointer, where every other one is chained, and the "after a merge" steps ended with *start whatever rows that unblocks*, which on the last merge finds nothing to start and terminates like a finished turn. And the plan's own prose called it "the only human merge gate", which the driver read as *don't open without permission* rather than *don't merge*. It then wrote that reading into the plan file and into its own scheduled check-ins, so every later wake re-read the mistake as settled fact.

That second half is the more interesting one. A driver that records a wrong rule has made it permanent, which is the cost of the plan file being durable memory, and it is an argument for transitions in the skill being explicit rather than inferable from context that a compaction can drop.

It is also where checks scoped to the default branch report for the first time. CodeQL default setup and hosted mobile build services are usually configured for the default branch only, so they never fire on a feature base. A plan can be entirely green and still meet those checks here for the first time. That is information for the user, not a gate for the driver to drive green.

### Why the cumulative UAT moved off the final phase PR

The first version put it on the final phase's PR. Under YOLO that PR is merged by the driver within minutes of opening, so the checklist was being written into something no human ever had to open. Technically recorded, functionally invisible. The failure looked exactly like success: a complete plan, a full checklist, and nobody prompted to run any of it.

The integration PR is the first artifact in the whole plan that a human must act on. A checklist has leverage only where a decision is already required, so that is where it goes. Where phases already target the default branch there is no integration PR, the final phase PR is the last thing anyone sees, and the original rule stands.

### Why it is one script rather than sections per phase

The first version grouped the cumulative list by phase, which is the order the work was produced in and no help at all to the person running it. Someone verifying a feature reads top to bottom once; phase numbers ask them to reassemble a user journey from a build history.

Grouping by phase also actively hides a defect. Phases can supersede each other's steps. One plan had phase 2 asking a tester to confirm a deleted event *comes back* and phase 4 changing that behaviour to *stays gone*, and under per-phase headings both survive, each correct within its own section and contradictory in the document. One list forces the contradiction into a single step, which is the point at which someone has to notice and resolve it.

### Deleting the merged branch

GitHub's merge API has no equivalent of the UI's "delete branch after merge" checkbox, so unless the driver deletes the branch itself, phases it merges leave branches behind while phases a human merges do not. The result is a branch list where staleness is uncorrelated with anything, and no way to tell finished work from abandoned work at a glance.

The guard is narrow on purpose. The branch must match `branch_prefix`, and must not be the plan branch or any `target_branch`. A driver that deletes the branch its own plan lives on has destroyed its own memory, which is the one failure in this system with no recovery path.

## Things deliberately not done

**Writing status inside the phase PR.** Breaks resume. Non-negotiable.

**Starting cloud sessions from a scheduler.** There's no API for it. cpm can notify that a session died; it cannot resurrect one, and pretending otherwise would be worse than the gap.

**Auto-rerunning CI until green.** One rerun per head commit, disclosed. Beyond that it launders a real failure into a pass.

**Renumbering phases during a replan.** Merged rows are a record of what shipped. Append or subdivide instead.

**A machine-readable status block alongside the human table.** Two sources of truth for one value diverge. The table is the status; front matter is config; Driver State is liveness.

## Known gaps

**Nobody notices a dead session.** A dying session cannot report its own death, so a stalled phase looks the same as a slow one. The natural fix is a watchdog on a cold heartbeat, which is what cpm already is, and the strongest argument for eventually connecting the two projects.

**The head can move between the final gate check and the merge.** `merge_pull_request` accepts no expected-SHA, so the window can be narrowed. Re-read the head as the last call before merging, but not closed.

**Rate limits are invisible.** A review consuming a large chunk of a subscription's allowance, re-running on every push, can hit a limit mid-phase. A rate-limited reviewer looks like a stalled gate.

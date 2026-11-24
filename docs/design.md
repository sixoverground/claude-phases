# Design notes

This document explains why `claude-phases` works the way it does. The detailed rules can look excessive without the failure that motivated them, and a rule whose reason is forgotten is easy to simplify back into a bug.

A narrative account of the runs behind these rules, including the missing integration PR and the six green checks that proved nothing, is in [I Let Claude Merge 38 PRs. Here’s What Broke.](https://www.craigphares.com/i-let-claude-merge-38-prs-heres-what-broke/).

## Design at a glance

Six principles account for most of the system:

| Principle | Consequence |
|---|---|
| A Claude Code session is temporary | The committed plan file is the durable state |
| State must survive a crash at any point | The driver records transitions before or immediately after external actions |
| Only one driver may advance a plan | Driver identity, heartbeats, and blob SHAs form an optimistic lock |
| A green check is weak evidence | Merge readiness is split into independent CI, review, and thread gates |
| YOLO delegates phase merges, not final release judgment | The driver may merge phase PRs, but never the final integration PR |
| The rules name no forge | The core asks questions; one reference per forge, GitHub or GitLab, says how that forge answers them |

If you are new to the project, read [The plan file is the state](#the-plan-file-is-the-state), [What a green check does not prove](#what-a-green-check-does-not-prove), and [Finishing a plan](#finishing-a-plan) first. The remaining sections explain edge cases and the real runs that uncovered them.

## The plan file is the state

A Claude Code cloud session is ephemeral. Its container is reclaimed after inactivity, its context compacts as it grows, and it can die at any moment: mid-implementation, between opening a PR and recording it, between merging and advancing.

That fact drives the design. A fresh session must reconstruct the world from the plan file and the forge, with no memory of what came before.

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

### The skill is not durable, so the plan points back at it

The plan file survives everything. The skill does not: a session that compacts, or that a check-in or webhook wakes, comes back holding the plan and GitHub and nothing of `phase-driver`. It knows the state and has forgotten the rules, and it does not know that it has forgotten them, because the plan looks complete and the compaction summary says it is driving a plan.

Observed, with YOLO on: the driver merged a green phase PR and stopped. Asked why it hadn't started the next phase when the skill plainly says to, it answered that it had not read the skill. It had been driving from the plan file and a compacted summary, and "start whatever that unblocks" was never in front of it. The skill's own rule for this case, re-read this file and continue, is in the one file such a session cannot see.

So the pointer has to live outside the skill. Two places. Every plan carries a fixed **For the driver** section that names the skill, says to invoke it before acting, and restates the single rule that was observed to drop, that a merge always advances the plan. And the check-in message the driver schedules for itself says to invoke the skill and reconcile, and nothing else. Between them they cover the ways a session comes back: from a merge webhook it must open the plan to record `Merged`, and from a check-in it reads the message.

The section restates one rule and not the rest, deliberately. Text copied into a plan is frozen at the version of the skill that wrote it, and a plan is read for weeks after it was written. The rule it carries is the invariant that has not changed since the first version. Everything else is a pointer.

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

### A nit never starts a push

Every push is a round: CI, a re-review, and a re-review on a fresh head finds something fresh to say. A driver that pushes for a naming preference has bought the next nit at the price of a whole round. So a minor finding gets a reply and a resolved thread, and rides along only with a push that was happening anyway. A reviewer's label doesn't decide what is minor: a finding about correctness, security or data is never minor, whatever it was tagged.

### Declining needs a destination

"Out of scope" with nowhere to put the finding means forgotten, and a driver that senses that will implement things rather than lose them. So each outcome has a home: work that belongs to this plan but not this phase goes to **Carried findings** in the plan file, a standalone defect goes to an issue, and a remark that changes nothing goes in the reply.

**The driver appends to that list and never adds a phase.** Turning a finding into a phase means writing scope, acceptance criteria, UAT and dependencies. That is planning, and it belongs to `phase-planner` and the person whose plan it is. A driver that adds phases because a reviewer suggested something is the same runaway that produced twenty-eight rounds, moved up a level where it costs more and is noticed later.

### Two stuck counters, because a moving head is not progress

`stuck.max_cycles` counts a gate failing for the same reason with an **unmoved head**. That is the right shape for a phase waiting on something that never arrives, and it is the wrong shape for the runaway above, which pushed a commit every round. By that counter the phase was making progress thirty-two times in a row.

So `stuck.max_review_rounds` counts the other failure: a phase that moves and gets nowhere. Two counters rather than one generalized counter, because the two states are genuinely different and a rule that tried to cover both would have to define progress, which is the thing in dispute.

**The count is derived, never remembered.** It is the number of distinct head commits a required reviewer has evaluated, re-read every wake, using the same test gate 6 already applies to decide whether a reviewer looked at a commit. Heads rather than review submissions, because answering two reviewers on one commit is one round and costs one push, and because a `check:` entry never submits a review at all, so a submission count would sit at zero for exactly the setups most able to loop. This is not an implementation detail; it is most of why the runaway was invisible. A session that tracks the tally loses it to compaction, and the next session sees one review comment, a rule telling it to answer, and no evidence that twelve rounds came before. Every wake honestly looks like the first one. Anything the driver must not lose has to be re-derivable or written down, and a round count is cheap to re-derive.

The exception proves the rule. Clearing the stop needs a baseline, because a derived count still reads above the threshold the moment after a person says carry on, and the row would block again forever. That baseline is the one number here that cannot be re-derived, so it goes in the plan, which is where everything the driver must not lose already lives.

**The stop is a report, not a question.** The observed failure was approved at four rounds by a person who had no basis to refuse: "shall I continue?" carries no information, so it collects a yes. The threshold therefore produces evidence, and the load-bearing line of it is whether the newest findings are new ground or the same class of finding resurfacing somewhere new. Four rounds of unrelated real bugs and four rounds of one problem in four files are the same number and opposite decisions.

### Stepping back at the threshold: the arbiter

The stop worked, and it moved the problem. A report at round three asked the right question about whether the findings were converging, and then waited for a person to answer it, so a plan running unattended under YOLO needed someone to steer it every time a phase ran long. Most of those stops had the same answer, and anyone looking at the whole phase could see it: the driver had been fixing one sibling of a mistake per round, or chasing nits a re-review kept turning up.

The driver could not see it, for a reason more rules wouldn't fix. It wrote every fix under review, and it comes to each round focused on the newest comment. "Fix the whole shape" was already in the skill; the driver still didn't step back, because nothing in the round made it.

So at the threshold the judgement moves to an **arbiter**, a subagent with a fresh context. It reads the phase's scope, the whole diff, and every finding from every round, and it hears what the driver changed but not what the driver thinks of the findings. It returns a verdict per group of findings and a bar for what still deserves a round, and the driver works the next few rounds under that verdict before a person is asked. The fresh context does most of the work; a different model (`fable` by default, against the driver's `opus`) adds independence on top.

The limits run one way. The arbiter can tell the driver to do more about a defect, never less. It cannot accept an in-scope correctness, security, or data defect, it rejects a finding only with reasoning someone can check, and it never widens a phase. Its verdict is posted on the PR before anything is acted on, because under YOLO the phase may merge before anyone reads it, and resolved threads with no fix need a reason someone can find.

**A person can ask for a fresh arbiter.** `arbitrate` at a stop is `continue` plus an arbitration at once, defined entirely by rules the driver already has rather than a new kind of verdict. The one subtlety is the baseline. An arbitration belongs to a budget only when its entry is above the baseline, and `continue` writes the baseline at the current count, so an arbitration recorded at that count would fall outside the budget and the next wake would arbitrate again. Writing the baseline one below makes the effective count 1, which is exactly the rule a repo's own stop rule already follows, reached by choosing the number rather than by an exception. One below is exact: two below would hand the phase a free round. The baseline, the entry and the row's return to `In Review` go in one plan write, so a crash cannot clear the stop without recording the arbitration.

**The stop for a person is still there**, after the arbiter's extra rounds. A loop that survives an arbiter calling for rework is a phase that needs replanning, and that is the person's call.

### Why the driver resolves a disagreement

This used to be the other way round. A scope decline resolved its thread and a disagreement on the merits stayed open for a person, on the reasoning that a thread saying the code is *wrong* is exactly what gate 5 exists to hold, and resolving it on the driver's say-so would overrule a reviewer by fiat.

In practice the open thread held the phase until a person came to settle a question the reply had usually already answered, and under YOLO nobody was coming. That is a block, and loud, which is the error this project prefers. But it was loud every time, about the same thing, and a person who has to settle it on every phase is steering the driver rather than supervising it.

So the driver resolves a review bot's thread when it disagrees, and the record moves into the reply, which has to be checkable: the line, test, invariant or caller that makes the finding false. A bare "I disagree" resolves nothing. Two things keep this from becoming a false pass. A reviewer that raises the same finding on a later head makes the driver look again, instead of repeating itself. And a thread a *person* opened still stays open, because there the person can answer, and resolving their comment for them would overrule someone who is present.

## Multi-repo

**One plan, one driver, N repos.** The plan lives in `home_repo` and is the only writer, which is what keeps the single-writer invariant intact across a cross-platform project.

**Independent repos run concurrently**, one open PR per repo, gated only by `Depends`. cpm is serial across repos. It skips a project when *any* repo has an open phase PR, which costs roughly 3× the wall-clock on a three-platform project for no correctness benefit.

**Blank `Depends` means "the previous row", not "no dependency."** Parallel rows must name their real dependency explicitly. Leaving it blank chains them, which is the opposite of the intent, and it's an easy mistake to make while writing a plan by hand.

**There is no atomic cross-repo merge.** Three PRs cannot land as one transaction, and no amount of prompt engineering changes that. Plans that need platforms to ship together express it as a dependency plus an explicit cutover phase.

## Where tests run

Running tests in-session is preferred: seconds instead of a CI round-trip, and a failure never costs a PR revision. But a Linux container has node and not Xcode, so `verify` is per repo and honest about it.

Where the session runs decides what is realistic. In a cloud container iOS is `ci`. In a session on a Mac with Xcode it is `local`, and the right local step there is a quick build for the simulator before each push, with the full suite left to CI: a build is what catches a phase that does not compile, in seconds, while the suite is slow and already runs on every PR. When a CI runner shares that Mac, the driver's build needs its own DerivedData and a simulator the runner is not using, and the runner one job at a time. Contention between the two is intermittent, which is why the planner's hygiene checklist states it as a rule rather than leaving it to be discovered.

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

### Milestones generalise the integration PR

The integration PR is the driver opening a PR from the feature branch to the default branch, and never merging it. A **milestone row** is the same act at a point the plan names rather than only at the end. The rule that made the integration PR safe carries over unchanged: the driver opens it, a person merges it, whatever YOLO says. A plan with no milestone rows behaves as before, its integration PR being the one implicit, final milestone.

They exist because "nothing reaches the default branch until the feature is whole" is sometimes false in practice. A later phase may need the earlier ones deployed, published or installed before it can be built or tested at all. The first plan to need this was this project's own: it builds a feature into the driver and then needs the *installed* driver to have it, and the marketplace serves only the default branch.

An explicit milestone opens with YOLO on or off, where the implicit one opens only under YOLO. A row someone put in the table is a checkpoint they planned, and later phases wait on it. YOLO only ever decided who merges phase PRs.

**A dependency replaces a pause.** The obvious way to make a later phase wait for a release is to tell the driver `pause`, ship by hand, and say `resume`. That works once, in the session where someone remembers to do it, and fails silently in the next. A phase that depends on the milestone row cannot start until the row is `Merged`, and the wait is in the table where any session can read it.

**Preparation is committed straight to the feature branch.** A version bump and a changelog section are not a phase, and a PR of their own into the feature branch would buy a review round for a diff that is reviewed again minutes later as part of the milestone PR. The milestone PR is their review, and a person merges it. Fixes to the milestone PR go the same way, and each one moves its head, so the reviewer and the checks see it again before anyone is told it is ready.

**The plan may not live on a branch a milestone ships.** A repo that deletes head branches on merge deletes the feature branch when the milestone merges, and the driver re-creates it from the default branch. A plan there would be deleted with it, and a driver whose plan has gone has lost its only memory. So a plan with milestone rows stays on the default branch, which narrows the older advice to keep a feature-branch plan on the feature branch.

**The re-sync moves a branch only when nothing can be lost.** It is the one place the driver applies force to a ref it did not create, so it refuses on any doubt. It re-creates a deleted branch, fast-forwards one that is behind, and moves one after a squash only if its head is exactly the head that was merged, with a lease on that head so a concurrent push is never overwritten. Anything else is left alone and reported.

## One core, one reference per forge

The driver was written against GitHub, and its rules were full of GitHub: `create_or_update_file` and a blob `sha`, check runs, `CHANGES_REQUESTED`, review threads. Supporting GitLab by adding a GitLab branch to every rule would have doubled each rule and made the two forges drift apart one sentence at a time.

So the rules were split from the mechanics first, before any GitLab code existed. `SKILL.md`, `gates.md` and `recovery.md` now ask questions any forge can answer: is this a draft, did every counted check pass, did a required reviewer evaluate this head, what is the write token. `forge-github.md` and `forge-gitlab.md` each answer them under the same headings. A plan names its forge per repo, and with no `forge` key it is GitHub, exactly as before the key existed.

The split was done behaviour-neutral, in its own phases, with GitHub as the only forge, so that any change in behaviour would show up as a change in a GitHub run rather than hide inside a new forge's first run. A forge reference the installed copy does not have stops the driver at Reconcile, before it writes anything: guessing one forge's API from another's reference is how a change request gets opened that nobody reviews.

## The review contract, and why the script owns the marker

On GitHub, a reviewer proves it looked at a commit through the forge: a review or an inline comment carries the commit it was made on, and a check run carries its head. GitLab gives a self-hosted reviewer nothing like that. A job can post notes, and a note says nothing about which commit it judged.

So a reviewer proves it with a line of its own, the review marker, `<!-- phases:review v=1 reviewer=<name> sha=<full sha> -->`, posted on the merge request after a review completes. [The review contract](review-contract.md) says what a reviewer must post and what it must never post, so that a reviewer built outside this repo can gate a phase. Gate 6 on GitLab reads markers and nothing else.

**The script writes the marker, never the model.** A model asked to end its review with a marker can write one for a review that failed halfway, or copy a sha from the diff it read rather than the one the pipeline ran on. So in `codex-mr-review` the sha comes from the pipeline's variables, the marker is posted by the script only after the review succeeded, and the model's own text is scrubbed of the reserved `<!-- phases:` prefix before anything is posted. A review that fails posts no marker, and the gate blocks, which is the right answer to a review that did not happen.

**A marker is plain text, so `logins` says whose count.** Anyone who can comment can type one. The plan's `marker` entry names the accounts allowed to post it, and a marker from anyone else is ignored.

## The watcher

A cloud session is woken by webhooks. A session on your own machine has none, and a GitLab project may be reachable only from that machine. Polling from inside the conversation would cost a model turn per poll, all night.

So the driver arms a small shell loop, the watcher, under Claude Code's Monitor. It polls the forge once a minute, keeps a snapshot per change request, and stays silent until something changes. Then it prints one line, which is a complete wake message: invoke the skill, reconcile this plan, and here is what changed. Waiting costs nothing, and each wake is a turn spent on a real event.

It holds no state that matters. Its snapshots only decide what to print, so a session that dies loses nothing with its watcher, and the next session's Reconcile arms a new one. It asks the forge itself first on every poll, so it reports a forge that stops answering once, backs off, and reports it answering again, even with no change request open. A night on a laptop that changes networks is two lines and no check-ins in between, not a stalled plan and not a message every half hour. And it prints its own fallback check-in by the wall clock, so a Mac that slept through the deadline checks in on the first poll after waking.

## Working through an outage

Before 0.16.0 an unreachable forge was a total wait: correct, and wasteful. The first real outage, hours of a dropped VPN against a self-managed GitLab, cost nothing only because the one open phase was already waiting on a person. Any phase mid-implementation would have sat idle for the length of the outage with all of its information already on the machine.

**What stays bound to the forge.** Claims and every other plan write, because the plan file is the lock that stops two drivers starting the same phase, and "a status write that could not be made means the action it describes has not started" is what makes crash recovery trustworthy. The merge gates, because their value is being the shared record a person can see. Pushes, and everything posted to a change request.

**What carries on.** Work under a claim that already landed: implementing, verifying locally and committing, and on a phase in review, fixing findings already read. The work exists only in the local clone until the forge answers, and that is the point: it is the same work a session that died mid-implementation leaves behind today, so recovery already has to cope with it, and Reconcile now reads the local clone before it would reset such a row.

**The claim is only as durable as its heartbeat.** `Heartbeat` is a plan write, so it cannot be refreshed while the home forge is down, and after 90 minutes a driver on another host may take the plan over and restart the phase. That risk is accepted rather than avoided. The guard sits at reconnect, not at a timer: before anything is pushed, the driver checks its `Driver-ID` and rewrites `Heartbeat` with the write token. A push is not a compare-and-swap, and the token-checked write in front of it is what makes it safe. A claim lost meanwhile means nothing is pushed and the work is kept, never deleted, on a `-orphaned` branch.

**Why no cap by default.** Losing the time is a bigger loss than spending it on work that might be orphaned, and with one driver the takeover never happens. The cap exists for the case where it can: `offline.max_minutes` stops new offline work once the heartbeat is that old, and a team with drivers on more than one machine sets it to the takeover threshold, 90. `offline: false` restores the total wait.

**A phase in review does not get to skip its budget.** Fixes made offline are the first path that prepares a push without the forge having evaluated anything. So the review count is derived again on reconnect, never carried across the outage, and the budget table is applied before the push: an outage cannot carry a phase past an arbitration or a stop.

**The local review pass counts for nothing on the forge.** `review.local` runs a reviewer on this machine before each push, so a round is not spent on what it would find. It writes no marker and is never a reviewed head, because a local run is invisible to everyone but the driver: if it counted, the review budget and gate 6 would rest on something nobody else can see. It runs once per push for the same reason, since nothing outside the driver would notice it looping.

## Authorship stamps

The driver used to know who wrote a note by its account. Its own notes came from its account, a reviewer's from a bot account, and a person's from anyone else. With the driver, the reviewer and the person all on one account, which is how most people would run GitLab, every one of those readings collapses. The watcher would ignore the person, and the resolve rules would treat the reviewer's findings as the person's own threads.

So every note says who wrote it, in a hidden line. The driver ends everything it posts with `<!-- phases:driver v=1 -->`. A reviewer meeting the contract's version 1.1 puts `<!-- phases:reviewer v=1 reviewer=<name> -->` in every note it posts. A note with neither is a person's, whatever account posted it.

A stamp is trusted only from an account allowed to write it: the driver's from the account the driver acts as, a reviewer's from that reviewer's `logins`. Anything the reading is unsure of counts as a person's, because a person's thread staying open and a person's note waking the driver are the safe sides of both mistakes. The driver never writes another actor's line, not a marker, not a reviewer stamp, and not a hidden line copied out of someone else's note.

Two identities still work as they always did. A reviewer on its own account is a reviewer by its account, with no stamp needed. The stamps decide only where the account cannot.

## The first GitLab run

A toy plan on a private gitlab.com project: two phases and a milestone, driven from a local session on a Mac, with the project's only runner on that same Mac and Codex reviewing through `codex-mr-review`. One account did everything: the driver, the reviewer's token and the maintainer's own comments. The plan, and every wake it took, are in [`examples/gitlab-local.md`](../examples/gitlab-local.md).

It confirmed the design and corrected the prose:

- **The stamps carried the one-account case.** Nineteen notes across three merge requests, all from one account. The driver read the reviewer's finding as a bot's thread, resolved it after the fix, and left the maintainer's own thread open after disagreeing with it. The watcher woke for the reviewer and for the person, and never for the driver's own replies. Nothing in the account told them apart; only the stamps did.
- **Recovery and waiting behaved as written.** A session killed mid-phase was replaced by one that took over on the same host and finished the phase from the plan and the forge. A network outage was reported once and waited out, with nothing marked `Blocked`. The recovery was not from a truly cold start, since the new session was resumed with the old one's conversation, and the next run should start one with none.
- **Three things the references had wrong or left open.** `glab mr create -R` still needs a GitLab remote in the current directory. A runner under launchd gets a `PATH` that finds neither Node nor Codex until you set one at registration. And `[skip ci]` does skip pipelines for plan commits made through the Files API, which the reference had not been able to say. Each is now corrected where it lives, naming the run.
- **One thing a phase on the same Mac should expect.** The runner and Codex share the network, so an outage fails a review in progress as well as the driver's polls. The driver's one retry per head covers it.

What it did not reach: a self-managed instance, a Developer-role token, a protected target branch, a reviewer on an identity of its own, and the re-sync of a milestone branch, which the driver correctly skipped because no row still targeted it. A self-managed instance differs on most of those, so the first plan on one is the next test.

## Things deliberately not done

**Writing status inside the phase PR.** Breaks resume. Non-negotiable.

**Starting cloud sessions from a scheduler.** There's no API for it. cpm can notify that a session died; it cannot resurrect one, and pretending otherwise would be worse than the gap.

**Auto-rerunning CI until green.** One rerun per head commit, disclosed. Beyond that it launders a real failure into a pass.

**Renumbering phases during a replan.** Merged rows are a record of what shipped. Append or subdivide instead.

**A machine-readable status block alongside the human table.** Two sources of truth for one value diverge. The table is the status; front matter is config; Driver State is liveness.

**Shipping the watcher as a script.** It is a template in `watching.md` that the driver fills in and runs, not a file installed with the plugin. A script would need installing, versioning and a path on every machine, and a skill uploaded to claude.ai cannot carry one. The template travels with the reference that explains it.

**Posting to GitHub from `codex-mr-review`.** GitHub has its own Codex reviewer, which the driver already reads. A second way to get the same review there would be a second setup to keep working for no new capability.

**Queueing plan writes to replay when the forge answers.** The file update's token check would still catch a conflict on replay, but by then the work it describes was done without a claim, which is exactly what the claim exists to prevent. Offline work happens only under a claim that already landed.

**A `required` local review.** A local pass that had to succeed would make a push depend on a tool installed on one machine and an API outside the forge, and it would invite treating the local run as proof of review. It is optional, skipped and disclosed where it cannot run, and the CI review stays the gate.

**New rules for reading a self-hosted Codex review.** On GitLab, Codex's review is read through the marker, exactly as any other reviewer meeting the contract would be. Gate 6 has no Codex-specific case there, so a different reviewer, a Claude review job for example, needs no change to the driver.

## Known gaps

**Nobody notices a dead session.** A dying session cannot report its own death, so a stalled phase looks the same as a slow one. The natural fix is a watchdog on a cold heartbeat, which is what cpm already is, and the strongest argument for eventually connecting the two projects.

**The head can move between the final gate check and the merge, on GitHub.** `merge_pull_request` accepts no expected-SHA, so the window can be narrowed. Re-read the head as the last call before merging, but not closed. On GitLab the merge carries the gated head, `glab mr merge --sha`, and GitLab's documentation says it merges only if the head is still that commit, which closes the window. The GitLab run merged that way but never raced it, so the refusal itself is still documented rather than seen.

**What the GitLab run left untested.** A self-managed instance, a token with the Developer role, a protected target branch, a reviewer on an identity of its own, moving a feature branch back in line after a milestone on GitLab, and recovery from a truly cold start there. The GitLab references say so where each would matter, and say what to do when one fails.

**Rate limits are invisible.** A review consuming a large chunk of a subscription's allowance, re-running on every push, can hit a limit mid-phase. A rate-limited reviewer looks like a stalled gate.

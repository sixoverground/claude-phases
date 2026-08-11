---
name: phase-driver
description: Execute a phased implementation plan from docs/plans/*.md. Pick the next phase, implement it, open a PR, watch CI and review, and merge when the gates pass. Use when asked to run, continue, resume, or drive the next phase of a plan, to check the status of a plan or its open phase PRs, or to merge, pause, skip, or re-plan a phase. Also use when a PR webhook or a check-in wakes the session and a plan file is present.
---

# Phase driver

You execute a phased plan. The plan file is your only durable memory: the session running you can be reclaimed at any moment, and the next one starts knowing nothing. Write state down before you act on it, and everything survives.

Read `references/recovery.md`, `references/gates.md`, and `references/vocabulary.md` when you reach the steps that need them, not up front.

## Golden rules

1. **Never modify the plan file from a phase branch.** Plan writes go to `home_repo`'s **plan branch**, always.
2. **Write status before the action it describes**, not after. Claim before branching; record the PR before waiting on it.
3. **Pass the `sha` you just read** on every plan write. A stale sha means another driver moved: re-read, retry, and don't overwrite.
4. **Every plan commit message ends `[skip ci]`.**
5. **One phase = one PR = one repo.**
6. **Re-read the head SHA immediately before anything irreversible** and re-check the gate against it.
7. **If your context was compacted or you don't remember starting this: re-read this file and the plan, run Reconcile, and continue.** That is the normal path, not an error.
8. **Never claim work you didn't do.** If tests didn't run, say so in the PR body. If you can't tell why CI failed, say that and link the run.

## 1. Find the plan

Look for `docs/plans/*.md` in the current repo. More than one, and no phase named: list them and ask.

Parse the front matter under `phases:`. That is your entire configuration. Resolve per-repo settings by deep-merging each repo's entry over `defaults`. Never look for configuration anywhere else; there is no other config file.

**The plan branch** is `plan_branch`, or the home repo's default branch when that key is absent. Every read and every write of the plan file uses it. It is usually the default branch; on feature-branch work. Where phases target `feature/x` and nothing reaches `main` until the feature is whole. The plan lives there instead, so that status is visible without merging a phase PR. If `plan_branch` names a branch that doesn't exist, stop and say so. Never fall back to the default branch: a plan read from the wrong branch reports every phase as unstarted, and the driver would start them all a second time.

## 2. Reconcile, always, before anything

Run this on every invocation and every wake, including when you think you know the state. It is cheap and it is what makes crash recovery work.

1. Read the plan: front matter, the PR Sequence Table, the Driver State block.
2. Check the **Driver-ID** rules below.
3. For **every** non-terminal row, ask GitHub what's actually true: `list_pull_requests` filtered by that row's head branch in that row's repo, then `pull_request_read{get}` for any match.
4. Apply `references/recovery.md` per row. Where the plan and GitHub disagree, **GitHub is the truth**, fix the plan, never assume.
5. Rewrite `Heartbeat` and, if you took over, `Driver-ID`.

### Driver-ID

| Condition | Action |
|---|---|
| `Driver-ID` matches the one you hold | It's you. Proceed regardless of heartbeat age |
| Different ID, `Heartbeat` under 90 minutes old | Another driver is live. Report and stop; do not touch the plan |
| Different ID, `Heartbeat` stale | Take over: mint a new random ID, write it, continue |
| No ID, or `-` | Unclaimed. Claim it |

You hold an ID only if you minted it in this session. After compaction you may have forgotten; if you can't establish that you hold it, treat it as someone else's.

## 3. Start phases

Startable rows are `Pending`, with every id in `Depends` now `Merged` or `Skipped` (blank `Depends` means the row above), and **no other open phase PR in that row's repo**. Start every startable row. Repos run in parallel, and only declared dependencies serialize anything. Honour `max_concurrent` if set.

For each, in order:

1. **Ensure the repo is reachable.** If it isn't in the session's scope, add it and clone it. If access is denied, mark that row `Blocked` with the error and carry on with the others. One inaccessible repo must not stall the rest.
2. **Commit `In Progress`** to the plan branch. This is the claim, and it comes first.
3. **Branch** from that repo's `target_branch`, named from the row's `Branch`.
4. **Implement** the phase against its Phase Details: scope, acceptance criteria, risks. Match the surrounding code. Stay inside the phase's scope: if you find unrelated problems, note them in the PR body rather than fixing them.
5. **Verify** per that repo's `verify`:
   - `local`. Run the tests and build. They must pass before you push.
   - `ci`. Don't attempt a local build.
   - `auto`. Try local; if the toolchain isn't there, fall back to CI.
   - `none`. Skip verification.
6. **Push and open the PR**, titled `Phase N: <scope>`. Body: the acceptance criteria as a checklist, **which verification path actually ran**, the UAT checklist per the rules below, anything out of scope you noticed, and `Driven by phase-driver, do not edit the plan file in this PR`.
7. **Commit `In Review`** and the `Link`, immediately, before subscribing, before any wait. A PR that exists but isn't recorded is the most expensive state to recover from.

### UAT checklists

UAT is what a **human** does by hand. It is not the acceptance criteria, which you verified yourself. Never merge the two, and never tick a UAT box. You are not the one who performs it.

Start from the phase's `**UAT.**` items in Phase Details, then refine against what you actually built: you may have implemented it differently, and you know what's adjacent enough to have broken. Write steps someone can follow without reading the diff. What to open, what to do, what they should see. If a phase has no UAT section, write one.

Which checklist goes where depends on YOLO, because YOLO decides whether anyone is stopping to look:

- **YOLO off.** This PR carries its own phase's UAT, **plus** everything in `UAT-pending`, assembled into one script by the rules below. Then clear those ids. Someone is looking at this PR; give them everything nobody has verified yet.
- **YOLO on.** Omit UAT from the PR and append this phase's id to `UAT-pending` when it merges. The cumulative script. Everything in `UAT-pending`, plus the end-to-end flows that only make sense once every phase has landed. Goes on the **integration PR** at the end of the plan (§8), or on the **final phase**'s PR if no integration PR will exist because phases target the default branch directly. Clear the list when it lands somewhere.

Read the YOLO state **at the moment you open the PR**, not from memory. Toggling mid-plan is expected and `UAT-pending` is what makes it safe: turn YOLO off after three unattended merges and the next PR carries those three alongside its own.

§8 covers what happens if the plan finishes and the list never landed anywhere.

Where a repo sets `uat: false`, skip everything in this section, including the assembly rules below. Under YOLO an integration PR still opens at the end, it is worth having regardless, just without a checklist.

### Assembling more than one phase's UAT

**Write a test script, not a changelog with checkboxes.** Whoever runs it wants to sit down once and verify the feature; they do not care which phase produced which step, and phase numbers are an artifact of how the work was built rather than of how it is tested.

So when a PR carries more than one phase's worth:

1. **One list.** No per-phase sections. Group by theme or by user journey only where that genuinely helps someone execute it. Setup, then connect, then edit, then disconnect. If the feature is small, no headings at all.
2. **Ordered so it can be run top to bottom.** Anything that blocks everything else goes first, accounts, domains, migrations, env vars, and steps that depend on earlier state follow it. A script that has to be re-read to find a runnable order is a list, not a script.
3. **Merge duplicates.** Adjacent phases routinely specify the same click. One step, once.
4. **Reconcile contradictions, and say so in the step itself.** A later phase can invalidate an earlier phase's step, and grouping by phase hides that because both survive under their own heading. If phase 2 says *confirm the event comes back* and phase 4 changed that to *confirm it stays gone*, the script gets **one** step describing what the code does now, with a trailing note in that same step naming what it supersedes. *"This reverses what phase 2 specified; phase 4 changed a remote delete to unlink"*. The note belongs there and nowhere else: whoever runs the script may have read the plan, and without it a correct step looks like a bug they have just found. Fix the stale line in the plan's Phase Details too. A checklist that disagrees with the code is as harmful as a comment that does, and worse, because a human executes it and believes it.
5. **Say what has not been verified.** If nothing has been exercised against a live third party or a real device, put that at the top in a sentence. It is the single most useful line in the document, and it is invisible from the checkboxes alone.

Where each step came from stops mattering the moment the plan is done. What matters is whether someone can run the thing end to end and know the feature works.

## 4. Watch

Subscribe to PR activity for each open phase PR. Schedule a check-in 45–60 minutes out if you can. Webhooks don't reliably deliver CI success or new pushes, and a missed event otherwise stalls the plan silently.

Message the user what you started and where. Then **end your turn.** Sleeping is correct; there is nothing to poll.

## 5. On every wake

Reconcile first. Then handle what woke you, against the row it belongs to:

- **A check failed.** Read `references/gates.md` for how to get the failure text for that repo's `ci.logs` setting. Fix it and push. One re-run per head commit is allowed for a suspected flake, and say in the PR that you re-ran it. Beyond that, treat it as a real failure.
- **A review comment or thread.** Address it in code, push, then resolve the thread. Never resolve a thread you disagree with: reply explaining why, and leave it open for a human.
- **A merge conflict.** Update the branch from base; if that fails, resolve it in the working tree and push. After two failed attempts, mark `Blocked`.
- **The head moved.** Discard that row's gate result and re-evaluate from scratch. A gate result is only ever valid for the commit it was computed against.
- **The PR was merged by anyone.** Go to step 7. This is expected, not an anomaly.
- **A message from the user**, see `references/vocabulary.md`.
- **Nothing actionable**, re-arm the check-in and end the turn.

## 6. Evaluate the gate

When a PR has no outstanding work, evaluate `references/gates.md` against it, using that repo's resolved config. Then:

- **YOLO on.** Re-read the head SHA as your *last* read before merging, with no other calls in between, and merge with that repo's `merge.method`. Then **delete the phase branch**, unless the repo sets `merge.delete_branch: false`.
- **YOLO off.** Do not merge. Tell the user it's ready, with the PR link and a per-gate summary, and set the row's `Note` to `ready to merge`. Re-ping only if the head moves and it passes again. Don't nag on a timer.

**Deleting the branch is yours to do because the API will not.** GitHub's merge endpoint has no equivalent of the UI's "delete branch after merge" checkbox, so a driver that merges and stops leaves a branch behind for every phase it shipped, while phases a human merged get cleaned up. Nobody notices until the branch list is half stale and it is no longer obvious which of them are finished.

Delete only a branch **you** created: it must match that repo's `branch_prefix`, and it must not be the plan branch or any repo's `target_branch`. Those three checks are the whole guard, and skipping them is how a driver deletes the branch its own plan lives on.

A failed delete is not a failed merge. Branch protection or a ruleset can forbid it, and so can the environment the session runs in — a sandboxed one may permit pushes and PR operations while refusing ref deletion at both the git and API layers. Say so once and carry on, because the phase is merged either way and nothing downstream depends on the branch being gone.

**A second failure for the same reason is not incidental, so stop reporting it as though it were.** Say once that deletions are refused here and recommend turning on GitHub's own *Automatically delete head branches* (Settings → General), which runs server-side on merge and needs nothing from the driver. Without that, the driver shrugs once per phase for the length of the plan and the user finds a fully stale branch list at the end — losing the signal the deletion exists to preserve, that a branch which still exists means work which has not landed.

`YOLO` lives in the Driver State block. A repo may also pin `yolo: false` in front matter, which wins, config can restrict, never enable.

**If a gate fails for the same reason on consecutive wakes with an unmoved head**, count it. At `stuck.max_cycles` (default 5), mark that row `Blocked` with the reason and tell the user. Count per row: one stuck platform must not stall the others.

## 7. After a merge

However the PR merged. You, the user from their phone, or anyone else:

1. Unsubscribe from that PR.
2. **Commit `Merged`** to the plan branch. If YOLO was on and the PR carried no UAT checklist, append that phase's id to `UAT-pending` in the same write.
3. Comment on the PR and tell the user.
4. **Start whatever rows that unblocks**, in the same turn, unless `Driver: paused`.

A merge always advances the plan. YOLO changes who presses the button, never whether the plan moves.

## 8. Finishing the plan

When every row is `Merged` or `Skipped`, in this order: **open the integration PR if YOLO is on**, then set `Driver: idle`, clear `Active`, post a summary of what shipped, and stop.

**Everything in this section is YOLO-only.** With YOLO off the developer merged every phase themselves and read every checklist as they went. They know exactly where the branch stands, and opening a PR to their default branch on their behalf presumes a decision they are already positioned to make. The handoff exists because YOLO means nobody was watching.

### The integration PR

Phases usually target a feature branch rather than the default one, so that nothing reaches `main` until the feature is whole. When the last phase merges, that branch is finished and nobody has been asked to look at it as a whole. Every review so far was of one phase against its siblings.

So, with YOLO on: **for each repo whose `target_branch` is not its default branch and which merged at least one phase, open a PR from `target_branch` to that repo's default branch.** Title it `<project>: <n> phases`. Body: what shipped, phase by phase with links; anything the plan recorded as deliberately out of scope; and any setup the feature needs that no PR could contain.

**Never merge it. YOLO opens this PR and does not merge it**, and that is not an inconsistency. YOLO is a judgement about *phase* PRs. Work the plan produced, scoped by the plan, verified by the driver, gated per phase. This one is the whole feature landing on the branch everything else builds on, and none of that reasoning reaches it. Open it, report it, go idle.

Don't wait on its CI either. Checks that were scoped to the default branch may report here for the first time. CodeQL and mobile build services commonly are, and a first red result on a check no phase ever saw is information for the user, not a gate for you to drive to green.

**The cumulative UAT checklist goes on the integration PR**, not on the final phase's PR, whenever an integration PR will exist. With YOLO on the final phase PR is merged by the driver within minutes of opening, so a checklist placed there is written into something nobody had to read. The integration PR is the first thing on the whole plan a human must act on, which is the only place a checklist has leverage. Clear `UAT-pending` when you open it.

With more than one repo, the **home repo's** integration PR carries the entire script across all repos, and the others link to it. UAT is end-to-end by nature; splitting it by repo produces two lists that each describe half a user journey, the same reason it is not split by phase.

Where `target_branch` *is* the default branch there is no integration PR to open, and the rules stand as they were: the final phase PR carries the cumulative checklist. Same with YOLO off, where every PR carried its own UAT as it went and there is no backlog to hand over.

### The fallback

If the plan completes with `UAT-pending` non-empty and no integration PR was opened. Every repo targets its default branch, or the final phase was skipped or merged before you assembled the list. Open a GitHub issue titled `UAT: <project>` with the outstanding items. Never drop them; unverified work that nobody knows is unverified is the thing this exists to prevent.

## Writing to the plan

`create_or_update_file` against `home_repo` on the plan branch, passing the `sha` you read at the start of the transition. Message: `chore(plan): <project> phase <N> -> <Status> [skip ci]`.

Re-read that `sha` at the start of **every** transition. When the plan branch is also a `target_branch`, merging a phase PR moves it, and a sha cached from before the merge is already stale.

On a sha conflict: re-read, re-apply your change, retry. Three failures means another driver is active, stop and report rather than forcing it.

If the plan branch rejects direct commits, switch to `plan_writes: plan-pr`. Each transition becomes a single-file PR with auto-merge, targeting the plan branch, and tell the user once that you've done so.

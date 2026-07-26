---
name: phase-driver
description: Execute a phased implementation plan from docs/plans/*.md — pick the next phase, implement it, open a PR, watch CI and review, and merge when the gates pass. Use when asked to run, continue, resume, or drive the next phase of a plan, to check the status of a plan or its open phase PRs, or to merge, pause, skip, or re-plan a phase. Also use when a PR webhook or a check-in wakes the session and a plan file is present.
---

# Phase driver

You execute a phased plan. The plan file is your only durable memory: the session running you can be reclaimed at any moment, and the next one starts knowing nothing. Write state down before you act on it, and everything survives.

Read `references/recovery.md`, `references/gates.md`, and `references/vocabulary.md` when you reach the steps that need them — not up front.

## Golden rules

1. **Never modify the plan file from a phase branch.** Plan writes go to `home_repo`'s default branch, always.
2. **Write status before the action it describes**, not after. Claim before branching; record the PR before waiting on it.
3. **Pass the `sha` you just read** on every plan write. A stale sha means another driver moved — re-read and retry, don't overwrite.
4. **Every plan commit message ends `[skip ci]`.**
5. **One phase = one PR = one repo.**
6. **Re-read the head SHA immediately before anything irreversible** and re-check the gate against it.
7. **If your context was compacted or you don't remember starting this: re-read this file and the plan, run Reconcile, and continue.** That is the normal path, not an error.
8. **Never claim work you didn't do.** If tests didn't run, say so in the PR body. If you can't tell why CI failed, say that and link the run.

## 1. Find the plan

Look for `docs/plans/*.md` in the current repo. More than one, and no phase named: list them and ask.

Parse the front matter under `phases:` — that is your entire configuration. Resolve per-repo settings by deep-merging each repo's entry over `defaults`. Never look for configuration anywhere else; there is no other config file.

## 2. Reconcile — always, before anything

Run this on every invocation and every wake, including when you think you know the state. It is cheap and it is what makes crash recovery work.

1. Read the plan: front matter, the PR Sequence Table, the Driver State block.
2. Check the **Driver-ID** rules below.
3. For **every** non-terminal row, ask GitHub what's actually true: `list_pull_requests` filtered by that row's head branch in that row's repo, then `pull_request_read{get}` for any match.
4. Apply `references/recovery.md` per row. Where the plan and GitHub disagree, **GitHub is the truth** — fix the plan, never assume.
5. Rewrite `Heartbeat` and, if you took over, `Driver-ID`.

### Driver-ID

| Condition | Action |
|---|---|
| `Driver-ID` matches the one you hold | It's you. Proceed regardless of heartbeat age |
| Different ID, `Heartbeat` under 90 minutes old | Another driver is live. Report and stop — do not touch the plan |
| Different ID, `Heartbeat` stale | Take over: mint a new random ID, write it, continue |
| No ID, or `-` | Unclaimed. Claim it |

You hold an ID only if you minted it in this session. After compaction you may have forgotten — if you can't establish that you hold it, treat it as someone else's.

## 3. Start phases

Startable rows are `Pending`, with every id in `Depends` now `Merged` or `Skipped` (blank `Depends` means the row above), and **no other open phase PR in that row's repo**. Start every startable row — repos run in parallel, and only declared dependencies serialize anything. Honour `max_concurrent` if set.

For each, in order:

1. **Ensure the repo is reachable.** If it isn't in the session's scope, add it and clone it. If access is denied, mark that row `Blocked` with the error and carry on with the others — one inaccessible repo must not stall the rest.
2. **Commit `In Progress`** to the default branch. This is the claim, and it comes first.
3. **Branch** from that repo's `target_branch`, named from the row's `Branch`.
4. **Implement** the phase against its Phase Details: scope, acceptance criteria, risks. Match the surrounding code. Stay inside the phase's scope — if you find unrelated problems, note them in the PR body rather than fixing them.
5. **Verify** per that repo's `verify`:
   - `local` — run the tests and build. They must pass before you push.
   - `ci` — don't attempt a local build.
   - `auto` — try local; if the toolchain isn't there, fall back to CI.
   - `none` — skip.
6. **Push and open the PR**, titled `Phase N: <scope>`. Body: the acceptance criteria as a checklist, **which verification path actually ran**, anything out of scope you noticed, and `Driven by phase-driver — do not edit the plan file in this PR`.
7. **Commit `In Review`** and the `Link`, immediately — before subscribing, before any wait. A PR that exists but isn't recorded is the most expensive state to recover from.

## 4. Watch

Subscribe to PR activity for each open phase PR. Schedule a check-in 45–60 minutes out if you can — webhooks don't reliably deliver CI success or new pushes, and a missed event otherwise stalls the plan silently.

Message the user what you started and where. Then **end your turn.** Sleeping is correct; there is nothing to poll.

## 5. On every wake

Reconcile first. Then handle what woke you, against the row it belongs to:

- **A check failed** — read `references/gates.md` for how to get the failure text for that repo's `ci.logs` setting. Fix it and push. One re-run per head commit is allowed for a suspected flake, and say in the PR that you re-ran it. Beyond that, treat it as a real failure.
- **A review comment or thread** — address it in code, push, then resolve the thread. Never resolve a thread you disagree with: reply explaining why, and leave it open for a human.
- **A merge conflict** — update the branch from base; if that fails, resolve it in the working tree and push. After two failed attempts, mark `Blocked`.
- **The head moved** — discard that row's gate result and re-evaluate from scratch. A gate result is only ever valid for the commit it was computed against.
- **The PR was merged by anyone** — go to step 7. This is expected, not an anomaly.
- **A message from the user** — see `references/vocabulary.md`.
- **Nothing actionable** — re-arm the check-in and end the turn.

## 6. Evaluate the gate

When a PR has no outstanding work, evaluate `references/gates.md` against it, using that repo's resolved config. Then:

- **YOLO on** — re-read the head SHA as your *last* read before merging, with no other calls in between, and merge with that repo's `merge.method`.
- **YOLO off** — do not merge. Tell the user it's ready, with the PR link and a per-gate summary, and set the row's `Note` to `ready to merge`. Re-ping only if the head moves and it passes again. Don't nag on a timer.

`YOLO` lives in the Driver State block. A repo may also pin `yolo: false` in front matter, which wins — config can restrict, never enable.

**If a gate fails for the same reason on consecutive wakes with an unmoved head**, count it. At `stuck.max_cycles` (default 5), mark that row `Blocked` with the reason and tell the user. Count per row: one stuck platform must not stall the others.

## 7. After a merge

However the PR merged — you, the user from their phone, or anyone else:

1. Unsubscribe from that PR.
2. **Commit `Merged`** to the default branch.
3. Comment on the PR and tell the user.
4. **Start whatever rows that unblocks**, in the same turn — unless `Driver: paused`.

A merge always advances the plan. YOLO changes who presses the button, never whether the plan moves.

When every row is `Merged` or `Skipped`: set `Driver: idle`, clear `Active`, post a summary of what shipped, and stop.

## Writing to the plan

`create_or_update_file` against `home_repo` on its default branch, passing the `sha` you read at the start of the transition. Message: `chore(plan): <project> phase <N> -> <Status> [skip ci]`.

On a sha conflict: re-read, re-apply your change, retry. Three failures means another driver is active — stop and report rather than forcing it.

If the default branch rejects direct commits, switch to `plan_writes: plan-pr` — each transition becomes a single-file PR with auto-merge — and tell the user once that you've done so.

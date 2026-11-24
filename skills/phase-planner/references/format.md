# Plan file format

A plan is one markdown file, committed to a repo on the project's forge, that describes a piece of work split into phases, and doubles as the durable state of the driver executing it.

It lives at `docs/plans/<project>.md` in the project's **home repo**.

Three parts:

1. **Front matter.** Immutable configuration.
2. **PR Sequence Table**. One row per phase, with a `Status` column that is the execution cursor.
3. **Driver State**. Mutable runtime state: liveness, and the toggles you flip from your phone.

No value ever appears in two of those places. Config is config, per-phase status is the table, runtime state is Driver State.

A fourth section, **Carried findings**, appears only once something has been recorded in it. It holds work the driver was told about and deliberately did not do. It is not state, and nothing reads it to decide what to run.

One more block, **For the driver**, sits between the title paragraph and the table in every plan. It is fixed text, not state, and nothing reads it to decide what to run either. It exists to send a session that opens this file without the driver skill in context back to the skill. See [For the driver](#for-the-driver) below.

---

## Why the plan file holds the state

A Claude Code cloud session is ephemeral. Its container is reclaimed after inactivity, its context compacts as it grows, and it can die at any point: mid-implementation, between opening a PR and recording it, or between merging and advancing.

So the plan file is not documentation that happens to track progress. **It is the only durable state.** A fresh session must be able to reconstruct everything from the plan file plus what GitHub reports, with no memory of what came before. Every design rule below follows from that.

Two invariants make it work:

- **Status is written to the home repo's plan branch, never inside a phase PR.** A status written inside a PR is invisible until that PR merges, so a fresh session would see `Pending` for a phase that already has an open PR, and start it again.
- **Phase PRs never modify the plan file.** One writer means a squash merge can never conflict with its own bookkeeping, no matter how far the plan branch has moved.

The **plan branch** is `plan_branch`, defaulting to the home repo's default branch. What the first invariant actually requires is a branch that no phase PR modifies and that is readable without merging one. The default branch is the usual answer, not the only one. Feature-branch work, where every phase targets `feature/x` and nothing reaches `main` until the feature is whole, puts the plan on `feature/x` and satisfies it just as well, unless the plan has [milestone rows](#milestone-rows). A milestone ships `feature/x` and the branch is deleted and re-created when it merges, so a plan with milestone rows stays on the default branch.

---

## For the driver

The plan file is the durable memory, and the skill is not. A session that compacts, or that is woken by a check-in or a PR webhook, comes back with the plan and with GitHub, and with none of `phase-driver` in its context. It knows the state and has forgotten the rules. Observed on a real run: a driver in that condition merged a green phase PR and stopped, because "start whatever that unblocks" was a rule in the skill and the skill was gone. The skill's own instruction for a compacted session, re-read this file and continue, cannot reach a session that has lost the file it is written in.

So every plan carries a pointer back. Immediately after the title paragraph, before `## PR Sequence`, verbatim from the template:

```markdown
## For the driver

This plan is executed by the `phase-driver` skill, and nothing in this file stands in for it. If you are acting on this plan and that skill is not in your context, because the session was compacted or was woken by a check-in or a webhook, invoke `phase-driver` before you do anything else, then reconcile. The rule a session without it most often drops: **a merge always advances the plan.** After any phase PR merges, start whatever it unblocks in the same turn unless `Driver: paused`, and when the last row merges, finish the plan by the skill's finishing steps rather than going idle.
```

It restates exactly one rule, the one that was observed to drop, and otherwise points at the skill. The plan is not the place for the rest: a rule copied into a plan is frozen at the version that wrote it, and the driver reads a plan far longer than the planner writes one.

The planner writes it. The driver adds it to a plan that predates it, on the plan branch, in its next status write. Neither edits its text.

That self-heal reaches only a session that still holds the driver skill. A plan already in flight under a session that has compacted is in exactly the state the section exists to rescue, and no code can reach it: invoke `phase-driver` once by hand in that session, or paste the section in. Either is a one-time step per plan.

---

## 1. Front matter

YAML, under a top-level `phases:` key. Every field is optional except `project`, `home_repo`, and at least one entry in `repos`. Defaults are listed in [configuration.md](configuration.md).

```yaml
---
phases:
  project: acme
  home_repo: acme/acme-web         # where THIS file lives; the only repo the driver writes state to

  defaults:                        # inherited by every repo, overridable per repo
    branch_prefix: claude/
    target_branch: main
    verify: auto
    merge: { method: squash }
    ci:
      required: []
      allow_none: false
      dispatch: auto
      logs: auto
    review:
      required: []
      changes_requested_blocks: true
      threads_must_resolve: true
    stuck:
      max_cycles: 5
      max_review_rounds: 3
      arbiter: { model: fable, extra_rounds: 3 }

  repos:
    acme/acme-web: {}

  max_concurrent: null
---
```

Per-repo values deep-merge over `defaults`. A single-repo project lists one repo and inherits everything.

---

## 2. PR Sequence Table

| Column | Required | Meaning |
|---|---|---|
| `PR` | yes | Ordinal, for humans reading the table |
| `Branch` | yes | The phase branch, prefixed with `branch_prefix`. On a [milestone row](#milestone-rows), the repo's `target_branch` |
| `Repo` | yes | The repo's project path on its forge: `owner/name` on GitHub, `group/project` on GitLab, subgroups included. **This is what makes multi-repo work**: each row targets exactly one repo |
| `Scope` | yes | One line. The detail lives in Phase Details below the table |
| `Phase` | yes | Phase id, referenced by `Depends`. `3a`/`3b` for splits. `M1`, `M2` for milestone rows |
| `Status` | yes | The cursor. See below |
| `Link` | no | `-`, `owner/repo#42` on GitHub, or `group/project!42` on GitLab. A cache only, and always re-derivable from the forge |
| `Depends` | no | Comma-separated phase ids. Blank means "the previous row" |

```markdown
| PR | Branch              | Repo              | Scope                    | Phase | Status  | Link | Depends |
|----|---------------------|-------------------|--------------------------|-------|---------|------|---------|
| 1  | claude/foundation   | acme/acme-web     | Project config, base deps| 0     | Merged  | #12  |         |
| 2  | claude/auth-api     | acme/acme-web     | Session endpoints        | 1     | Merged  | #14  |         |
| 3  | claude/auth-ios     | acme/acme-ios     | Sign-in screen           | 2     | In Review | #17 | 1       |
| 4  | claude/auth-android | acme/acme-android | Sign-in screen           | 3     | In Review | #9  | 1       |
| 5  | claude/cutover      | acme/acme-web     | Retire legacy login      | 4     | Pending |  -   | 2,3     |
```

Phases 2 and 3 both depend only on phase 1, so they run **concurrently** in different repos. Phase 4 waits for both.

### Milestone rows

A milestone row ships a repo's `target_branch` to its release branch, `release_branch` or else the default branch, at a point the plan names, rather than only at the end. It is the row to use when phases land on a feature branch and a later phase needs some of that work released first.

```markdown
| PR | Branch            | Repo          | Scope                              | Phase | Status  | Link | Depends |
|----|-------------------|---------------|------------------------------------|-------|---------|------|---------|
| 1  | claude/schema     | acme/acme-web | Calendar tables                    | 0     | Merged  | #31  |         |
| 2  | claude/sync       | acme/acme-web | Two-way sync                       | 1     | Merged  | #33  | 0       |
| 3  | feature/calendar  | acme/acme-web | Ship schema and sync to `main`     | M1    | Pending | -    | 0, 1    |
| 4  | claude/sharing    | acme/acme-web | Shared calendars                   | 2     | Pending | -    | M1      |
```

**It is told apart by two things together, with no new column:** its `Phase` id is `M` followed by a number, and its `Branch` is the repo's `target_branch`. No phase row can have that branch, since phase branches carry `branch_prefix`. A row with one sign and not the other is an error, and the driver stops on it rather than guess which was meant.

- Its PR goes from that branch to the repo's release branch, titled `Milestone M1: <scope>`.
- Its `Depends` lists the phases it ships.
- A later phase that needs the work released depends on the milestone row, as phase 2 does above. That dependency is the wait: nothing has to be paused by hand.
- Milestone rows are appended or inserted like any row and never renumbered.

**The driver opens a milestone PR and never merges it**, with YOLO on or off. A person merges it, every time. The driver then brings the branch back in line with the release branch and starts what the milestone unblocks.

A plan with milestone rows keeps the plan file on the default branch, or on another branch no milestone ships, such as one of its own where the default branch is protected, never on a branch a milestone ships: that branch is deleted on merge and re-created, and the plan would go with it.

**The integration PR is the implicit final milestone.** A plan with no milestone rows ends as it always has: under YOLO, where `target_branch` is not the release branch, the driver opens one PR from it to the release branch and never merges it. A plan that has milestone rows ships through them instead, and no implicit PR is opened.

### Status vocabulary

| Status | Meaning | Written by |
|---|---|---|
| `Pending` | Not started | plan author |
| `In Progress` | Claimed; work underway; no PR yet | driver, **before** creating the branch |
| `In Review` | PR open, subscribed, gates being evaluated | driver, immediately after opening the PR |
| `Merged` | Merged (terminal success) | driver, after the merge is confirmed |
| `Blocked` | Needs a human; reason recorded in Phase Details | driver or user |
| `Skipped` | Dropped (terminal) | user |

A milestone row uses the same words. `In Progress` is claimed and preparing, with no PR yet. `In Review` is the milestone PR open, worked by the driver and waiting on a person to merge it. `Merged` is a person merged it. `Blocked` and `Skipped` mean what they mean for a phase.

Legal transitions:

```
Pending ──▶ In Progress ──▶ In Review ──▶ Merged
   ▲             │              │
   └─────────────┴──────────────┘        (abandon)
   
any non-terminal ──▶ Blocked ──▶ (back to its prior status, or Pending)
any non-terminal ──▶ Skipped
```

`Done` is accepted as a synonym for `Merged` when reading, for compatibility with plans written for [cpm](https://github.com/sixoverground/claude-project-manager).

### Transition ordering

The order matters. It's what makes each crash window recoverable:

1. `Pending → In Progress` is committed **before** the branch is created. This is the claim.
2. Branch, implement, verify, push, open the PR.
3. `In Progress → In Review` (plus `Link`) is committed **immediately** after the PR exists, before subscribing, before any long wait.
4. `In Review → Merged` is committed **after** the merge is confirmed.

Each status commit goes to the home repo's plan branch with the blob `sha` read at the start of the transition. A stale sha fails the write, which is a free compare-and-swap against a second driver. The loser of that race re-reads and re-runs the Driver-ID decision before retrying, since re-applying its own claim over the winner's would leave two drivers each believing they hold the plan.

Read that sha at the start of every transition rather than caching it. When the plan branch is also a `target_branch`, merging a phase PR moves the branch the plan sits on, so a sha from before the merge is stale by construction.

Commit messages end with `[skip ci]`:

```
chore(plan): acme phase 3 -> In Review [skip ci]
```

Three extra commits land on the plan branch per phase. Without `[skip ci]` they burn CI minutes or, worse, trigger deploys. Adding `paths-ignore: ['docs/plans/**']` to push-triggered workflows is belt and braces.

A plan branch that isn't the default branch often sidesteps this entirely, since push-triggered workflows are commonly pinned to the default branch. Check rather than assume. A deploy pipeline that runs on every branch will still fire.

---

## 3. Driver State

```markdown
## Driver State

- Driver: running          <!-- running | paused | idle -->
- YOLO: on                 <!-- on = driver merges; off = you merge -->
- Driver-ID: d7f3a91c
- Driver-Host: craigs-mbp.local 48542 Tue Nov 17 23:15:56 2026 UTC
- Active:
  - Phase 2 — acme/acme-ios#17 — In Review (gate: awaiting reviewer)
  - Phase 3 — acme/acme-android#9 — In Review (gate: CI pending)
- UAT-pending: 0,1
- Review-baselines: 2:6
- Arbitrations: 2:3
- Heartbeat: 2026-07-26T14:03:00Z
- Note: -
```

| Field | Meaning |
|---|---|
| `Driver` | `running` normally; `paused` finishes the current step and starts nothing new; `idle` when the plan is complete |
| `YOLO` | `on`: the driver merges once gates pass. `off`: you merge, and the driver does everything else. Toggled at runtime |
| `Driver-ID` | Random token identifying the driver instance holding the plan. See below |
| `Driver-Host` | `<host> <pid> <start time> UTC` of the Claude Code process holding the plan, written with the claim. The start time is in UTC, so sessions with different time zones agree on it. `-` when unknown, and what a plan without the field reads as. Lets a later session on the same machine see that the holder has died |
| `Active` | One entry per in-flight phase. A list, so several repos can be in flight at once |
| `UAT-pending` | Phase ids whose UAT checklist hasn't reached a human yet. See [When UAT reaches a human](#when-uat-reaches-a-human) |
| `Review-baselines` | `<phase id>:<count>` pairs, written when a user clears a review-round stop with `continue`. The driver subtracts a phase's baseline from its derived reviewed-head count. Per phase, because concurrent phases can each be stopped. A milestone row's id works the same way, as in `M1:3` |
| `Arbitrations` | `<phase id>:<count>` pairs, a milestone row's id included, written when the driver hands a review loop to the arbiter at `stuck.max_review_rounds`, or sooner when a repo's own stop rule fires, with the reviewed-head count at that moment. An entry above the phase's baseline means this budget has had its arbitration. Written before the arbiter starts, so a session that dies mid-arbitration doesn't start a second one |
| `Heartbeat` | UTC timestamp, rewritten on every turn that touches the plan |
| `Note` | Free text for the current situation; the place a `Blocked` reason goes |

### Driver-ID and the concurrency rule

Two drivers acting on one plan would race. But a *single* long-lived session that wakes from a webhook shortly after writing its own heartbeat must not lock itself out. So identity, not just recency:

| Condition | Action |
|---|---|
| `Driver-ID` matches the one I hold | It's me: proceed regardless of heartbeat age |
| Different ID, `Driver-Host` on this host names a process that is gone | The holder died: take over |
| Different ID, heartbeat < 90 min | Another driver may be live: report and stop, naming `take over` |
| Different ID, heartbeat stale | Take over: mint a new ID, continue |
| No ID | Unclaimed: claim it |

A fresh session holds no ID, so it always takes one of the last four branches. A resuming session holds its own, so it never blocks itself. A person can always release a dead driver's claim by saying `take over`.

---

## Carried findings

Optional, and written only by the driver. It goes after Driver State, and it exists so that a finding the driver was right not to act on doesn't have to be either implemented or forgotten.

```markdown
## Carried findings

- [ ] Retry/backoff is duplicated in three clients, should be one helper. Raised on acme/acme-web#42 (review thread), out of scope for phase 3, which only touched the billing client
- [x] Drop the unused `legacy_sync` flag. Raised on acme/acme-web#44, folded into phase 7
```

One line per finding: **what**, **where it was raised**, and **why it wasn't done there**. A checked box means a phase now covers it, with that phase named.

The rules that keep it useful:

- **The driver appends; it never writes phases.** Recording a finding is execution. Turning one into a phase is planning, with scope, acceptance criteria, UAT and dependencies to write, and it belongs to `phase-planner` and the person whose plan it is. A driver that adds phases is re-planning a project mid-flight on a reviewer's suggestion.
- **Nothing schedules off this list.** It is not status, no gate reads it, and an open entry never blocks a phase. Its only readers are people and the planner.
- **It is not a bug tracker.** A defect that stands on its own, unrelated to what the plan is delivering, belongs in an issue. This is for work that makes sense *for this plan* but not *for the phase it was raised on*.
- **It gets read out.** The driver names any open entries when the plan finishes, in the same breath as outstanding UAT, so a plan cannot quietly complete with a list nobody looked at.

---

## Phase Details

Below the table, one section per phase:

```markdown
### Phase 2 — Sign-in screen (acme/acme-ios)

**Scope.** Add the sign-in screen and wire it to `POST /sessions`.

**Depends on.** Phase 1 (the endpoint must exist).

**Acceptance criteria.**
- [ ] Valid credentials navigate to the home screen
- [ ] Invalid credentials show an inline error
- [ ] Token persisted to the keychain

**UAT.**
- [ ] Sign in with a real account on a physical device; land on Home
- [ ] Enter a wrong password; error appears inline, field keeps focus
- [ ] Force-quit and reopen; still signed in
- [ ] Airplane mode; a network error appears rather than a hang

**Risks.** Keychain access on first launch needs an entitlement.
```

Acceptance criteria become the PR body checklist, so write them as things that can be checked.

### Milestone sections

A milestone row gets a section of its own shape. It has no acceptance criteria, because the driver writes no code for it beyond the repo's `milestone.prepare`:

```markdown
### Milestone M1 — Schema and sync (acme/acme-web)

**Ships.** Phases 0 and 1: the calendar tables and two-way sync.

**Review scope.** A finding on this PR is in scope when it falls within the scope of phases 0 and 1, taken together, or within what `milestone.prepare` produced. The driver answers it by its usual rules and commits fixes to `feature/calendar`. Anything beyond those goes to Carried findings.

**Needed by.** Phase 2, which builds sharing on the released sync.

**UAT.**
- [ ] Connect a real Google calendar, create an event on each side, and see both appear on the other within a minute

**Risks.** The migration runs on `main` for the first time here.
```

**Ships** also defines what is in scope when the milestone PR is reviewed, together with the preparation the driver did for it: a wrong version or changelog line is the driver's to fix, not to carry. **UAT** is for the end-to-end flows that only exist once the shipped phases are together; the phases' own UAT reaches the PR through `UAT-pending`, below.

### Acceptance criteria vs UAT

They are different audiences and must not be merged.

| | Acceptance criteria | UAT |
|---|---|---|
| Who performs it | The driver, before opening the PR | A human, by hand |
| What it proves | The code does what the phase specified | The product actually works |
| Typical item | "Endpoint returns 401 on a bad token" | "Sign in on a real device and land on Home" |
| Verified by | Tests, build, CI | Someone using the thing |

Write UAT as steps someone can follow without reading the diff: what to open, what to do, what they should see. "Test the login flow" is not a UAT step. Cover the happy path, the obvious failure, and anything adjacent that this phase could plausibly have broken.

### When UAT reaches a human

Which PR carries the checklist depends on YOLO, because YOLO determines whether anyone is stopping to look:

| YOLO | Where the checklist goes |
|---|---|
| **off** | Every PR carries its own phase's UAT. You're merging each one, so you get the checklist at the moment you decide |
| **on** | Phases merge unattended, so UAT is deferred to **one comprehensive test script** covering every phase: one runnable list rather than per-phase sections, plus the end-to-end flows that only make sense once everything has landed. It lands on the **integration PR**: `target_branch` → release branch, opened when the plan completes, or on the **final phase's PR** where phases already target the release branch and no integration PR exists |

**`UAT-pending` in Driver State tracks what hasn't been surfaced yet.** When a phase merges under YOLO on, its id is appended. When a PR carries a UAT checklist, the ids it covered are removed. This is what makes toggling safe: turn YOLO off after three auto-merged phases and the next PR carries its own UAT *plus* the three that nobody has verified. Turn it back on and they accumulate again.

Without that list, a mid-plan toggle silently loses UAT for every phase that merged while YOLO was on. The failure would be invisible, because the plan would look complete.

**A milestone PR is where UAT reaches a human, in either mode.** It carries the assembled script for every id in `UAT-pending` that it ships, plus the milestone's own UAT, and those ids are cleared when it opens. With YOLO on, that makes each milestone a point where the backlog is handed over rather than only the end of the plan. The integration PR in the table above is the implicit final milestone, and the same rule is what puts the cumulative script on it.

**When no integration PR will exist by configuration**, because the repo sets `integration_pr: false`, the cumulative script has no change request to land on. Under YOLO the phases still omit their own UAT and add their ids to `UAT-pending`, and when the plan completes the script goes to the fallback below. That gives up the one place the script had leverage, and it is the plan author's trade to make.

**The final phase** is the last non-`Skipped` row in table order. Under YOLO it is merged by the driver within minutes of opening, which is why the cumulative checklist belongs on the integration PR wherever one exists: a checklist on a PR nobody had to read is a record, not a prompt.

If a plan finishes with `UAT-pending` non-empty and no integration PR carried the cumulative checklist, which happens when `integration_pr` is `false`, or when every repo targets its release branch and the final phase was skipped or merged before the checklist was assembled, the driver never drops it. Where the forge has issues, it posts the cumulative checklist as an issue titled `UAT: <project>` and clears `UAT-pending`. Where it has none, it posts the checklist as a comment on the last merged PR, leaves `UAT-pending` as it is, and says so in its completion summary.

Set `uat: false` in a repo's config for repos where manual testing is meaningless.

---

## Writing a good plan

The rules that make phases work, carried over from cpm where they're already proven:

- **One phase = one PR = one repo.** Never split a phase across repos; use two rows and a `Depends`.
- **Sequential within a repo, parallel across repos.** Only declared dependencies serialize anything.
- **Every phase leaves the project working.** A phase that requires the next one to compile isn't a phase.
- **Size each phase to one session.** Roughly two hours of work. If it's bigger, split it into `3a` and `3b`. This is the single most common planning mistake, and it produces PRs nobody wants to review.
- **Phase 0 is foundation.** Dependencies, config, base architecture.
- **The last phase is cleanup.** Remove the legacy path, drop unused deps, final polish.

## Recovery

What a driver does when the plan and GitHub disagree, which is the situation after any crash:

| Plan says | GitHub says | What happened | Action |
|---|---|---|---|
| `Pending`, stale heartbeat | no branch, no PR | Never started | Start it |
| `Pending` | open PR on the branch | Died before recording the PR | Adopt the PR, write `In Review` |
| `In Progress`, foreign ID, heartbeat < 90 min | - | Another driver is live | Refuse, report |
| `In Progress`, this session's own ID | no branch | The local clone has the branch, with commits: worked offline, not yet pushed | Carry on through the reconnect sequence. Never reset |
| `In Progress`, taken over on this host | no branch | The local clone has the branch, with commits: the previous session's unpushed work | As a branch with no PR: inspect, finish, reset or ask |
| `In Progress`, stale | no branch | Claimed, died before any work, and no local branch holds commits | Reset to `Pending`, restart |
| `In Progress`, stale | branch, no PR | Died mid-implementation | Inspect the diff against the scope; finish and open the PR, or reset. A branch only in the local clone is renamed `<branch>-orphaned` on reset, never deleted |
| `In Progress` | open PR | Died before recording the PR | Write `In Review`, adopt |
| `In Review`, this session or a same-host successor | PR open | The local branch is ahead of the PR's head: fixes made while the forge was unreachable | Re-read the PR, re-derive the review count and apply the budget table, then push once. A merged, closed or moved PR never gets the commits unexamined |
| `In Review` | PR open | Normal | Re-subscribe, re-evaluate gates |
| `In Review` | PR merged | Died between merging and recording it | Write `Merged`, advance |
| `In Review` | PR closed unmerged | Someone killed it | Ask; default `Blocked` |
| all rows terminal | - | Complete | With no milestone rows and YOLO on, open the integration PR if `target_branch` is not the release branch and `integration_pr` is not `false`. Then set `Driver: idle` and report |

Applied **per row**, not once per plan. With several repos in flight, each recovers independently. The first matching row wins. Two rows also read the driver's local clone, which the forge cannot see; what the clone holds is in their *What happened*.

Every milestone in a repo shares one head and base, so a milestone row is matched to its PR by its `Link` where it has one, and otherwise by head equal to the row's branch, base equal to the repo's release branch, **and a title starting `Milestone <id>:`** with the row's id. Recovery also looks at `Merged` milestone rows until they are **settled**: the branch re-synced, and `milestone.after_merge` recorded as done by a marker comment on the PR.

| Plan says | GitHub says | What happened | Action |
|---|---|---|---|
| `Pending`, dependencies `Merged` or `Skipped` | no PR with this row's identity | Ready to ship | Start it |
| `Pending` or `In Progress`, dependencies `Merged` or `Skipped` | an open PR with this row's identity | Died after opening the PR, before recording it | Adopt it: write `In Review` and the `Link`. Do not prepare again if the preparation's commits are on the branch. Never adopt for a row with a dependency that is neither `Merged` nor `Skipped` |
| `In Progress`, stale | no PR, preparation partly on the branch | Died mid-preparation | Finish the preparation from where the branch stands, then open the PR |
| `In Review` | PR open | Normal | Work it. Never merge |
| `In Review` | PR merged | A person merged it | Write `Merged`, re-sync the branch, run `milestone.after_merge`, start what it unblocks |
| `In Review` | PR closed unmerged | Someone killed it | Ask; default `Blocked` |
| `Merged`, not settled | branch gone or lacking the milestone's merge commit, rows still target it | Died before re-syncing | Re-sync before starting anything in that repo |
| `Merged`, not settled | branch re-synced, no `after_merge` marker while the key is set | Died before finishing `after_merge` | Run it, post the marker, then start what it unblocks |

# Plan file format

A plan is one markdown file, committed to a GitHub repo, that describes a piece of work split into phases — and doubles as the durable state of the driver executing it.

It lives at `docs/plans/<project>.md` in the project's **home repo**.

Three parts:

1. **Front matter** — immutable configuration.
2. **PR Sequence Table** — one row per phase, with a `Status` column that is the execution cursor.
3. **Driver State** — mutable runtime state: liveness, and the toggles you flip from your phone.

No value ever appears in two of those places. Config is config, per-phase status is the table, runtime state is Driver State.

---

## Why the plan file holds the state

A Claude Code cloud session is ephemeral. Its container is reclaimed after inactivity, its context compacts as it grows, and it can die at any point — mid-implementation, between opening a PR and recording it, between merging and advancing.

So the plan file is not documentation that happens to track progress. **It is the only durable state.** A fresh session must be able to reconstruct everything from the plan file plus what GitHub reports, with no memory of what came before. Every design rule below follows from that.

Two invariants make it work:

- **Status is written to the home repo's plan branch, never inside a phase PR.** A status written inside a PR is invisible until that PR merges, so a fresh session would see `Pending` for a phase that already has an open PR — and start it again.
- **Phase PRs never modify the plan file.** One writer means a squash merge can never conflict with its own bookkeeping, no matter how far the plan branch has moved.

The **plan branch** is `plan_branch`, defaulting to the home repo's default branch. What the first invariant actually requires is a branch that no phase PR modifies and that is readable without merging one — the default branch is the usual answer, not the only one. Feature-branch work, where every phase targets `feature/x` and nothing reaches `main` until the feature is whole, puts the plan on `feature/x` and satisfies it just as well.

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
    stuck: { max_cycles: 5 }

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
| `Branch` | yes | The phase branch, prefixed with `branch_prefix` |
| `Repo` | yes | `owner/name`. **This is what makes multi-repo work** — each row targets exactly one repo |
| `Scope` | yes | One line. The detail lives in Phase Details below the table |
| `Phase` | yes | Phase id, referenced by `Depends`. `3a`/`3b` for splits |
| `Status` | yes | The cursor. See below |
| `Link` | no | `-` or `owner/repo#42`. A cache only — always re-derivable from GitHub |
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

### Status vocabulary

| Status | Meaning | Written by |
|---|---|---|
| `Pending` | Not started | plan author |
| `In Progress` | Claimed; work underway; no PR yet | driver, **before** creating the branch |
| `In Review` | PR open, subscribed, gates being evaluated | driver, immediately after opening the PR |
| `Merged` | Merged (terminal success) | driver, after the merge is confirmed |
| `Blocked` | Needs a human; reason recorded in Phase Details | driver or user |
| `Skipped` | Dropped (terminal) | user |

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

The order matters — it's what makes each crash window recoverable:

1. `Pending → In Progress` is committed **before** the branch is created. This is the claim.
2. Branch, implement, verify, push, open the PR.
3. `In Progress → In Review` (plus `Link`) is committed **immediately** after the PR exists — before subscribing, before any long wait.
4. `In Review → Merged` is committed **after** the merge is confirmed.

Each status commit goes to the home repo's plan branch with the blob `sha` read at the start of the transition. A stale sha fails the write, which is a free compare-and-swap against a second driver.

Read that sha at the start of every transition rather than caching it. When the plan branch is also a `target_branch`, merging a phase PR moves the branch the plan sits on, so a sha from before the merge is stale by construction.

Commit messages end with `[skip ci]`:

```
chore(plan): acme phase 3 -> In Review [skip ci]
```

Three extra commits land on the plan branch per phase. Without `[skip ci]` they burn CI minutes or, worse, trigger deploys. Adding `paths-ignore: ['docs/plans/**']` to push-triggered workflows is belt and braces.

A plan branch that isn't the default branch often sidesteps this entirely, since push-triggered workflows are commonly pinned to the default branch. Check rather than assume — a deploy pipeline that runs on every branch will still fire.

---

## 3. Driver State

```markdown
## Driver State

- Driver: running          <!-- running | paused | idle -->
- YOLO: on                 <!-- on = driver merges; off = you merge -->
- Driver-ID: d7f3a91c
- Active:
  - Phase 2 — acme/acme-ios#17 — In Review (gate: awaiting reviewer)
  - Phase 3 — acme/acme-android#9 — In Review (gate: CI pending)
- UAT-pending: 0,1
- Heartbeat: 2026-07-26T14:03:00Z
- Note: -
```

| Field | Meaning |
|---|---|
| `Driver` | `running` normally; `paused` finishes the current step and starts nothing new; `idle` when the plan is complete |
| `YOLO` | `on` — the driver merges once gates pass. `off` — you merge; the driver does everything else. Toggled at runtime |
| `Driver-ID` | Random token identifying the driver instance holding the plan. See below |
| `Active` | One entry per in-flight phase. A list, so several repos can be in flight at once |
| `UAT-pending` | Phase ids whose UAT checklist hasn't reached a human yet. See [When UAT reaches a human](#when-uat-reaches-a-human) |
| `Heartbeat` | UTC timestamp, rewritten on every turn that touches the plan |
| `Note` | Free text for the current situation; the place a `Blocked` reason goes |

### Driver-ID and the concurrency rule

Two drivers acting on one plan would race. But a *single* long-lived session that wakes from a webhook shortly after writing its own heartbeat must not lock itself out. So identity, not just recency:

| Condition | Action |
|---|---|
| `Driver-ID` matches the one I hold | It's me — proceed regardless of heartbeat age |
| Different ID, heartbeat < 90 min | Another driver is live — report and stop |
| Different ID, heartbeat stale | Take over: mint a new ID, continue |
| No ID | Unclaimed — claim it |

A fresh session holds no ID, so it always takes the third or fourth branch. A resuming session holds its own, so it never blocks itself.

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
| **on** | Phases merge unattended, so UAT is deferred: the **final PR** carries a cumulative checklist covering every phase, grouped by phase, plus end-to-end flows that only make sense once everything has landed |

**`UAT-pending` in Driver State tracks what hasn't been surfaced yet.** When a phase merges under YOLO on, its id is appended. When a PR carries a UAT checklist, the ids it covered are removed. This is what makes toggling safe: turn YOLO off after three auto-merged phases and the next PR carries its own UAT *plus* the three that nobody has verified. Turn it back on and they accumulate again.

Without that list, a mid-plan toggle silently loses UAT for every phase that merged while YOLO was on — the failure would be invisible, because the plan would look complete.

**The final phase** is the last non-`Skipped` row in table order. If a plan somehow finishes with `UAT-pending` non-empty — the final phase was skipped, or its PR merged before the checklist was assembled — post the cumulative checklist as a GitHub issue titled `UAT: <project>` rather than dropping it.

Set `uat: false` in a repo's config for repos where manual testing is meaningless.

---

## Writing a good plan

The rules that make phases work, carried over from cpm where they're already proven:

- **One phase = one PR = one repo.** Never split a phase across repos; use two rows and a `Depends`.
- **Sequential within a repo, parallel across repos.** Only declared dependencies serialize anything.
- **Every phase leaves the project working.** A phase that requires the next one to compile isn't a phase.
- **Size each phase to one session.** Roughly two hours of work. If it's bigger, split it into `3a` and `3b` — this is the single most common planning mistake, and it produces PRs nobody wants to review.
- **Phase 0 is foundation** — dependencies, config, base architecture.
- **The last phase is cleanup** — remove the legacy path, drop unused deps, final polish.

## Recovery

What a driver does when the plan and GitHub disagree — the situation after any crash:

| Plan says | GitHub says | What happened | Action |
|---|---|---|---|
| `Pending`, stale heartbeat | no branch, no PR | Never started | Start it |
| `Pending` | open PR on the branch | Died before recording the PR | Adopt the PR, write `In Review` |
| `In Progress`, foreign ID, heartbeat < 90 min | — | Another driver is live | Refuse, report |
| `In Progress`, stale | no branch | Claimed, died before any work | Reset to `Pending`, restart |
| `In Progress`, stale | branch, no PR | Died mid-implementation | Inspect the diff against the scope; finish and open the PR, or reset |
| `In Progress` | open PR | Died before recording the PR | Write `In Review`, adopt |
| `In Review` | PR open | Normal | Re-subscribe, re-evaluate gates |
| `In Review` | PR merged | Died between merging and recording it | Write `Merged`, advance |
| `In Review` | PR closed unmerged | Someone killed it | Ask; default `Blocked` |
| all rows terminal | — | Complete | Set `Driver: idle`, report |

Applied **per row**, not once per plan — with several repos in flight, each recovers independently.

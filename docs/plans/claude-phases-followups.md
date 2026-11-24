---
phases:
  project: claude-phases-followups
  home_repo: sixoverground/claude-phases
  # plan_branch is left at its default, the home repo's default branch (main).
  # A plan with milestone rows may not live on a branch a milestone ships, and
  # M1 ships feature/followups, which is deleted when it merges.

  defaults:
    branch_prefix: claude/
    merge: { method: squash }
    ci:
      required: []                 # every reported check counts; nothing is named, see Conventions
      allow_none: false
      dispatch: push               # release.yml declares workflow_dispatch and dispatching it releases
      logs: actions
    review:
      required:
        - logins: ["chatgpt-codex-connector"]
          rereview: optional       # smart detect: reviews and a thumbs up on #55 and #58,
                                   # and on the phase PRs of claude-phases-offline, which
                                   # were PRs into a non-default base
          rereview_grace: 15m
      changes_requested_blocks: true
      threads_must_resolve: true
    stuck:
      max_cycles: 5
      max_review_rounds: 3
      arbiter: { model: fable, extra_rounds: 3 }

  repos:
    # Markdown skills plus shell scripts. Phases land on the feature branch and
    # reach main at the one milestone. Checks seen on PRs: "Build skill zips"
    # on every PR; "Version bumped" runs only on PRs into main and is skipped
    # on PRs into a feature branch, so it is deliberately NOT in ci.required;
    # "Tag and release" is skipped until a merge to main.
    sixoverground/claude-phases:
      target_branch: feature/followups
      verify: auto                 # the scripts in scripts/ are the local build; see Conventions
      milestone:
        prepare: >
          On the feature branch: raise `version` in .claude-plugin/plugin.json to
          0.16.1, or by a patch step above what main has if main has moved past
          0.16.0; update the sentence "This copy is claude-phases <version>." that
          ends both skill descriptions; add one "## [<version>]" section at the top
          of CHANGELOG.md, in the file's voice, assembled from the changelog
          sentences in the PR bodies of the phases this milestone ships. Then run
          scripts/check-version-bump.sh origin/main, scripts/check-skill-versions.sh
          and scripts/release.sh --dry-run, and do not open the milestone PR until
          all three pass.
        after_merge: >
          First confirm the release. Read `version` from .claude-plugin/plugin.json
          on main and run `gh release view v<version>`. If the release is missing,
          the merge-triggered Release run was skipped or failed, so run
          `gh workflow run release.yml --ref main`, wait for that run to finish,
          confirm the release and both skill zips are there, and say in the
          milestone-merged message that the release had to be dispatched and why.
          This is the one case in which a workflow is dispatched in this repo. If
          `gh` cannot do this here, say that the release is missing and give the
          command. Then run `claude plugin marketplace update sixoverground` and
          `claude plugin update claude-phases@sixoverground` on the machine this
          session runs on, and say in the milestone-merged message which version
          is installed and that a running session must be restarted to load it.
          If the commands are unavailable here, as in a cloud session, say that
          they still have to be run on the Mac.

  max_concurrent: null
---

# claude-phases-followups

Settle the two questions `claude-phases-offline` left open, now that the owner has answered them. A person can say `arbitrate` to get a fresh arbitration, defined entirely by rules the driver already has. And the local review pass runs before a milestone PR's fix pushes, reviewing only the fix. Three rows in `sixoverground/claude-phases`: two phases on `feature/followups`, and one milestone that ships them to `main` as 0.16.1.

## For the driver

This plan is executed by the `phase-driver` skill, and nothing in this file stands in for it. If you are acting on this plan and that skill is not in your context, because the session was compacted or was woken by a check-in or a webhook, invoke `phase-driver` before you do anything else, then reconcile. The rule a session without it most often drops: **a merge always advances the plan.** After any phase PR merges, start whatever it unblocks in the same turn unless `Driver: paused`, and when the last row merges, finish the plan by the skill's finishing steps rather than going idle.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1 | claude/arbitrate-word | sixoverground/claude-phases | `arbitrate`: a person asks for a fresh arbitration, at a review-round stop or early in the current budget, defined by the existing baseline and `Arbitrations` rules | 0 | Merged | #67 |  |
| 2 | claude/local-pass-milestone | sixoverground/claude-phases | The local review pass runs before a milestone PR's fix pushes, with `{base}` at the PR's head before the fix; the preparation's commits get none | 1 | In Progress | - | 0 |
| 3  | feature/followups | sixoverground/claude-phases | Milestone: ship `arbitrate` and the local pass on milestone fix pushes to `main` as 0.16.1 | M1 | Pending | - | 0, 1 |

Row `M1` is a milestone row: its branch is the repo's `target_branch`, its PR goes to `main`, and its `Depends` lists what it ships. The driver opens it and never merges it.

## How this plan is driven

### Why one milestone

Neither phase needs the other released before it can start: both are prose the installed 0.16.0 driver can write. The milestone exists by the owner's decision, so the two changes reach `main` as one patch release that a person reads and merges. It is the last row, and with a milestone row in the plan no implicit integration PR is opened.

**The plan is driven by the installed 0.16.0 throughout.** Saying `arbitrate` to the driver of this plan does nothing new until `M1` is merged and the plugin is updated, and `M1`'s own fix pushes get no local pass.

### YOLO

**YOLO starts on, by the owner's choice.** Phases merge unattended once their gates pass. Their UAT accumulates in `UAT-pending` and reaches a person on the milestone PR, which YOLO never merges.

**Trying a phase's skills before they are released.** UAT steps that say "this branch's skills" mean: `claude plugin disable claude-phases@sixoverground`, then `claude --plugin-dir <a clone checked out at feature/followups>`, and re-enable the installed plugin afterwards.

### Prerequisites only a person can do

| Before | Do this |
|---|---|
| Starting the driver | Create `feature/followups` from `main` in `sixoverground/claude-phases`: `git fetch origin && git push origin origin/main:refs/heads/feature/followups`. It did not exist when this plan was written, and a `target_branch` that does not exist is a gate that waits forever |
| Starting the driver | Commit this file to `main` at `docs/plans/claude-phases-followups.md`, directly, with a message ending `[skip ci]` |
| Phase 1's UAT | A Mac with `codex-mr-review` on the `PATH` and `codex login` current |
| `M1` | Read the PR the driver opened and merge it |

### Conventions for every phase

These hold for each phase and are part of its acceptance criteria.

- **No phase changes the version.** `version` in `.claude-plugin/plugin.json`, the sentence `This copy is claude-phases <version>.` that ends both skill descriptions, and `CHANGELOG.md` are changed by the milestone's preparation only.
- Every phase's PR body carries two or three sentences written for the changelog, in the file's voice. `milestone.prepare` assembles the `[0.16.1]` entry from them.
- `scripts/check-skills.sh` passes: no link climbs out of a skill directory, and neither skill reads the other's files.
- `scripts/check-skill-versions.sh` still passes.
- `claude plugin validate . --strict` passes where the CLI is available. Say in the PR body if it was not run.
- House style: plain sentences, and no em-dashes anywhere, in prose or in headings this plan adds.
- The PR body says what was actually run, in CONTRIBUTING's words: a real run, or "reviewed by reading" when that is the truth.
- The plan format's own names do not change. **No phase adds a Driver State field, a status, or a front-matter key.** Both decisions are built from what exists.
- A rule stated in the driver and restated for the planner is changed in both in the same phase.
- **No phase edits `docs/plans/claude-phases-offline.md`.** Its Open questions section is the record of a finished plan. The answers live in the skills and in this plan's Decisions.

`ci.dispatch` is `push` and not `auto` because `release.yml` declares `workflow_dispatch`, and dispatching it runs the release job. Never dispatch a workflow here, with the one exception written into `milestone.after_merge`.

## Decisions and rationale

Settled with the owner on 2026-11-24. Each phase implements these; neither reopens them.

### `arbitrate`: a person asks for a fresh arbitration

A new word in the driver's vocabulary, with no new state and no new exception. It applies only where `stuck.arbiter` is configured and `review.required` is not empty. What it means depends on where the row is:

**At a review-round stop** (the row is `Blocked` by **Stop for a person**, after the arbiter's extra rounds): it is `continue` plus an arbitration at once. The driver starts a new budget and arbitrates in it immediately, and `extra_rounds` counts from that arbitration.

**The baseline is written one below the current count, and this is the point of the design.** An arbitration is in a budget only when its `Arbitrations` count is above that phase's baseline. A plain `continue` writes the baseline at the current count *C*. An arbitration then recorded at *C* would sit at the baseline, not above it, so it would be outside the new budget and the next wake would arbitrate again. So for `arbitrate` at a stop the driver writes `Review-baselines` as `<id>:<C - 1>` and `Arbitrations` as `<id>:<C>`. The effective count is then 1, the entry is above the baseline, and the budget table's last two rows take over: heads are answered under the verdict, and the next stop comes at *C* plus `extra_rounds`. This is the rule the skill already states for a repo's own stop rule, which counts only from an effective count of 1 for the same reason, applied by choosing the baseline and not by excepting anything.

The earlier arbitration's entry stays where it is. Its count is at most *C* minus `extra_rounds`, and `extra_rounds` is at least 1, so it is never above the new baseline and never mistaken for this budget's.

**All three changes go in one plan write**: the baseline, the `Arbitrations` entry, and the row back to `In Review`. One write is what golden rule 2 asks, and it leaves no window in which a session that dies has cleared the stop and not recorded the arbitration.

**Before the threshold, with no arbitration yet in this budget** (the row is `In Review`): it is an early arbitration in the current budget, recorded in `Arbitrations` as `<id>:<derived count>` exactly as the threshold one is, with nothing written to `Review-baselines`. It needs an effective count of at least 1, as a repo rule does. At an effective count of 0 no head has been reviewed in this budget, so there is nothing to arbitrate and an entry would sit at the baseline: the driver says so, writes nothing, and the word can be said again once a head has been reviewed.

**Everywhere else the driver writes nothing and says why:**

| Where | Answer |
|---|---|
| `In Review`, an arbitration already in this budget | The arbiter runs once per budget. Link the verdict, say at which count the stop comes, and that `arbitrate` at that stop starts a new budget with a fresh arbitration |
| `stuck.arbiter: null` | No arbiter is configured for this repo. At a stop, `continue` is the word |
| `review.required: []` | No head is ever counted, so an arbitration's stop could never be reached, as the skill already says of repo-rule stops there |
| `Blocked` for any other reason | `arbitrate` clears only a review-round stop |

**The arbitration itself is the existing one.** Same brief, same limits, same six steps, same verdict comment with `<!-- phase-driver:arbiter <id>:<count> -->` on its first line. The brief adds one fact: a person asked for this arbitration, and at a stop, that the previous budget ran out at this head. It adds no opinion. The verdict comment says the same in a line. A session that finds an `Arbitrations` entry in this budget with no verdict comment re-runs the arbiter as it does today, and can tell the request was a person's from a baseline exactly one below the entry.

**A milestone row works the same way**, with its own id, as in `M1:4` and `M1:5`.

### The local review pass on a milestone PR's fix pushes

**It runs, scoped to the fix.** Before a fix is pushed to a milestone PR, `review.local.command` runs once with `{base}` replaced by the milestone PR's head as the forge has it before the fix, and `{head}` by the commit about to be pushed. So the pass reviews the fix and nothing else. The phases the milestone ships were each reviewed on their own change requests, and a pass over the whole feature would spend a Codex run re-reading them and return findings that are out of the fix's scope.

**The preparation gets none.** The commits `milestone.prepare` produces, the version bump and the CHANGELOG section, and the push that opens the milestone PR have no local pass. A later fix to the preparation, made in answer to a check or a review, is a fix push like any other and gets one.

**Everything else about the pass is unchanged**: one pass per push, skipped and disclosed where the command cannot run, judged by **Answering a review** with the milestone's scope, against the verdict's bar where an arbitration is in the budget, never a review, and disclosed in one stamped comment after the push. On a phase branch `{base}` stays the fetched `origin/<target_branch>`.

## Phase Details

### Phase 0: `arbitrate` (sixoverground/claude-phases)

**Scope.** The word, and the few places that must know it. Everything is defined by **Decisions and rationale** above.

- **`skills/phase-driver/references/vocabulary.md`**: a row for `arbitrate`, "get a second opinion", directly after `continue`. It gives the two cases, the baseline at the current count minus one with the reason in a sentence, the one plan write, and the table of answers where it does not apply. The `continue` row gains a clause pointing at it, since its warning about a baseline written before the stop is the same concern.
- **`skills/phase-driver/SKILL.md`, minimally:**
  - **The budget**: one sentence after the table saying a person's `arbitrate` is the other way an arbitration enters a budget, and that it takes the same last two rows.
  - **Arbitrate**: step 1 names the person's case and its combined write; step 2's brief gains the fact that a person asked; step 5 says the verdict comment notes it. The sentence "nothing is written to `Review-baselines`" under **An arbitration is not a stop** is qualified for the stop case and no other.
  - **After the verdict**: "The arbiter runs once per budget" stays, with a clause that a person's `arbitrate` at the stop is how a new budget and its arbitration begin.
  - **Stop for a person**: after "The user resumes with `continue`", a sentence that `arbitrate` resumes too, where an arbiter is configured, and what differs. The stop report's own text does not change and still does not ask a question.
  - **Working a milestone PR**: nothing new beyond confirming that the sentence on `Review-baselines` and `Arbitrations` taking the milestone's id covers it.
- **`skills/phase-driver/references/recovery.md`**: where it says an offline phase in review holds at an arbitration or a stop, nothing changes, and the phase confirms that by reading it.
- **The planner's mirror**: `skills/phase-planner/references/format.md`, the `Review-baselines` and `Arbitrations` rows of the Driver State table, each gain a clause for a person's `arbitrate`; `references/configuration.md`, **The arbiter**, gains a short paragraph; `skills/phase-planner/SKILL.md`'s hand-off list of words a person can say gains it if that list names `continue`.
- **`docs/design.md`**, the arbiter section: a paragraph on why the word is `continue` plus an arbitration and why the baseline sits one below.

**Depends on.** Nothing.

**Acceptance criteria.**
- [ ] `vocabulary.md` defines `arbitrate` for both cases and for each case where it writes nothing, and states the baseline as the current count minus one with its reason
- [ ] A worked example appears once, in `vocabulary.md` or under **Arbitrate**: with defaults, arbitrated at 3, stopped at 6, `arbitrate` writes `Review-baselines` `<id>:5` and `Arbitrations` `<id>:6`, heads 7 and 8 are answered under the new verdict, and head 9 stops
- [ ] Checked by hand against the budget table as written: with those entries the effective count is 1, the arbitration is in this budget, and the row that applies is one of the last two. The PR body shows the working
- [ ] The text says the three changes are one plan write, and that the earlier `Arbitrations` entry is left in place
- [ ] The early case records `<id>:<derived count>` with no baseline write, and refuses at an effective count of 0
- [ ] The budget table's six rows are unchanged, no Driver State field is added, and the verdict marker's format is unchanged
- [ ] `format.md` and `configuration.md` agree with the driver on what writes each field
- [ ] The conventions above hold

**UAT.**
- [ ] With this branch's skills, take a scratch phase PR to its stop after the arbiter's extra rounds (lower `max_review_rounds` and `extra_rounds` to `1` to get there quickly). Say `arbitrate`. The driver should write one plan commit that sets the row to `In Review`, adds a baseline one below the current count and an `Arbitrations` entry at the current count, then run the arbiter and post a verdict that says a person asked for it
- [ ] Let the next review land. The driver should answer it under the new verdict and should not arbitrate again
- [ ] On a PR at its first reviewed head, below the threshold, say `arbitrate`. It should arbitrate now, record the entry at the current count, and write no baseline
- [ ] Say `arbitrate` again on that PR. It should decline, link the verdict, and say when the stop comes
- [ ] On a scratch plan with `stuck.arbiter: null`, say `arbitrate` at a stop. It should say no arbiter is configured and name `continue`
- [ ] Say `continue` at an ordinary stop. It should behave exactly as it did before this phase

**Risks.** The baseline is the one number that keeps a stop from being walked past, and this is the first rule that writes it anywhere but at the current count. One below is exact, and two below would hand the phase a free round. The review should check the arithmetic against the table and not against this plan's summary of it.

---

### Phase 1: The local review pass on milestone fix pushes (sixoverground/claude-phases)

**Scope.** Everything is defined by **Decisions and rationale** above.

- **`skills/phase-driver/SKILL.md`, The local review pass**:
  - The opening paragraph's `{base}` sentence gains the milestone case: the milestone PR's head as the forge reports it before the fix, read with `git ls-remote` as `references/recovery.md` requires for any decision about where a branch points.
  - **One pass per push** no longer says "of a phase branch" alone: every push of a phase branch, and every fix push to a milestone PR. It states that the preparation's commits and the push that opens a milestone PR get none.
- **`SKILL.md`, Working a milestone PR**: the **Where a fix goes** bullet gains a sentence linking the pass and its scoped `{base}`, and saying the disclosure is the one stamped comment after the push, as on a phase.
- **`SKILL.md`, Opening a milestone PR**: a clause that no local pass runs here, so nobody infers one from §3.
- **Scope of judgement.** A finding from the pass on a milestone fix is judged by the milestone's scope, the union of the shipped phases' scopes plus what `milestone.prepare` asked for, as **Working a milestone PR** already defines. The phase says so in a clause and restates nothing.
- **`skills/phase-planner/references/configuration.md`, `review.local`**: the table row's meaning and the prose below it say the same two things, where it runs and what `{base}` is in each case.
- **`docs/review-setup.md`, A local pass before each push**, and **`docs/running-locally.md`**: a sentence each for the milestone case, where they say when the pass runs.
- **`docs/design.md`**, where it explains that the local pass counts for nothing on the forge: two sentences on why a milestone's pass is scoped to the fix.
- `skills/phase-planner/references/plan-template.md`, `format.md`, both detection references and `profiles/review-codex-local.yml` are read, and changed only if they say "phase branch". The command line itself does not change.

**Depends on.** Phase 0, only because one repo has one open phase PR at a time.

**Acceptance criteria.**
- [ ] **The local review pass** states both cases of `{base}` and both places it runs, and names what gets no pass
- [ ] `grep -rn -i 'phase branch' skills docs` shows no sentence that limits the local pass to phase branches
- [ ] The text says the milestone's `{base}` is read from the forge before the fix is pushed, not from a remote-tracking ref
- [ ] Nothing about a phase branch's pass changed: same `{base}`, same cap, same disclosure
- [ ] The text still says the pass is never a review and that gate 6 waits for the real reviewer at the pushed head, on a milestone PR as on a phase
- [ ] `configuration.md`, `docs/review-setup.md` and the driver agree
- [ ] The conventions above hold

**UAT.**
- [ ] On the Mac, with this branch's skills and `review.local` set in a scratch plan with a milestone row, let the driver prepare and open the milestone PR. No local pass should run, and the PR body should not claim one
- [ ] Leave a review comment on the milestone PR that needs a small fix. Before pushing the fix, the driver should run the command once, and the comment it posts afterwards should name a base that is the PR's previous head, not the target of the PR
- [ ] Check the command's output or the disclosure: its findings should concern the fix only, with nothing about files the fix did not touch
- [ ] On an ordinary phase PR in the same plan, let a review round happen. The local pass before its fix push should still review the whole phase against the target branch

**Risks.** A fix that spans two commits before one push needs `{base}` at the forge's head, not at the previous local commit, or the first commit goes unreviewed. Reading the base from the forge is what covers it.

---

### Milestone M1: `arbitrate` and the local pass on milestone fixes, 0.16.1 (sixoverground/claude-phases)

**Ships.** Phases 0 and 1: the `arbitrate` word, and the local review pass before a milestone PR's fix pushes.

**Review scope.** A finding on this PR is in scope when it falls within the scope of phases 0 and 1, taken together, or within what `milestone.prepare` produced. The driver answers it by its usual rules and commits fixes to `feature/followups`. Anything beyond those goes to Carried findings.

**Needed by.** Nothing in the plan. It is the end and the last row, and it exists so the two changes reach `main` as one release that a person merges.

**UAT.** On the milestone PR before you merge it:
- [ ] Read the CHANGELOG section the preparation wrote. It should be headed `[0.16.1]`, define `arbitrate` in a few sentences including the baseline one below the count, and say where the local pass now runs and what it reviews there
- [ ] Read the whole diff as one change, the baseline arithmetic first

After merging:
- [ ] The release `v0.16.1` should appear with its notes and both skill zips, started by the merge
- [ ] The driver should record `M1`, leave the feature branch deleted since no row targets it any more, set `Driver: idle`, and name any outstanding UAT and carried findings
- [ ] Update the plugin, restart, and ask Claude which version of claude-phases it has. It should say 0.16.1
- [ ] On the released version, on a real plan, say `arbitrate` at the next review-round stop. It should clear the stop, arbitrate at once, and carry on under the verdict
- [ ] Drive one phase of an existing plan on the released version without saying `arbitrate` and without `review.local`. It should behave as 0.16.0 did

**Risks.** If `main` moved while the plan ran, the preparation's bump may collide; the driver redoes it on what `main` says. A patch number on a change in what a word does: the CHANGELOG's own preface says to read the entry, and the entry should make that easy.

## Driver State

- Driver: running
- YOLO: on
- Driver-ID: 58e3df70
- Driver-Host: Raphael.local 73385 Tue Nov 24 14:52:15 2026 UTC
- Active: 1, claude/local-pass-milestone
- UAT-pending: 0
- Review-baselines: -
- Arbitrations: -
- Heartbeat: 2026-11-24T17:51:36Z
- Note: -

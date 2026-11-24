---
phases:
  project: claude-phases-offline
  home_repo: sixoverground/claude-phases
  # plan_branch is left at its default, the home repo's default branch (main).
  # A plan with milestone rows may not live on a branch a milestone ships, and
  # M1 ships feature/offline, which is deleted when it merges.

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
          rereview: optional       # smart detect: reviews on #55 and #58, a thumbs up on both.
                                   # #55 was a PR into a non-default base, so it reviews those too
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
    # on PRs into a feature branch (seen skipped on #55), so it is deliberately
    # NOT in ci.required; "Tag and release" is skipped until a merge to main.
    sixoverground/claude-phases:
      target_branch: feature/offline
      verify: auto                 # the scripts in scripts/ are the local build; see Conventions
      milestone:
        prepare: >
          On the feature branch: raise `version` in .claude-plugin/plugin.json to
          0.16.0, or by a minor step above what main has if main has moved past
          0.15.x; update the sentence "This copy is claude-phases <version>." that
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

# claude-phases-offline

Make a forge outage cost a driver as little as it has to. Today an unreachable forge is a total wait. After this plan, an outage still blocks claims, every plan write and every push, but work under a claim that already landed carries on in the local clone and is pushed through a guarded reconnect sequence when the forge answers. The waiting gets quiet, an optional local review pass runs before each push, and two small faults found on the same real run are fixed. Eight rows in `sixoverground/claude-phases`: seven phases on `feature/offline`, and one milestone that ships them to `main` as 0.16.0.

## For the driver

This plan is executed by the `phase-driver` skill, and nothing in this file stands in for it. If you are acting on this plan and that skill is not in your context, because the session was compacted or was woken by a check-in or a webhook, invoke `phase-driver` before you do anything else, then reconcile. The rule a session without it most often drops: **a merge always advances the plan.** After any phase PR merges, start whatever it unblocks in the same turn unless `Driver: paused`, and when the last row merges, finish the plan by the skill's finishing steps rather than going idle.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1 | claude/arbiter-brief-body-files | sixoverground/claude-phases | Small fixes: the arbiter brief carries a fresh export of the plan from the plan branch; comment bodies are written to files, never heredocs | 0 | Merged | #59 |  |
| 2 | claude/quiet-outage | sixoverground/claude-phases | Both watcher templates: no check-in while the forge is down, a host-level reachability line with no open change request, an outage expiry re-arms silently | 1 | Merged | #60 | 0 |
| 3 | claude/offline-claimed-work | sixoverground/claude-phases | An outage blocks claims, plan writes and pushes, not work under a landed claim: rule 10, §3, the reconnect sequence, the `offline` key | 2 | Merged | #61 | 1 |
| 4 | claude/recover-local-branch | sixoverground/claude-phases | Recovery for a claimed row whose commits exist only in the local clone: new rows, the same-host successor, orphaned branches, the planner's copy of the table | 3 | Merged | #62 | 2 |
| 5 | claude/offline-in-review | sixoverground/claude-phases | Offline fixes on an `In Review` phase, with the review budget re-derived from the forge before anything is pushed | 4 | Merged | #63 | 3 |
| 6 | claude/local-review-pass | sixoverground/claude-phases | `review.local`: an optional, non-posting, single local review pass before every push; config, detection, profile, disclosure, the arbiter brief | 5 | Merged | #64 | 4 |
| 7 | claude/offline-cleanup | sixoverground/claude-phases | Cleanup: design notes, the local guide, README, hygiene, and a consistency pass over everything this plan restated in two places | 6 | Merged | #65 | 5 |
| 8 | feature/offline | sixoverground/claude-phases | Milestone: ship working through a forge outage, the quiet watcher, `review.local` and the two fixes to `main` as 0.16.0 | M1 | In Review | #66 | 0, 1, 2, 3, 4, 5, 6 |

Row `M1` is a milestone row: its branch is the repo's `target_branch`, its PR goes to `main`, and its `Depends` lists what it ships. The driver opens it and never merges it.

## How this plan is driven

### Why one milestone

Phases merge into `feature/offline` and nothing in this plan needs earlier work released before it can start: every phase is prose and shell that the installed 0.15.0 driver can write. The milestone exists by the owner's decision, so that the whole change reaches `main` as one release, read as one diff and merged by a person. It is the last row, and with a milestone row in the plan no implicit integration PR is opened.

**The plan is driven by the installed 0.15.0 throughout.** Nothing a phase writes changes how this plan is driven until `M1` is merged and the plugin is updated. So an outage during this plan is still a total wait, as 0.15.0 says.

### YOLO

**YOLO starts on, by the owner's choice.** Phases merge unattended once their gates pass. Their UAT accumulates in `UAT-pending` and reaches a person on the milestone PR, which YOLO never merges.

**Trying a phase's skills before they are released.** UAT steps that say "this branch's skills" mean: `claude plugin disable claude-phases@sixoverground`, then `claude --plugin-dir <a clone checked out at feature/offline>`, and re-enable the installed plugin afterwards.

### Prerequisites only a person can do

| Before | Do this |
|---|---|
| Starting the driver | Create `feature/offline` from `main` in `sixoverground/claude-phases`: `git fetch origin && git push origin origin/main:refs/heads/feature/offline`. It did not exist when this plan was written, and a `target_branch` that does not exist is a gate that waits forever |
| Starting the driver | Commit this file to `main` at `docs/plans/claude-phases-offline.md`, directly, with a message ending `[skip ci]` |
| Phase 5's UAT | A Mac with `codex-mr-review` on the `PATH` and `codex login` current |
| `M1` | Read the PR the driver opened and merge it |

### Conventions for every phase

These hold for each phase and are part of its acceptance criteria.

- **No phase changes the version.** `version` in `.claude-plugin/plugin.json`, the sentence `This copy is claude-phases <version>.` that ends both skill descriptions, and `CHANGELOG.md` are changed by the milestone's preparation only.
- Every phase's PR body carries two or three sentences written for the changelog, in the file's voice. `milestone.prepare` assembles the entry from them.
- `scripts/check-skills.sh` passes: no link climbs out of a skill directory. A reference the driver needs lives in `skills/phase-driver/references/`, one the planner needs in `skills/phase-planner/references/`, and neither skill reads the other's files.
- `scripts/check-skill-versions.sh` still passes.
- `claude plugin validate . --strict` passes where the CLI is available. Say in the PR body if it was not run.
- House style: plain sentences, and no em-dashes anywhere, in prose or in headings this plan adds.
- The PR body says what was actually run, in CONTRIBUTING's words: a real run, or "reviewed by reading" when that is the truth.
- The plan format's own names do not change: the `## PR Sequence` heading, the `PR` column, `Phase N:` titles, the Driver State fields. Plans in flight contain them. **No phase adds a Driver State field or a status.**
- A rule stated in the driver and restated for the planner (the recovery table, the Driver-ID table) is changed in both in the same phase.

`ci.dispatch` is `push` and not `auto` because `release.yml` declares `workflow_dispatch`, and dispatching it runs the release job. Never dispatch a workflow here, with the one exception written into `milestone.after_merge`.

## Decisions and rationale

Settled with the owner on 2026-11-24, after a multi-hour VPN outage against a self-managed GitLab. Each phase implements these; none reopens them.

**What stays bound to the forge.** Claims and every other plan write, the merge gates, replies, resolves, pushes and opening a change request. "A status write that could not be made means the action it describes has not started" is unchanged. **Queueing plan writes to replay later is rejected**: by the time a queued claim replayed, the work would have been done without a claim, which is what the lock prevents.

**No time cap on offline work by default.** The owner's words: losing time is the bigger loss than wasting time. A claim's `Heartbeat` cannot be refreshed while the home forge is down, so after 90 minutes a driver on another host may take the plan over and restart the phase. That risk is accepted and answered at reconnect, not by stopping work.

**The guard is the reconnect sequence**, which applies whatever `offline` is set to and before any push:

1. Read the plan and run the Driver-ID check.
2. Rewrite `Heartbeat` with the write token just read. This write is what re-asserts the claim: a stale token means another driver moved, so re-read and re-check whose claim it is.
3. `git ls-remote` the phase branch. For an `In Progress` row it must be absent on the forge.
4. Fetch the target branch. If it moved, rebase and verify again.
5. Push, open the change request, write `In Review` and the `Link`.

**If the claim was lost** (the ID is no longer this session's, or the row is no longer what this session left it as): push nothing, never force, rename the local branch to `<branch>-orphaned` so that the new holder's branch of the same name, later fetches and §7's tidy cannot collide with it, and report what is on it. Nothing ever deletes an orphaned branch.

**Offline work starts only from a fetched base.** §3 step 3 must have completed before the outage: the branch was made from `origin/<target_branch>` after a fetch that succeeded. An outage between the claim and that fetch is a wait.

**Unreachability is per forge.** A plan's repos can sit on different forges and hosts. When only a row's own forge is down and the home forge answers, heartbeats still land and the claim stays fresh. When only the home forge is down, a row's repo can be fetched from but nothing is pushed for it, since `In Review` could not be recorded.

**The limit is configurable.** `offline.max_minutes` under `defaults`, overridable per repo. `null`, the default, is no cap. A number stops the driver starting new offline work once the claim's `Heartbeat` is that many minutes old, so a team with second drivers sets `90` to match the takeover threshold. `offline: false` restores today's total wait, as `stuck.arbiter: null` turns the arbiter off.

**`In Review` phases are included.** Findings and failure text already read from the forge in this session may be fixed and committed offline. On reconnect the review budget is re-derived from the forge before anything is pushed, and a head that is at an arbitration or a stop holds the push and follows the budget table. A finding that needs a verdict the driver could not read is never answered offline.

**The local review pass is optional, single and silent on the forge.** `review.local` names a command that prints findings and posts nothing. It runs once before every push and never again over its own fixes. It never writes a review marker, never counts as a reviewed head, and gate 6 is unchanged. There is no `required` setting in this version.

**Deferred:** a person asking for a fresh arbitration outside the threshold. **Cut:** queued plan writes, and local-first CI as a feature of its own, which `verify: local` already is.

## Phase Details

### Phase 0: Small fixes (sixoverground/claude-phases)

**Scope.** Two faults from the same run, neither about outages, both small enough to be the foundation.

- **The arbiter brief carries the plan, not a path to it.** `skills/phase-driver/SKILL.md`, **Arbitrate**, step 2 briefs the arbiter with "the plan file's path". An arbiter given a path read a stale, untracked local copy and reported the Carried findings entry missing. The driver instead reads the plan from the plan branch as the forge reference's plan read says, writes that text to a file outside the repo's working tree, and gives the arbiter that file with a sentence saying it is the plan branch's current content and that no copy in the checkout is to be trusted. The same wording goes wherever the skill tells the driver to do the pass itself without a subagent.
- **Comment bodies go through files.** One rule in the core, under **Stamp what you write**: write every comment, reply, note and change-request body to a file with the Write tool and pass it by file (`--rawfile`, `--input`, `--body-file`, or the forge's equivalent), never through a heredoc or an inline shell string. Observed: bodies containing `$$` (xcconfig escapes) inside a heredoc made the shell safety check refuse the whole command. `references/forge-gitlab.md` already reads `reply.md` by `--rawfile` and gains a pointer to the rule where it does; `references/forge-github.md` gains the same pointer wherever it shows a `gh` command that takes a body.

**Depends on.** Nothing.

**Acceptance criteria.**
- [ ] **Arbitrate** step 2 no longer tells the driver to pass the plan's path; it describes the fresh export and the warning sentence
- [ ] **Stamp what you write** states the body-file rule once, with the observed failure in one sentence
- [ ] Both forge references point at the rule and show no heredoc or inline body in any snippet that posts text
- [ ] `grep -n '<<' skills/phase-driver` finds no heredoc that carries comment text
- [ ] The conventions above hold

**UAT.**
- [ ] With this branch's skills, on any plan with an open phase PR at its review threshold, let the driver arbitrate. The arbiter's brief should name a file outside the checkout, and the verdict should quote Carried findings as the plan branch has them
- [ ] Ask the driver to reply on a thread with a body containing `$$(SRCROOT)` and a backtick. The reply should post intact, with the driver's stamp, and no command should be refused

**Risks.** A file written inside the working tree could be committed by accident, so the export goes to the session's scratch or temp directory and the phase says so.

---

### Phase 1: A quiet outage (sixoverground/claude-phases)

**Scope.** `skills/phase-driver/references/watching.md`, both templates, and the text around them.

- **No check-in while the forge is down.** Today the fallback check-in prints by wall clock whatever the forge is doing, and each one became a "still unreachable" message for hours. While the watcher's down state says the host is not answering, it prints no check-in. The deadline is kept, so the first poll after the forge answers prints the "answering again" line, and the check-in resumes its normal interval from there.
- **A host-level reachability line.** The watcher polls only open change requests, so with none open it can never say the forge came back. Each template gains a probe of the forge itself (`gh api user`, `glab api --hostname <host> user`), tracked in a `host.down` file beside the per-change-request ones, printing one "unreachable" line and one "answering again" line as the per-change-request states do. The driver arms the watcher with an empty list of change requests whenever it is waiting on the forge with nothing open: a status write that could not be made, or, from phase 2 on, unpushed work.
- **An outage expiry re-arms silently.** **When Monitor expires** already says an expiry with no events is not a wake. Add the sentence that this holds during an outage too: re-arm with the same values, post nothing, tell the user nothing, since they were told once.
- `references/recovery.md`, **The forge is unreachable**, and `docs/running-locally.md` say the same in a line each.

Suppression keys on the down-state files, never on "no change request answered this poll", which is also true when the list is empty.

**Depends on.** Phase 0.

**Acceptance criteria.**
- [ ] Both templates run under macOS bash 3.2 with only `gh` and `jq`, or `glab` and `jq`, and keep the guarded `rm`
- [ ] Run for real against a host that does not resolve: one "unreachable" line, no check-in line for at least two `CHECKIN_MIN` intervals (set `CHECKIN_MIN=1` to test), then one "answering again" line when the host is restored. The PR body says which template was run and how the outage was made
- [ ] With an empty change-request list, the watcher still prints the host's "unreachable" and "answering again" lines
- [ ] With one change request down and another up on the same host, the check-in is not suppressed
- [ ] **When Monitor expires** names the outage case
- [ ] The conventions above hold

**UAT.**
- [ ] With this branch's skills, drive a scratch plan to an open phase PR, then turn Wi-Fi off for a little over an hour. You should see one message that the forge is unreachable and nothing more until you turn it back on
- [ ] Turn Wi-Fi on. Within five minutes the driver should say the forge is answering again and reconcile
- [ ] Repeat with no change request open and a phase `In Progress` whose push failed. The driver should still wake when the forge returns

**Risks.** A suppressed check-in is the backstop for a missed event, so suppression must end the moment anything answers. The first poll after upgrading prints one line per open change request, as earlier template changes did.

---

### Phase 2: Work under a claim that landed (sixoverground/claude-phases)

**Scope.** The change of rule, for an `In Progress` phase.

- **Golden rule 10** in `skills/phase-driver/SKILL.md` is rewritten: an unreachable forge blocks claims, plan writes, pushes and everything posted to a change request, and it does not block work under a claim that already landed. Its last sentence, on a status write that could not be made, stays word for word.
- **§3 says which steps need the forge.** Steps 1 to 3 (reachability, the claim, the fetched branch), 6 (push and open), 7 (`In Review`) and 8 need it. Steps 4 and 5, implement and verify, do not. `verify: ci` and the CI half of `auto` cannot run offline: the phase is committed and waits, and the change request's body says which path ran, as always.
- **The precondition.** Offline work on a phase is allowed only when its claim is on the forge and its branch was made from `origin/<target_branch>` after a fetch that succeeded. Otherwise the outage is a wait, as today.
- **`references/recovery.md`, The forge is unreachable**, is rewritten around three lists: what waits, what carries on, and the reconnect sequence from **Decisions and rationale**, in that order, including the lost-claim branch (push nothing, never force, rename to `<branch>-orphaned`, report). It says unreachability is per forge, and what each half being down means.
- **The `offline` key** in `skills/phase-planner/references/configuration.md`, in a section of its own beside **Stuck detection**: `offline.max_minutes` (default `null`, no cap; a number stops new offline work once the claim's `Heartbeat` is that old, measured from the plan as last read), and `offline: false` for the total wait. Under `defaults`, overridable per repo. It states that the reconnect sequence applies under every setting. The key is added, commented out, to `references/plan-template.md`, and to `references/format.md`'s front-matter example only if that example lists every key.
- **The planner proposes it.** `skills/phase-planner/SKILL.md` and `references/detection.md`: `null` where one driver ever runs the plan, `90` where a second driver on another machine can reach it. That cannot be read from a repo, so it is asked with the other confirmations, and left out of the front matter when the answer is the default.
- **The driver holds unpushed work in the open.** It tells the user once which phase has commits waiting and on which branch, and arms phase 1's host-level watch.

Reaching the limit of `offline.max_minutes` stops new work only: the driver commits what it has and waits. It deletes nothing and marks nothing `Blocked`.

**Depends on.** Phase 1, for the host-level watch.

**Acceptance criteria.**
- [ ] Rule 10, §3 and **The forge is unreachable** agree on what waits and what carries on, and none says "wait" without saying for what
- [ ] The reconnect sequence appears once, in `recovery.md`, in the order given above, and rule 10 and §3 link to it and do not restate it
- [ ] The sequence says in so many words that the Driver-ID check and the token-checked heartbeat write come before any push, and that a push is not protected by the write token
- [ ] The lost-claim branch names the rename, says never force, and says what the report contains: the phase, the orphaned branch, its commit count, and who holds the plan now
- [ ] `configuration.md` documents `offline.max_minutes` and `offline: false` with defaults, and the driver's text reads the key from the row's resolved repo config
- [ ] The planner's text proposes the key by the rule above and writes nothing for the default
- [ ] A plan with no `offline` key behaves as `max_minutes: null`
- [ ] The conventions above hold

**UAT.**
- [ ] With this branch's skills, start a phase on a scratch plan. Once the driver says it has branched, turn Wi-Fi off. It should keep implementing, verify locally, commit, tell you once that the phase is waiting to be pushed, and end its turn
- [ ] Turn Wi-Fi on. It should write a heartbeat first, then push, open the change request and record `In Review`, in that order. Check the plan's commit history for the heartbeat write before the change request's creation time
- [ ] Repeat, and while it is offline edit the plan on the forge from another machine to a different `Driver-ID` with a fresh `Heartbeat`. On reconnect it should push nothing, rename its branch to `<branch>-orphaned`, and tell you
- [ ] Set `offline: false` in the scratch plan and repeat the first step. It should wait, as 0.15.0 does
- [ ] Turn Wi-Fi off before the driver has claimed a phase. It should start nothing

**Risks.** This is the phase that touches the locking model. A driver that pushes before re-asserting its claim can land work on a phase another driver now owns, since the new holder pushes only at its own step 6. The order of the sequence is the whole guard, so the review should read it as a protocol and try to break it.

---

### Phase 3: Recovering a branch that exists only locally (sixoverground/claude-phases)

**Scope.** Reconcile, for the state phase 2 creates. The recovery table's second column is what the forge says, read with `git ls-remote`, so a phase with commits only in the local clone reads as `In Progress` with no branch, and the existing row resets it to `Pending`. That would discard a session's own offline work after a compaction.

- **A new row in `references/recovery.md`**, above the `In Progress`, stale, no branch row: `In Progress`, this session holds the ID (by the Driver-ID rules, a matching `Driver-Host` included), no branch on the forge, and a local branch of the row's name with commits ahead of `origin/<target_branch>`. Do this: it is this session's unpushed work, so carry on from it and go through the reconnect sequence. Never reset it.
- **The same-host successor.** A session that took over because `Driver-Host` showed a dead process on this host checks the local clone before applying the no-branch row. A local branch with commits is treated as **a branch with no PR**: inspect the diff against the phase's scope, finish it, reset it, or ask. The existing section gains that case, and says a reset renames the local branch to `<branch>-orphaned` instead of deleting it when it holds commits the forge never saw.
- **A driver on another host** cannot see the clone and applies the table as it stands. That is the takeover the reconnect sequence's lost-claim branch answers, and the row says so.
- **Orphaned branches.** Reconcile's tidy step and **Tidy the local clone** never touch a branch ending `-orphaned`, and the driver names any that exist once per session in its status report, so they are not forgotten.
- **The planner's copy.** `skills/phase-planner/references/format.md`, **Recovery**, gets the new row in its own shorter wording.

**Depends on.** Phase 2.

**Acceptance criteria.**
- [ ] The new row sits above the row it overrides, and the table still reads top to bottom with the first match winning where two could apply
- [ ] The table's forge column still describes the forge only; the local clone is named as a third fact in the rows that use it
- [ ] **A branch with no PR** covers the local-only case and the rename on reset
- [ ] Both tidy texts exempt `-orphaned` branches, and the delete guard is otherwise unchanged
- [ ] `format.md`'s recovery table and `recovery.md`'s agree row for row on these cases
- [ ] The conventions above hold

**UAT.**
- [ ] With this branch's skills, get a phase to "committed, waiting to be pushed" with Wi-Fi off. Run `/compact`, turn Wi-Fi on, and say `resume`. The driver should find its own branch, say it is resuming unpushed work, and push it. It should not reset the row
- [ ] Do the same, but quit the session instead of compacting, and start a new one on the same Mac. It should take over, find the local branch, and either finish it or ask you, never silently start over
- [ ] After the lost-claim test from phase 2, run `git branch`. The `-orphaned` branch should still be there after the phase merges and the driver tidies

**Risks.** A local branch can be stale work from an earlier attempt at the same phase. The successor path inspects the diff for that reason, and the phase must not turn "a local branch exists" into "adopt it".

---

### Phase 4: Offline fixes on a phase in review (sixoverground/claude-phases)

**Scope.** Rule 10's exception extended to an `In Review` row, in `skills/phase-driver/SKILL.md` §5 and `references/recovery.md`.

- **What may be done offline.** Fixes for review findings and CI failure text that this session read from the forge before the outage, committed on the phase branch, when the local branch's tip is the change request's head as the forge last reported it. Nothing is replied to, resolved or pushed.
- **What may not.** A session that compacted during the outage has lost the findings and does not reconstruct them from memory or from its own commits: it waits. A finding is never answered offline when answering it needs an arbiter's verdict the driver cannot read. So where the plan as last read shows an arbitration in this phase's budget, offline review work is limited to in-scope defects in correctness, security or data, which no bar covers, and everything else waits for the verdict comment.
- **On reconnect, before any push**, after the reconnect sequence's first two steps:
  1. Read the change request: state, head sha, every thread.
  2. If it was merged or closed, or the head moved on the forge, the offline commits are not pushed as they are. Rebase them onto the new head where that is clean and still wanted, and otherwise rename the branch to `<branch>-orphaned` and report.
  3. **Re-derive the reviewed-head count and apply the budget table.** If the table says arbitrate or stop for a person, hold the push and follow the table. The arbiter judges the head the forge has; its brief lists the unpushed commits as changes not yet reviewed. After a verdict, bring the offline commits in line with it before the one push.
  4. Fold in findings that arrived during the outage, so the push answers every open thread at once, then reply and resolve as §5 says.
- **A recovery row:** `In Review`, change request open, local branch ahead of the forge's head, this session or a same-host successor. Do this: the steps above. Never push on the strength of the local commits alone.
- `offline: false` and `offline.max_minutes` govern this as they govern phase 2.

**Depends on.** Phase 3.

**Acceptance criteria.**
- [ ] §5 states the offline rule once and the budget table itself is unchanged
- [ ] The text says the count is derived on reconnect and never carried across the outage, citing **Derive the count; never remember it**
- [ ] The compaction case and the unreadable-verdict case each have an explicit "wait"
- [ ] The reconnect steps hold the push at an arbitration and at a stop, and say what happens to the offline commits in each
- [ ] A merged, closed or moved change request never receives a push of offline commits unexamined, and nothing is forced
- [ ] The conventions above hold

**UAT.**
- [ ] With this branch's skills, wait for a review with two findings on a scratch phase PR, let the driver read them, then turn Wi-Fi off before it pushes. It should fix both, commit, say it is holding one push, and end its turn
- [ ] Turn Wi-Fi on. It should re-read the PR, push once, and reply to and resolve both threads
- [ ] Repeat on a PR already at two reviewed heads with `max_review_rounds: 3`, so the head being answered is the third. On reconnect it should arbitrate before pushing, and the verdict comment should mention the unpushed commits
- [ ] Repeat, and push a commit to the PR's branch from another machine during the outage. On reconnect the driver should not force, and should either rebase cleanly or set its work aside as `-orphaned` and say so

**Risks.** The budget is the one protection against a review loop, and this is the first path that prepares a fix without having evaluated it. Holding at the table on reconnect is the guard; a driver that pushes first and counts afterwards has walked past a stop.

---

### Phase 5: A local review pass before every push (sixoverground/claude-phases)

**Scope.** `review.local`, optional and per repo.

- **The key**, in `skills/phase-planner/references/configuration.md` under **Review**: `review.local.command`, a shell line the driver runs in the repo's clone with `{base}` and `{head}` replaced by the target branch's fetched ref and the commit about to be pushed. Unset, no local pass runs. **It must be a command that prints findings and posts nothing.** The documented one is `codex-mr-review review --base {base} --head {head} --dry-run`, with `--format json` available. There is no `required` setting.
- **When it runs.** In `skills/phase-driver/SKILL.md`: once before every push of a phase branch, the opening push in §3 and every fix push in §5, after verification. **One pass per push.** The fixes it leads to are verified and pushed without a second local pass. That is the cap that keeps an unmetered reviewer from looping, since a local pass is invisible to `stuck.max_review_rounds`.
- **When it cannot run.** The command is not on the `PATH`, or it fails: skip the pass and say so in the change request, as `verify: auto` says which path ran. A failed local pass never blocks a push and never marks a row `Blocked`.
- **Judging what it finds.** By §5's own rules: in scope and right is fixed, minor is carried in the same push or left, wrong is declined, out of scope goes to Carried findings or an issue. Where an arbitration is in this budget, findings are judged against the verdict's bar, read from the change request. If the verdict cannot be read because the forge is down, only in-scope defects in correctness, security or data are fixed and the rest are held until it can.
- **What it never does.** It writes no review marker and no reviewer stamp, posts no thread, satisfies no gate, and is not a reviewed head. Gate 6 and the counting rules are unchanged, and the text says so beside golden rule 11.
- **Disclosure.** Every push that had a local pass is followed by one stamped comment on the change request, or a section of its body on the opening push: the command, the commit it reviewed, what was fixed, and what was declined with the reason. That is the record a thread would otherwise be.
- **The arbiter brief** lists those comments with the review findings, as local findings and what became of them.
- **Planner.** `references/detection.md` and `references/detection-gitlab.md`: propose the key when the repo's reviewer is the local Codex marker reviewer and `codex-mr-review --version` succeeds on the planning machine, as the Xcode row probes `xcodebuild`. Say it is a property of the machine, that a session without the command skips it, and that it adds one Codex run per push. `profiles/review-codex-local.yml` gains the key, and `docs/review-setup.md` a short section.

**Depends on.** Phase 4, which defines what a held finding is.

**Acceptance criteria.**
- [ ] `configuration.md` documents the key, its placeholders, its default, and the non-posting requirement in bold
- [ ] The driver's text places the pass before the push in both §3 and §5 and states "one pass per push" in one place that both link to
- [ ] The absent-command and failed-command cases each end in a push with a disclosed skip
- [ ] The text says a local pass never counts as a reviewed head, with a link to **Count reviewed heads, not reviews**
- [ ] The disclosure comment's contents are listed, and it carries the driver's stamp and nothing of a reviewer's
- [ ] **Arbitrate** step 2's brief includes local findings
- [ ] Both detection references and the profile agree on the command line
- [ ] `codex-mr-review review --help`, run for real, shows `--dry-run`, `--base`, `--head` and `--format`, and the PR body says which version was checked. If a flag differs, the documented command follows the tool
- [ ] The conventions above hold

**UAT.**
- [ ] On the Mac, with this branch's skills and `review.local` set in a scratch plan, start a phase that contains an obvious bug. Before the PR opens, the driver should run the command, fix the bug, and open the PR with a section saying what the local pass found
- [ ] Look at the PR: no review marker and no thread should come from the local pass, and the PR should not count as reviewed until the real reviewer has answered
- [ ] Rename `codex-mr-review` out of the `PATH` and start another phase. The PR should open as usual and say the local pass was skipped because the command was not found
- [ ] Let a review round happen. The fix push should have exactly one local pass before it

**Risks.** A command that posts would let a local run satisfy gate 6 with no review in CI. The key's contract and `--dry-run` are the protection, and the phase must not document any command without it. The pass shares Codex's allowance, and a runner on the same Mac, with the real reviewer.

---

### Phase 6: Cleanup (sixoverground/claude-phases)

**Scope.** The documentation outside the skills, and one consistency pass.

- `docs/design.md`: a section on working through an outage, covering why the claim is as durable as its heartbeat, why the guard sits at reconnect and not at a timer, why queued plan writes were rejected, and why the local pass counts for nothing on the forge. The watcher section's sentence about a night of changing networks is brought up to date. **Things deliberately not done** gains queued plan writes and a `required` local review.
- `docs/running-locally.md`: what an outage looks like now, the `offline` key, `-orphaned` branches and what to do with one, and the local review pass.
- `README.md` and `skills/phase-planner/references/hygiene.md`: a line each where they describe waiting on the forge or a reviewer on the same Mac.
- `examples/gitlab-local.md` gains `review.local` and a commented `offline` key, if its front matter is meant to show a full local setup.
- **Consistency.** Read rule 10, §3, §5, `recovery.md`, `watching.md`, `format.md`'s recovery table and `configuration.md` together, and fix any sentence that still says an unreachable forge means the driver does nothing. Nothing in this phase changes behaviour.

**Depends on.** Phase 5.

**Acceptance criteria.**
- [ ] `grep -rn -i 'unreachable' skills docs README.md` shows no sentence describing the outage as a total wait, except where `offline: false` is being described
- [ ] Every key this plan added appears in `configuration.md`, the template where it belongs, and at least one example or profile
- [ ] `docs/design.md` names the accepted risk of the uncapped default and where the cap is
- [ ] No file under `skills/` changed in this phase other than to fix an inconsistency, and the PR body lists each such fix
- [ ] The conventions above hold

**UAT.**
- [ ] Read `docs/running-locally.md` from the top as someone whose VPN just dropped. It should tell you what the driver is doing, what it will do when the VPN returns, and what an `-orphaned` branch is
- [ ] Read the new section of `docs/design.md`. It should give the reason for each decision in **Decisions and rationale** without your needing this plan

**Risks.** None known.

---

### Milestone M1: Working through a forge outage, 0.16.0 (sixoverground/claude-phases)

**Ships.** Phases 0 to 6: the arbiter brief and body-file fixes, the quiet watcher with its host-level line, offline work under a landed claim with the reconnect sequence and the `offline` key, recovery for local-only branches, offline fixes in review, `review.local`, and the documentation.

**Review scope.** A finding on this PR is in scope when it falls within the scope of phases 0 to 6, taken together, or within what `milestone.prepare` produced. The driver answers it by its usual rules and commits fixes to `feature/offline`. Anything beyond those goes to Carried findings.

**Needed by.** Nothing in the plan. It is the end and the last row, and it exists so the work reaches `main` as one release that a person merges.

**UAT.** On the milestone PR before you merge it:
- [ ] Read the CHANGELOG section the preparation wrote. It should say what an outage now blocks and what it does not, name `offline` and `review.local` with their defaults, and say that a plan with neither key behaves as before except for working through an outage
- [ ] Read the whole diff as one change, the reconnect sequence first

After merging:
- [ ] The release `v0.16.0` should appear with its notes and both skill zips, started by the merge
- [ ] The driver should record `M1`, leave the feature branch deleted since no row targets it any more, set `Driver: idle`, and name any outstanding UAT and carried findings
- [ ] Update the plugin, restart, and ask Claude which version of claude-phases it has. It should say 0.16.0
- [ ] On the released version, on the self-managed GitLab project behind the VPN, drop the VPN while a phase is `In Progress` and after it has branched. The driver should finish and commit the phase, stay quiet, and push through the reconnect sequence when the VPN returns
- [ ] Drive one phase of an existing GitHub plan in a cloud session on the released version. It should behave as it did before this plan

**Risks.** If `main` moved while the plan ran, the preparation's bump may collide; the driver redoes it on what `main` says. This release changes what a driver does while its lock cannot be refreshed, so the claims the CHANGELOG makes should be exactly as strong as the UAT that was actually run.

## Open questions

- **A person asking for a fresh arbitration** outside the threshold is deferred. It needs a decision on whether such an arbitration is recorded in `Arbitrations` and so uses up the budget's one, since a later session finds a verdict by that entry.
- **Whether `review.local` should also run before a milestone branch's fix pushes.** This plan says every push of a phase branch. A milestone PR's fixes are commits to the target branch, and the plan leaves them out until someone asks.

## Driver State

- Driver: running
- YOLO: on
- Driver-ID: 9d0dac66
- Driver-Host: Raphael.local 73385 Tue Nov 24 14:52:15 2026 UTC
- Active: M1, feature/offline (#66)
- UAT-pending: -
- Review-baselines: -
- Arbitrations: -
- Heartbeat: 2026-11-24T16:46:04Z
- Note: M1 ready to merge (#66)

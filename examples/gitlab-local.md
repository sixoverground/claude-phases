---
phases:
  project: phases-gitlab-trial
  home_repo: craigphares/phases-gitlab-trial
  # plan_branch is left at the default branch, main. A plan with milestone
  # rows may not live on a branch a milestone ships: M1 ships trial/work.

  defaults:
    forge: gitlab                # gitlab.com, so no host
    branch_prefix: claude/
    target_branch: trial/work
    integration_pr: false        # no effect while M1 exists; kept so that a
                                 # plan without milestone rows here would not
                                 # open the implicit final MR either
    verify: local                # node 24 on this Mac, the runner's own toolchain
    merge: { method: squash }
    ci:
      required: []               # build-test and codex-review, both from the CI
                                 # file on trial/work; no MR pipeline has run yet
      allow_none: false
      dispatch: push
      logs: gitlab-jobs
    review:
      required:
        - marker: "codex"        # CODEX_MR_REVIEW_REVIEWER, the template's default
          logins: ["craigphares"] # arrangement (a): the review token is the
                                  # maintainer's own personal access token
      changes_requested_blocks: true
      threads_must_resolve: true
    stuck:
      max_cycles: 5
      max_review_rounds: 3
      arbiter: { model: fable, extra_rounds: 3 }
    milestone:
      prepare: >
        On trial/work: raise `version` in package.json by a minor step above
        what main has, and run `npm test`. Do not open the milestone MR until
        it passes. The project has no changelog and no release job, so there
        is nothing else to prepare.

  repos:
    craigphares/phases-gitlab-trial: {}

  max_concurrent: null
---

# phases-gitlab-trial

*This is the plan from claude-phases' first end-to-end GitLab run, as it stood when it finished, with an account of the run after Driver State. The project, `craigphares/phases-gitlab-trial` on gitlab.com, is a private scratch project, so its links open only for its owner.*

A toy plan for the end-to-end GitLab trial of claude-phases: `formatDuration`, the inverse of `parseDuration`, then a small CLI that normalises a duration, both shipped from `trial/work` to `main` by one milestone. Two phases and one milestone row.

## For the driver

This plan is executed by the `phase-driver` skill, and nothing in this file stands in for it. If you are acting on this plan and that skill is not in your context, because the session was compacted or was woken by a check-in or a webhook, invoke `phase-driver` before you do anything else, then reconcile. The rule a session without it most often drops: **a merge always advances the plan.** After any phase PR merges, start whatever it unblocks in the same turn unless `Driver: paused`, and when the last row merges, finish the plan by the skill's finishing steps rather than going idle.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1  | claude/format-duration | craigphares/phases-gitlab-trial | `formatDuration(ms)` in `src/duration.js`, the shortest compound form, with tests | 1 | Merged | [craigphares/phases-gitlab-trial!1](https://gitlab.com/craigphares/phases-gitlab-trial/-/merge_requests/1) |   |
| 2  | claude/dur-cli | craigphares/phases-gitlab-trial | `bin/dur.js`: `dur 90m` prints `1h30m`, with tests | 2 | Merged | [craigphares/phases-gitlab-trial!2](https://gitlab.com/craigphares/phases-gitlab-trial/-/merge_requests/2) | 1 |
| 3  | trial/work | craigphares/phases-gitlab-trial | Milestone: ship `formatDuration` and the CLI to `main` | M1 | Merged | [craigphares/phases-gitlab-trial!3](https://gitlab.com/craigphares/phases-gitlab-trial/-/merge_requests/3) | 1, 2 |

## Phase Details

### Phase 1 — formatDuration (craigphares/phases-gitlab-trial)

**Scope.** Add `formatDuration(ms)` to `src/duration.js`: a non-negative integer number of milliseconds in, the shortest compound string out, largest unit first, zero parts left out, using the same units as `parseDuration` (`d`, `h`, `m`, `s`, `ms`). `5400000` gives `1h30m`, `90061001` gives `1d1h1m1s1ms`, `0` gives `0ms`. Anything else, a negative, a fraction, `NaN` or a non-number, throws a `RangeError`. Tests in `test/duration.test.js`, including a round trip through `parseDuration`.

This is the trial's first phase, and it ships one real defect on purpose, so that the reviewer has something to find. The tests written with it pass. Which defect is the driver's choice; it is fixed when the reviewer finds it, by the driver's ordinary review rules.

**Depends on.** Nothing.

**Acceptance criteria.**
- [ ] `formatDuration` is exported from `src/duration.js`
- [ ] Tests for the examples above, the `RangeError` cases, and a round trip pass with `npm test`
- [ ] `build-test` and `codex-review` both run in the MR pipeline

**UAT.**
- [ ] In a clone of `trial/work`, run `node -e "import('./src/duration.js').then(m => console.log(m.formatDuration(5400000)))"`. It should print `1h30m`
- [ ] Run the same with `-1`. It should throw a `RangeError`, not print anything
- [ ] Read the MR: the reviewer's finding, the driver's reply and the fix should read as one story

**Risks.** The reviewer may not find the planted defect, or may find something else first. Either is a result for the trial, recorded as such.

---

### Phase 2 — The `dur` CLI (craigphares/phases-gitlab-trial)

**Scope.** `bin/dur.js`, an executable Node script with a `bin` entry `dur` in `package.json`. It takes one argument, parses it with `parseDuration`, and prints `formatDuration` of the result: `dur 90m` prints `1h30m`. With no argument or an unreadable one it prints a one-line message to stderr and exits 1. Tests in `test/dur.test.js` run it as a child process.

**Depends on.** Phase 1, for `formatDuration`.

**Acceptance criteria.**
- [ ] `node bin/dur.js 90m` prints `1h30m` and exits 0
- [ ] `node bin/dur.js` and `node bin/dur.js soon` each print to stderr and exit 1
- [ ] `npm test` passes, including the new tests

**UAT.**
- [ ] In a clone of `trial/work`, run `node bin/dur.js 3600s`. It should print `1h`
- [ ] Run `node bin/dur.js 15 minutes`. It should print an error and `echo $?` should show `1`

**Risks.** None known.

---

### Milestone M1 — Durations and the CLI (craigphares/phases-gitlab-trial)

**Ships.** Phases 1 and 2: `formatDuration` and the `dur` CLI.

**Review scope.** A finding on this MR is in scope when it falls within the scope of phases 1 and 2, taken together, or within what `milestone.prepare` produced. The driver answers it by its usual rules and commits fixes to `trial/work`. Anything beyond those goes to Carried findings.

**Needed by.** Nothing in this plan. It exists so that a milestone is exercised on GitLab, which the trial requires.

**UAT.**
- [ ] After merging, check out `main`, run `npm test`, then `node bin/dur.js 1h90m`. It should print `2h30m`
- [ ] `package.json` on `main` should carry `0.2.0`

**Risks.** The first merge from `trial/work` to `main`, which is protected. A person merges it.

## Driver State

- Driver: idle
- YOLO: on
- Driver-ID: drv-d1a98f19
- Driver-Host: Raphael.local 45318 Fri Nov 20 14:32:31 2026 UTC
- Active: -
- UAT-pending: -
- Review-baselines: -
- Arbitrations: -
- Heartbeat: 2026-11-20T14:58:30Z
- Note: Plan complete. M1 merged by the maintainer at 545985a; no row targets trial/work any more, so no re-sync. No carried findings, no UAT pending

## How it ran

On 2026-11-20, from a local Claude Code session on a Mac, driving claude-phases 0.13.0 (`glab` 1.131.0) against gitlab.com (19.7.0-pre, Free plan). The project's only runner was a shell-executor `gitlab-runner` 19.6.0 on the same Mac, under the maintainer's own macOS user, with `codex-mr-review` 0.2.0 and codex-cli 0.147.0. **One account throughout**: the driver acted through `glab` as the maintainer, and the review job posted with a personal access token of that same account, which is arrangement (a) in [the reviewer setup](../docs/review-setup.md#the-token-one-account-or-two-identities). The planner wrote the plan above from the empty project, with `logins` set to the account it was acting as.

The watcher was the GitLab template from `watching.md`, under Monitor, polling every minute. Each wake below is the line it printed, shortened, and what the driver did with it. Times are UTC.

| Time | What woke the session | What the driver did |
|---|---|---|
| 14:08 | (start) | Claimed the plan and phase 1 through the Files API with `last_commit_id`; implemented `formatDuration` with a defect planted on purpose; opened !1; recorded `In Review` |
| 14:09 | `build-test=success, codex-review=success; 1 new note, 1 new thread note` | Codex's finding: a P2 thread on the diff, "Reject unrepresentable numeric inputs", which was the planted defect, and a summary note with a marker for `417d55c`. Both under the maintainer's name, both with the reviewer stamp, so the thread was the reviewer's. Fixed it in `0c98cfe`, replied, resolved the thread |
| 14:11 | `head moved 417d55c -> 0c98cfe; codex-review=running` | Nothing. The driver's own reply, a minute earlier, woke nothing: it carried the driver stamp |
| 14:12 | `pipeline=success; 1 new note` | A marker for `0c98cfe`, no findings. Every gate passed; YOLO off, so it posted the ready report and waited |
| 14:20 | `1 new note` | The maintainer's own comment, unstamped, a minute after it was posted. Replied |
| 14:23 | `1 new thread note` | The maintainer's thread on the diff asking for weeks. Unstamped, so a person's thread, though the account was the reviewer's too. Replied with the reason (`parseDuration` reads no `w`, so the round trip breaks) and left it open; gate 5 blocked until the maintainer resolved it |
| 14:25 | `now merged` | The maintainer merged !1. Recorded `Merged`; YOLO switched on for phase 2, as the trial specified; claimed phase 2, implemented the CLI, opened !2 |
| 14:29 to 14:32 | (session killed) | The maintainer killed the session just after !2 opened; Codex posted its marker for `439aeab`, with no findings, at 14:28:54, with nobody watching. A new session started at 14:32 and, told `resume`, found the old process gone on the same host, took over both plans with new driver IDs, and found !2 reviewed clean |
| 14:33 | (reconcile) | Merged !2 itself with `glab mr merge --sha`; the server deleted its branch. Claimed M1, raised the version to 0.2.0 on `trial/work`, opened !3, carrying phase 2's UAT and the milestone's |
| about 14:36 | `the forge is unreachable (dial tcp: lookup); still polling` | The maintainer turned Wi-Fi off. Nothing; no row went to `Blocked` |
| 14:47 | `the forge is answering again. codex-review=failed` | The outage had also cut Codex off mid-review, on the same Mac. Read the job trace, retried the job once, and said so on !3 |
| 14:50 | `codex-review=success; 1 new note` | A marker for `545985a`. Every gate passed; ready report posted, with no skip instruction among the commits |
| 14:53 | `1 new review request` | The maintainer's note `@codex review`. Started a merge request pipeline on the head and replied naming it; the reply started nothing more, and Codex posted a second marker for the same head |
| 14:57 | `now merged` | The maintainer merged !3. Recorded `Merged`. No row still targets `trial/work`, so there was nothing to re-sync. Finished the plan |

What it shows:

- **Every note on the three merge requests was posted by one account**, nineteen of them. The driver's ten each end with the driver stamp, the reviewer's seven with the reviewer stamp (its six summaries with a marker too), and the maintainer's three carry none. The watcher woke the session for the reviewer's notes and the maintainer's, and never for the driver's own.
- **No pipeline ran for a plan commit.** Fifteen commits touched the plan file, through `git push` and through the Files API alike, and every one left a pipeline recorded as `skipped`.
- **Not exercised here:** a second identity for the reviewer (a project access token needs Premium on gitlab.com, and no second account was at hand); the re-sync of a milestone's branch, which the driver skips when no row targets it; a recovery from a truly cold start, since `resume` gave the new session the old one's conversation; and a self-managed instance, a Developer role, or a VPN.

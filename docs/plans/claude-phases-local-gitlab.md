---
phases:
  project: claude-phases-local-gitlab
  home_repo: sixoverground/claude-phases
  # plan_branch is left at its default, the home repo's default branch (main).
  # A plan with milestone rows may not live on a branch a milestone ships.

  defaults:
    branch_prefix: claude/
    merge: { method: squash }
    ci:
      required: []                 # every reported check counts; nothing is named, see below
      allow_none: false
      dispatch: push               # release.yml declares workflow_dispatch and dispatching it releases
      logs: actions
    review:
      required:
        - logins: ["chatgpt-codex-connector"]
          rereview: optional       # smart detect: a thumbs up on #27, reviews on #22 to #27.
                                   # Confirmed to review PRs into a non-default base too
          rereview_grace: 15m
      changes_requested_blocks: true
      threads_must_resolve: true
    stuck:
      max_cycles: 5
      max_review_rounds: 3
      arbiter: { model: fable, extra_rounds: 3 }

  repos:
    # Markdown skills plus shell scripts. Phases land on the feature branch and
    # reach main at milestones. Checks seen on PRs into main: "Build skill zips",
    # "Version bumped", "Tag and release" (skipped). Phase 0a makes
    # "Version bumped" skip for PRs into the feature branch, so it is
    # deliberately NOT in ci.required.
    sixoverground/claude-phases:
      target_branch: feature/local-gitlab
      verify: auto                 # the scripts in scripts/ are the local build; see Conventions
      # Read by the driver from phase 0b's release on. The released 0.9.3 ignores them.
      milestone:
        prepare: >
          On the feature branch: raise `version` in .claude-plugin/plugin.json by a
          minor step above what main has; update the sentence
          "This copy is claude-phases <version>." that ends both skill descriptions;
          add one "## [<version>]" section at the top of CHANGELOG.md, in the file's
          voice, assembled from the changelog sentences in the PR bodies of the
          phases this milestone ships. Then run scripts/check-version-bump.sh
          origin/main, scripts/check-skill-versions.sh and scripts/release.sh
          --dry-run, and do not open the milestone PR until all three pass.
        after_merge: >
          Run `claude plugin marketplace update sixoverground` and
          `claude plugin update claude-phases@sixoverground` on the machine this
          session runs on. Then say in the milestone-merged message which version
          is installed and whether this session must be restarted to load it, per
          the finding recorded in phase 0d. If the commands are unavailable here,
          as in a cloud session, say that they still have to be run on the Mac.

    # Created by hand before phase 8: public, cloud Codex review enabled.
    # No PR history yet, so its checks and reviewer are unobserved. Phase 8
    # adds its CI in its own PR.
    sixoverground/codex-mr-review:
      target_branch: main
      verify: local                # Node; `npm test` and `npm run lint`

  max_concurrent: null
---

# claude-phases-local-gitlab

Make claude-phases run from a local Claude Code session and drive GitLab as well as GitHub, and build a small separate tool that runs the Codex CLI's review mode in a GitLab pipeline and proves it did. Twenty-three rows across two repos: sixteen phases and three milestones in `sixoverground/claude-phases`, and four phases in a new tool repo. The plan begins by building the thing it then relies on: **milestones**, a row that ships a feature branch to the default branch when a later phase needs the work released. Once that is on `main`, by hand, once, the driver opens every later merge to `main` itself and a person merges it. The first real user is a client project on a self-managed GitLab that cloud sessions cannot reach, and that project is deliberately not part of this plan.

## For the driver

This plan is executed by the `phase-driver` skill, and nothing in this file stands in for it. If you are acting on this plan and that skill is not in your context, because the session was compacted or was woken by a check-in or a webhook, invoke `phase-driver` before you do anything else, then reconcile. The rule a session without it most often drops: **a merge always advances the plan.** After any phase PR merges, start whatever it unblocks in the same turn unless `Driver: paused`, and when the last row merges, finish the plan by the skill's finishing steps rather than going idle.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1  | claude/scope-version-check | sixoverground/claude-phases | `.github/workflows/release.yml`: run `Version bumped` only for PRs into `main` | 0a | In Progress | - |  |
| 2  | claude/milestones-driver | sixoverground/claude-phases | Milestone rows: format, `milestone.prepare` and `milestone.after_merge`, driver behaviour, recovery; the integration PR becomes the implicit final milestone | 0b | Pending | - | 0a |
| 3  | claude/milestones-planner | sixoverground/claude-phases | Planner proposes milestones and writes `milestone.prepare`; refusals, hygiene, README and design notes | 0c | Pending | - | 0b |
| 4  | claude/release-milestones | sixoverground/claude-phases | Bootstrap release prep: version bump, CHANGELOG, descriptions. The maintainer then ships it to `main` by hand, the one time | 0d | Pending | - | 0c |
| 5  | claude/review-marker-contract | sixoverground/claude-phases | Review contract v1: `docs/review-contract.md`, the forge-neutral `marker` entry in `review.required`, gate 6 reads it | 1 | Pending | - | 0d |
| 6  | claude/forge-neutral-driver | sixoverground/claude-phases | Behaviour-neutral: move GitHub specifics out of driver `SKILL.md` into `references/forge-github.md` | 2a | Pending | - | 1 |
| 7  | claude/forge-neutral-gates | sixoverground/claude-phases | Behaviour-neutral: split `gates.md` and `recovery.md` into forge-neutral rules plus the GitHub mapping | 2b | Pending | - | 2a |
| 8  | claude/local-watcher | sixoverground/claude-phases | Local sessions: `references/watching.md`, the polling watcher, and "forge unreachable is not Blocked" | 3 | Pending | - | 2b |
| 9  | feature/local-gitlab | sixoverground/claude-phases | Milestone: ship the review contract, the forge-neutral driver and local running to `main` | M1 | Pending | - | 1, 2a, 2b, 3 |
| 10 | claude/forge-config | sixoverground/claude-phases | Config keys `forge`, `host`, `integration_pr`, `ci.logs: gitlab-jobs`; `group/project` ids and `!42` links; forge selection in the driver | 4 | Pending | - | M1 |
| 11 | claude/gitlab-driver-core | sixoverground/claude-phases | `references/forge-gitlab.md` part 1: plan reads and writes, finding, opening and merging MRs, milestones, finishing | 5a | Pending | - | 4 |
| 12 | claude/gitlab-gates | sixoverground/claude-phases | `references/forge-gitlab.md` part 2: the six gates, job traces, discussions, the watcher command | 5b | Pending | - | 5a |
| 13 | claude/gitlab-planner | sixoverground/claude-phases | Planner: `references/detection-gitlab.md`, four new refusals, hygiene items, `profiles/ci-gitlab-runner-macos.yml` | 6 | Pending | - | 5b |
| 14 | claude/local-docs-verify | sixoverground/claude-phases | `docs/running-locally.md`, README local sections, `verify: local` for iOS on a Mac | 7 | Pending | - | 6 |
| 15 | claude/tool-scaffold | sixoverground/codex-mr-review | Node CLI skeleton, tests, lint, GitHub Actions CI, `AGENTS.md` | 8 | Pending | - | 1 |
| 16 | claude/review-runner | sixoverground/codex-mr-review | Run `codex exec review` read-only, normalise findings into cloud Codex's shape, print them with `--dry-run` | 9 | Pending | - | 8, M1 |
| 17 | claude/gitlab-posting | sixoverground/codex-mr-review | Post findings as MR discussions, summary note, script-owned marker, fingerprint dedupe | 10 | Pending | - | 9 |
| 18 | claude/ci-template-install | sixoverground/codex-mr-review | `.gitlab-ci.yml` job template, one-command install, secret hygiene, README, v0.1.0 | 11 | Pending | - | 10 |
| 19 | claude/review-setup-marker | sixoverground/claude-phases | `docs/review-setup.md` section for GitLab plus local Codex, `profiles/review-codex-local.yml`, planner detects a marker reviewer, GitLab marked experimental | 12 | Pending | - | 7, 11 |
| 20 | feature/local-gitlab | sixoverground/claude-phases | Milestone: ship GitLab support, the planner on GitLab, the local guide and the marker reviewer setup to `main` | M2 | Pending | - | 4, 5a, 5b, 6, 7, 12 |
| 21 | claude/gitlab-trial | sixoverground/claude-phases | End-to-end trial on a gitlab.com scratch project; `examples/gitlab-local.md`; fixes the trial exposes | 13 | Pending | - | M2 |
| 22 | claude/gitlab-cleanup | sixoverground/claude-phases | Cleanup: lift or narrow "experimental", docs say GitHub or GitLab, design notes | 14 | Pending | - | 13 |
| 23 | feature/local-gitlab | sixoverground/claude-phases | Milestone: ship the trial's corrections and the final documentation to `main` | M3 | Pending | - | 13, 14 |

Rows `M1`, `M2` and `M3` are milestone rows, the row kind phase 0b defines: the branch is the repo's `target_branch`, the PR goes to the default branch, and `Depends` lists what it ships. **A driver that does not know milestone rows must not start one.** The released 0.9.3 does not, and it cannot reach one here before the bootstrap, since every milestone depends on phases that come after phase 0d.

The home repo's phases are serial because a repo carries one open phase PR at a time. The tool repo runs beside them: phase 8 starts as soon as phase 1 merges, phase 9 once `M1` has, and phases 10 and 11 follow in order while the home repo works through 4 to 7. The two tracks meet at phase 12.

## How this plan is driven

### Milestones: when the work reaches `main`

Home-repo phases merge into `feature/local-gitlab`. The marketplace serves `main`, and a session drives with what is installed, so the branch is shipped to `main` whenever a later phase needs the **installed** driver to have what was built, and at no other time.

| Ships | What | Needed by |
|---|---|---|
| **Bootstrap**, by hand after 0d | 0a to 0d: the scoped version check and milestones themselves | Every later milestone. The driver cannot open a milestone PR until the driver that knows how is installed |
| **M1** | 1, 2a, 2b, 3: the review contract, the forge-neutral driver, the watcher | Phase 9, which has to be driven from a session on the Mac where the Codex CLI is logged in. A local session has nothing to wait with until the installed driver has the watcher |
| **M2** | 4, 5a, 5b, 6, 7, 12: GitLab support, the planner on GitLab, the local guide, the marker reviewer setup | Phase 13, which drives a real gitlab.com project with the installed driver and planner |
| **M3** | 13, 14: the trial's corrections and the final documentation | The end of the plan |

Three driven milestones is the fewest the real dependencies allow. M1 cannot wait for M2: the tool track would sit idle for six phases with nothing able to drive it locally. M2 cannot be folded into M3: the trial is what M3 ships, and it cannot run on a driver that lacks M2. The bootstrap is the price of building the feature inside the plan that uses it.

M1 is a complete release for a GitHub user. M2 ships GitLab support before anything has driven a real GitLab project with it, so phase 12 labels it experimental and phase 14 lifts or narrows the label on the trial's evidence.

### What the driver does at a milestone, from M1 on

This is the behaviour phase 0b specifies; it is summarised here because this plan depends on it.

1. When every phase in a milestone's `Depends` is `Merged`, the driver claims the row, runs `milestone.prepare` on the feature branch (the version bump, the CHANGELOG section, the two description lines), and opens a PR from `feature/local-gitlab` to `main` carrying the UAT script for everything not yet shown to a person. It does this with YOLO on or off.
2. It works that PR like any PR it opened: fixes failing checks, answers review by the skill's existing rules, counts rounds, calls the arbiter at the threshold. Fixes are commits pushed straight to the feature branch. When the gates pass it says the PR is ready. **It never merges it.** The merge to `main` is the maintainer's, every time.
3. While the milestone PR is open, nothing starts in this repo: it is the repo's one open PR. The tool repo carries on.
4. When the maintainer merges it, the driver records `Merged`, brings the feature branch back in line with `main` (GitHub deletes it on merge here, so it is re-created from `main`), runs `milestone.after_merge`, which updates the installed plugin, and starts what the milestone unblocks.

**The dependency is the wait.** Phase 4 depends on `M1`, so it cannot start before `M1` is `Merged`, and by then the branch is back in line with `main`. Nobody has to say `pause`. Phase 4 needs no capability check of its own for that reason: it is prose that the milestone-aware driver can already write. Phases 9 and 13 keep a precondition at the top, because they need the *running session* to hold the new skills, which the dependency alone does not guarantee if a restart turns out to be required.

**One thing may stay manual: restarting the session.** Whether a running Claude Code session picks up an updated plugin without a restart is not known. Phase 0d finds out and records it. If a restart is needed, the driver says so in its milestone-merged message and that is the remaining step.

**M1 is also where the driver moves to the Mac.** Everything up to and including `M1` can be driven from any session, a cloud one included. From `M1` on it has to be a Claude Code session on the Mac: phase 9 runs the real Codex CLI with the maintainer's login, phases 10, 11 and 13 need that machine and a GitLab runner on it. A cloud session that drives `M1` cannot update the Mac's plugin, so after merging `M1`: run the two commands from `milestone.after_merge` on the Mac, start `claude` there, and say `resume`. The takeover between sessions is the ordinary one.

### The bootstrap, by hand, once

The released driver knows nothing of milestone rows, so the first shipment cannot be one. After phase 0d is ready to merge:

1. Say **`pause`**, then merge phase 0d's PR. The driver records `Merged` and starts nothing.
2. Open a PR from `feature/local-gitlab` to `main`. `Version bumped` runs on it, because its base is `main`, and finds 0d's bump. Read it as one change and merge it. The merge cuts the release.
3. GitHub deletes the feature branch. Re-create it from `main`: `git fetch origin && git push origin origin/main:refs/heads/feature/local-gitlab`.
4. Run `claude plugin marketplace update sixoverground` and `claude plugin update claude-phases@sixoverground`. **Before restarting anything**, ask the running session whether its `phase-driver` has a Milestones section. Write down the answer: it settles the restart question for the rest of the plan.
5. Start a fresh session regardless, and say **`resume`**.

If `pause` is forgotten and phase 1's PR is already open against the feature branch when the bootstrap PR merges, do not re-cut the branch, since deleting a base branch closes the PRs into it. Use "Restore branch" on the merged PR, having merged it with a merge commit and not a squash.

### Why the plan file is on `main`

A plan with milestone rows may not live on a branch a milestone ships: this repo deletes head branches on merge, and a plan on a deleted branch stops the driver, as `hygiene.md` warns. So `plan_branch` is left at its default. Plan commits end `[skip ci]`, and the only push-triggered workflow on `main` is filtered to `.claude-plugin/plugin.json`, so they start nothing. Phase PRs never touch the plan file, so the feature branch never conflicts with it.

### YOLO

**YOLO starts off, by the maintainer's choice.** This plan edits the skill that is driving it, and its early phases are judged on whether a GitHub run still behaves the same, which is a person's call at each merge. YOLO never reaches a milestone PR either way.

**Trying a phase's skills before they are released.** Several UAT steps say to use "this branch's skills", since with YOLO off UAT happens before the merge and well before a milestone. For that, load the plugin from a checkout for one session: `claude plugin disable claude-phases@sixoverground`, then `claude --plugin-dir <a clone checked out at the phase branch>`, and re-enable the installed plugin afterwards. Confirm at first use, in phase 0b's UAT, that the repo root loads as the plugin and that disabling the installed copy is what avoids two `phase-driver` skills. This is for UAT. It is not how the plan is driven; the milestones are.

### Prerequisites only a person can do

| Before | Do this |
|---|---|
| Committing this plan | Create `feature/local-gitlab` from `main` in `sixoverground/claude-phases`. Commit this file to `main` at `docs/plans/claude-phases-local-gitlab.md`, directly, with a message ending `[skip ci]`. Update the installed plugin: the copy found on the Mac was 0.7.0 and `main` is 0.9.3 |
| Phase 1 | The bootstrap above |
| Phase 8 | Create `sixoverground/codex-mr-review` on GitHub, public, with an initial commit on `main` (a README is enough). Add it to the session's scope. Enable cloud Codex code review for it in ChatGPT's Codex settings |
| Phase 9 | `M1` is merged and installed on the Mac. `codex login` is current (codex-cli 0.147.0 was found installed), and Node 20 or later |
| Phase 5a UAT and phase 10 UAT, and required by phases 11 and 13 | On the Mac: install `glab` (it was not installed when this plan was written) and `jq`. Create a personal gitlab.com project. Create two tokens on it with `api` scope, one for the driver and one for the reviewer, so the two post under different identities. Register a GitLab Runner on the Mac with the shell executor, tagged `macos` |
| At each of M1, M2, M3 | Read the PR the driver opened and merge it |

### Conventions for every phase in `sixoverground/claude-phases`

These hold for each home-repo phase and are part of its acceptance criteria.

- **No phase changes the version, except 0d.** `version` in `.claude-plugin/plugin.json`, the sentence `This copy is claude-phases <version>.` that ends both skill descriptions, and `CHANGELOG.md` are changed by a milestone's preparation, and by phase 0d for the bootstrap. Phase 0a is what makes that possible.
- Every phase's PR body carries two or three sentences written for the changelog, in the file's voice. `milestone.prepare` assembles the entry from them.
- `scripts/check-skills.sh` passes: no link climbs out of a skill directory. A reference the driver needs lives in `skills/phase-driver/references/`, one the planner needs in `skills/phase-planner/references/`, and neither skill reads the other's files.
- `scripts/check-skill-versions.sh` still passes, which in a phase means nobody edited a description's version sentence by accident.
- `claude plugin validate . --strict` passes where the CLI is available. Say in the PR body if it was not run.
- House style: plain sentences, no em-dashes in prose. The separators in phase headings, `Active` entries and the gate report stay.
- The PR body says what was actually run, in CONTRIBUTING's words: a real run, or "reviewed by reading" when that is the truth.
- The plan format's own names do not change: the `## PR Sequence` heading, the `PR` column, `Phase N:` titles. Plans in flight contain them.

`ci.dispatch` is `push` and not `auto` for a reason specific to this repo: `release.yml` declares `workflow_dispatch`, and dispatching it runs the release job. Never dispatch a workflow here.

## Decisions and rationale

Settled with the maintainer before this plan was written. Recorded so that a later reader does not reopen them by accident.

**The core is forge-neutral, and each forge is one reference file.** The driver's rules are about plans, phases, gates and recovery. Which API call opens a change request is a detail of the forge. Today the two are interleaved, so a second forge would mean a second copy of every rule or a conditional in every paragraph. After phases 2a and 2b the core says "change request" and "the forge is the truth", and `references/forge-github.md` holds what is true only of GitHub: MCP tools against `gh pr create` and who that makes the opener, reactions and the thumbs up, `rereview: optional`, check runs against statuses, Actions logs, branch deletion, the issue fallback, plan writes through the contents API with a blob sha. The refactor lands alone and changes nothing for GitHub, so that if a GitHub run regresses later, the cause is one of two reviewable diffs.

**A contract, and no coupling.** claude-phases specifies what a reviewer must leave behind: inline resolvable threads for findings, and after every completed review a note carrying `<!-- phases:review v=1 reviewer=<name> sha=<full sha> -->`. Any tool that emits that satisfies a `{ marker: "<name>" }` entry, with an optional `logins` list pinning who may author the note. The entry is forge-neutral: it is specified in the core gate and read from GitHub PR comments as readily as from GitLab merge request notes, so a self-hosted reviewer that meets the contract works on GitHub too. The review tool does not know claude-phases exists; its ordinary summary note simply contains the marker. The contract is specified first, in phase 1, so the tool and the driver can be built in parallel against it.

**The script owns the marker, never the model.** The marker is written by the tool's own code, only after `codex exec` exits successfully, with the sha taken from the pipeline's environment. Nothing the model outputs can supply or alter it, and model output is scrubbed of anything that looks like one. Proof of review has to be deterministic and has to survive a diff that contains instructions. A commit cannot contain its own hash, so text in the diff cannot forge a marker for the head it belongs to.

**Cloud Codex reviews the home repo.** `.github/workflows/code-review.yml` is disabled and the earlier plan's `Claude review` entry is stale; Codex reviewed #22 to #27 and is confirmed to review PRs whose base is not `main`, so `feature/local-gitlab` phase PRs are reviewed. The front matter's `logins: ["chatgpt-codex-connector"], rereview: optional` entry stands.

**Codex runs read-only with no network and never holds the forge token.** The tool holds the token and does the posting. Codex reads the checkout and returns findings. A prompt injection in the diff can then at worst produce a bad finding, which a person or the driver reads as a finding.

**A separate tool repo, like `anthropics/claude-code-action`.** claude-phases is instructions and configuration with no runtime of its own, and its review setups all point at a reviewer maintained elsewhere. A Node CLI with tests, releases and a security surface does not belong inside a skills plugin, and people who never use claude-phases can use the tool.

**The tool looks like cloud Codex, so the driver needs no new rules for it.** The driver already knows how to read a Codex review: what is in scope, what is minor and never starts a push, when to disagree and resolve, how rounds are counted, when the arbiter steps in, how a repo's own stop rules and severity bar apply. All of that is in `phase-driver` today and none of it is restated or changed here. The tool's job is to produce the same artefacts cloud Codex does, inline threads with the same P0 to P3 labelling and a summary, so those rules apply as written. This plan adds mappings from a forge's objects to the existing rules and adds no rule about interpreting a review.

**GitLab posting only, for now.** The tool posts to GitLab merge requests. Posting to GitHub pull requests is a possible follow-up and is in no phase here, even though the `marker` entry would accept it.

**Milestones generalise the integration PR.** The driver already ends a plan by opening a PR from the feature branch to the default branch and never merging it. A milestone is that same act at a point the plan names, in a row of the table. The rule that made the integration PR safe carries over unchanged: **the driver opens it, a person merges it**, whatever YOLO says. A plan with no milestone rows behaves exactly as it does today, its integration PR being the one implicit, final milestone.

**An explicit milestone opens whatever YOLO says; the implicit one does not.** A milestone row is a checkpoint someone planned, and later phases wait on it, so the driver opens its PR with YOLO on or off. YOLO only ever decided who merges phase PRs. The integration PR of a plan with no milestone rows keeps 0.9.3's rule and opens only under YOLO, so no existing plan changes.

**A milestone PR is worked like any PR the driver opened.** Checks are fixed and review is answered by the rules the skill already has, with round limits, the arbiter and stop rules applying as they do on a phase. In scope means the union of the shipped phases' scopes. Fixes, like the preparation, are direct commits to the feature branch, and each one moves the head, so the gate and the reviewer see it again. The one thing withheld is the merge.

**With milestone rows, the plan lives on the default branch.** A shipped branch is deleted on merge and re-created, so a plan there would not survive its first milestone. This narrows the older advice to keep a feature-branch plan on the feature branch, which still holds for plans without milestone rows.

**Re-sync moves a branch only when nothing can be lost.** After a squash or rebase merge the feature branch is moved to the default branch's head only if its head is exactly the head that was merged. Anything else is left alone and reported.

**A milestone row needs no new column.** It is an `M<n>` id together with a `Branch` equal to the repo's `target_branch`, which no phase branch can be. The rows sit in this plan's table from the start, before the driver that understands them is installed, because seeing the whole shape matters more than the small risk, and the bootstrap includes updating the plugin.

**A dependency replaces `pause`.** A phase that needs earlier work released depends on the milestone row that ships it, and the driver cannot start it until that row is `Merged`. The wait is in the table where a new session can read it, and not in someone remembering to pause.

**Merge to `main` only when something needs it.** Every merge to `main` of this plugin is a release, so each milestone here is justified by a phase that needs the installed driver to have what it ships. Phase 0a exists because the `Version bumped` check ran on every PR whatever its base, which would have forced a bump per phase. With it scoped to `main`, the only PRs that need a bump are milestone PRs, and `milestone.prepare` is what gives them one.

**Preparation is committed straight to the feature branch.** The version bump and changelog are not a phase and get no PR of their own into the feature branch. The milestone PR is their review: a person reads it and merges it, and the version check runs on it. A separate PR would buy a review round for a diff that is reviewed again minutes later.

**Updating the installed plugin is this plan's business, expressed generically.** `milestone.after_merge` is an optional instruction any repo can set. Here it updates the plugin, which only a plan that develops its own driver needs.

**Locally, a watcher replaces subscriptions.** A cloud session is woken by GitHub webhooks. A local session has none, and a self-managed GitLab behind a VPN could not deliver them anyway. So the driver arms a polling loop that prints a line only when an open change request changes, plus a long fallback check-in. It is a command the driver composes from a template in the skill, because the project ships no runtime code, and it runs under the Monitor tool. Monitor caps a watch at 30 minutes, so an expiry with no events is a cheap re-arm and not a wake. Where a session can subscribe, it still does, so GitHub cloud behaviour is unchanged.

**A forge you cannot reach is a wait.** VPN down, Mac asleep, a network error: none of these is a phase needing a person, and `Blocked` is cleared only by a person. The driver backs off, says so once, and carries on when the forge answers.

**The integration MR is the client's call.** `integration_pr: false` stops the driver opening the implicit final milestone, the change request from the long-lived branch to the default branch at the end of a plan that has no milestone rows.

**Xcode Cloud is not a phase gate here.** In the client setup it builds pushes to the long-lived branch for TestFlight. The gate is the runner's `build-test` job and the review job.

## Phase Details

### Phase 0a — Scope the version check to `main` (sixoverground/claude-phases)

**Scope.** One workflow file, so that phases can land on a feature branch without a version bump each.

`.github/workflows/release.yml` has a job `version-bumped` (check name `Version bumped`) that runs on every `pull_request` whatever its base. It runs `scripts/check-version-bump.sh` against `github.event.pull_request.base.sha`, and `scripts/check-skill-versions.sh` in the same job. A PR into `feature/local-gitlab` that touches `skills/` therefore fails unless it bumps the version, which is the opposite of what a feature branch is for.

Change the job's condition to:

```yaml
if: github.event_name == 'pull_request' && github.event.pull_request.base.ref == 'main'
```

and update the comments at the top of the file to say why: the marketplace serves `main`, so the version matters at the moment something reaches `main` and at no other.

A job-level `if` is chosen over a `branches: [main]` filter on the trigger. With the filter the workflow does not run at all for a PR into a feature branch and the check is simply absent, which on this project reads as CI that stopped reporting. With the `if`, the check appears as skipped, which the checks gate counts as passing and which tells a person the omission is deliberate. It also sits beside the `release` job's own `if`, so both conditions are read in one place.

Why editing it on the feature branch is enough: for a `pull_request` event GitHub runs the workflow file from the PR's merge commit, the head merged into the base. So this PR is judged by its own edited copy, and every later PR into `feature/local-gitlab` inherits the edit from the base. `main` keeps the old file until the bootstrap, and from then on the branch has it from `main`. A milestone PR's base is `main`, so the check runs on it under either version of the file, and that is the one place it should: only a milestone PR needs a bump, and the milestone's preparation supplies it.

This phase touches only `.github/`, which `check-version-bump.sh` does not guard, so it would pass under the old rule as well.

**Depends on.** Nothing.

**Acceptance criteria.**
- [ ] The `version-bumped` job carries the condition above, and no other job or trigger in `release.yml` changed
- [ ] On this PR, `Version bumped` reports as skipped and `Build skill zips` passes
- [ ] The diff touches nothing outside `.github/workflows/release.yml`
- [ ] The file's header comment explains the scoping in the file's existing voice
- [ ] `ci.required` in this plan's front matter still names nothing: a check that is skipped by design on this branch must not be required on it

**UAT.**
- [ ] Open this PR's Checks tab. `Version bumped` should show as skipped, and `Build skill zips` as passed
- [ ] After merging, open a throwaway PR into `feature/local-gitlab` that adds a blank line to a file under `skills/`, with no version bump. `Version bumped` should be skipped and nothing should be red. Close it
- [ ] Open a throwaway PR with the same one-line change into `main`. `Version bumped` should run and fail, as it does today. Close it

**Risks.** If the claim about which workflow file GitHub uses were wrong, this PR's own check would run and pass regardless, and the first sign would be phase 0b failing `Version bumped`; the second UAT step exists to find that out a phase early. Cloud Codex does review PRs whose base is not `main`, the maintainer confirms, so the reviewer entry in the front matter holds for PRs into the feature branch.

---

### Phase 0b — Milestones: format, configuration, driver (sixoverground/claude-phases)

**Scope.** A new kind of row that ships a feature branch to the default branch, and everything the driver does with it. The integration PR the driver already opens at the end of a plan becomes the implicit case of the same thing. **A plan with no milestone row behaves exactly as it does at 0.9.3.**

- `skills/phase-planner/references/format.md`:
  - A new subsection of **PR Sequence Table**, **Milestone rows**. A milestone row is told apart by two things together, with no new column: its `Phase` id is `M` followed by a number, and its `Branch` is the repo's `target_branch`, which no phase row can be, since phase branches carry `branch_prefix`. A row with one sign and not the other is an error the driver stops on. Its PR goes from that branch to the repo's default branch. Its `Depends` lists the phases it ships. A later phase that needs that work released depends on the milestone row. Titles read `Milestone M1: <scope>`. Milestone rows are appended or inserted like any row and never renumbered.
  - **Status vocabulary** for a milestone row, same words: `In Progress` is claimed and preparing, `In Review` is the milestone PR open and waiting on a person, `Merged` is a person merged it. `Blocked` and `Skipped` as for a phase.
  - **Phase Details** gains the milestone section shape: `### Milestone M1 — <name> (repo)` with **Ships.**, which is also what defines in-scope when the PR is reviewed, **Review scope.** A finding on this PR is in scope when it falls within the scope of phases 1, 2a, 2b and 3, taken together. The driver answers it by its usual rules and commits fixes to `feature/local-gitlab`. Anything beyond those scopes goes to Carried findings.

**Needed by.**, **UAT.** for the end-to-end flows that only exist once those phases are together, and **Risks.**
  - **When UAT reaches a human**: a milestone PR carries the assembled script for every id in `UAT-pending` that it ships, plus the milestone's own UAT, and those ids are cleared when it opens. This holds with YOLO on or off. The existing table is restated in terms of milestones, with the integration PR as the implicit final one.
  - **Recovery**: the milestone rows below.
- `skills/phase-planner/references/configuration.md`:
  - **Branch and merge**: `milestone.prepare` and `milestone.after_merge`, per repo, both prose the driver follows, both absent by default. `prepare` runs on the target branch before a milestone PR opens. `after_merge` runs after a person has merged it and the branch is back in line. Neither applies to the implicit final milestone unless set.
  - **YOLO** table: a row for opening a milestone PR (the driver, in both modes, for an explicit row; under YOLO only for the implicit one, as today) and for merging it (you, always).
  - **Where the plan lives**, and its **Feature-branch work** subsection: the advice to put the plan on the feature branch now carries its condition. A plan with milestone rows keeps the plan on the default branch, as the general rule, and may never use as `plan_branch` a branch a milestone row ships: that branch is deleted on merge and re-created by the driver, and the plan would go with it. A feature-branch plan without milestone rows may still live on the feature branch, as today. The worked example there gains the milestone variant.
- `skills/phase-planner/references/plan-template.md`: the two keys, commented out. No milestone row in the template.
- `skills/phase-driver/SKILL.md`:
  - §3 **Start phases**: a milestone PR counts as its repo's open PR, so no phase starts in a repo whose milestone row is `In Progress` or `In Review`. A milestone row is startable when every id in its `Depends` is `Merged` or `Skipped`, and it is started by the new section, not by the phase steps.
  - A new section **Milestones**, before §8. Claim the row (`In Progress`) first. Run `milestone.prepare` as commits pushed straight to the target branch; where that branch refuses direct pushes, put them through one small PR into it under the ordinary gate. Open the PR to the default branch, titled `Milestone M1: <scope>`, with what ships phase by phase with links, anything recorded as out of scope, the assembled UAT, and a line saying a person merges it. Write `In Review` and the `Link` at once. **Never merge it**, in any YOLO state, and `merge` and `merge now` do not apply to it. An explicit milestone row opens its PR with YOLO on or off: it is a checkpoint the plan's author put there, and YOLO only decides who merges phase PRs.
  - **Working a milestone PR**, a subsection of the same section. Between opening and the person's merge it is handled like any PR the driver opened, by the rules already in §5 and `gates.md`, with nothing restated: a failed check is read and fixed; a review is answered under **Answering a review**, with the same outcomes for in scope and right, minor, wrong, and out of scope, and the same treatment of a person's thread; `stuck.max_cycles`, `stuck.max_review_rounds`, the arbiter and the repo's own stop rules all apply. Four things are particular to it:
    - **Scope.** "In scope" means the union of the scopes of the phases the milestone ships, read from their Phase Details. Work none of them covers is out of scope and goes to Carried findings or an issue, as on a phase.
    - **Where a fix goes.** A commit pushed straight to the target branch, which is the PR's head, the same as the preparation. No fix PR into the feature branch, unless that branch refuses direct pushes.
    - **The head moving.** Every fix commit moves the milestone PR's head, so the gate result is discarded and re-evaluated against the new head, and gate 6 needs the reviewer at that head, exactly as on a phase PR. Rounds are counted the same way, as reviewed heads on this PR, starting from the head the PR opened at, so the preparation's commits are not rounds. `Review-baselines` and `Arbitrations` take the milestone's id, `M1:3`. The arbiter's brief names every shipped phase's details.
    - **When the gates pass.** Tell the person it is ready, with the per-gate summary, and set the row's `Note` to `ready to merge`, as for a phase with YOLO off. Then wait. A row that reaches a stop goes `Blocked` like any other.
  - The implicit final milestone is not worked this way. §8's rule for it stands: open it under YOLO, do not drive its checks, never merge it.
  - §7 **After a merge**, when the merged PR is a milestone row's: write `Merged`; **re-sync** the target branch; run `milestone.after_merge`; tell the user, including anything `after_merge` produced; start what it unblocks.
  - **Re-sync**, stated once and precisely. Skip it when no non-terminal row still targets the branch. Otherwise: if the branch is gone, re-create it at the default branch's head. If it exists and its head is an ancestor of the default branch, as after a merge commit, fast-forward it. If it exists, is not an ancestor, and its head is exactly the head the milestone PR was merged at, as after a squash or rebase merge, move it to the default branch's head. If it holds commits beyond the merged head, change nothing, report it, and start nothing in that repo until a person has sorted it out. A refused update is reported once with the one command that does it.
  - The branch-deletion guard under §5 gains its only exception, in the same paragraph: the driver never deletes or moves the plan branch or a `target_branch`, **except** this re-sync of a milestone row's own branch, after that row's PR is confirmed merged, and never when that branch is the plan branch.
  - §8 **Finishing the plan**: when the plan has no milestone rows, this section applies unchanged and its integration PR is the implicit final milestone. When it has any, the rows govern and no implicit PR is opened; finishing is `Driver: idle` and the summary.
- `skills/phase-driver/references/recovery.md`, new rows, found by head equal to the row's branch and base equal to the default branch:

  | Plan says | The forge says | Do this |
  |---|---|---|
  | `Pending`, dependencies merged | no such PR | Start it |
  | `Pending` or `In Progress` | an open PR from that branch to the default branch | Adopt it: write `In Review` and the `Link`. Do not prepare again if the preparation's commits are on the branch |
  | `In Progress`, stale | no PR, preparation partly on the branch | Finish the preparation from where the branch stands, then open the PR |
  | `In Review` | PR open | Watch it. Never merge |
  | `In Review` | PR merged | Write `Merged`, re-sync, `after_merge`, start what it unblocks |
  | `In Review` | PR closed, not merged | Ask why. Default to `Blocked` |
  | `Merged` | target branch missing or behind, rows still target it | Re-sync before starting anything in that repo |

- `skills/phase-driver/references/vocabulary.md`: `merge` and `merge now` on a milestone answer that it is the person's; `status` lists milestone rows with what each is waiting on.

**Depends on.** Phase 0a.

**Acceptance criteria.**
- [ ] `format.md` defines the milestone row by id and branch together, its statuses, its Phase Details shape, and where UAT goes
- [ ] `configuration.md` documents both keys with their default (absent) and says what absent means
- [ ] **Compatibility.** The PR body walks a plan with no milestone row through `SKILL.md` §3, §5, §7 and §8 and shows that no step reads differently from 0.9.3: the integration PR still opens only under YOLO, only where `target_branch` is not the default branch, and is never merged. The words of §8 that govern that path are unchanged apart from the sentence naming it the implicit final milestone
- [ ] `examples/two-phase-demo.md` and `examples/cross-platform.md` contain no row the new rule could read as a milestone
- [ ] The Milestones section says "never merge" without a YOLO condition, and the vocabulary reference agrees
- [ ] **Working a milestone PR** points at the existing review-handling, round-counting, arbiter and stop rules and restates none of them. `git diff` shows no change to the wording under **Answering a review**
- [ ] It defines in-scope as the union of the shipped phases' scopes, says fixes are direct commits to the target branch, says the gate is re-evaluated at each new head, and says rounds are counted from the head the PR opened at and keyed by the milestone id
- [ ] `format.md`'s descriptions of `Review-baselines` and `Arbitrations` allow a milestone id
- [ ] §8's rule for the implicit integration PR, that the driver does not drive its checks, is unchanged
- [ ] The re-sync rule covers the four cases in the scope, and the deletion guard names the re-sync as its single exception and excludes the plan branch
- [ ] The seven recovery rows exist, and each is reachable from a crash at a point the Milestones section's ordering allows
- [ ] `plan-template.md` still produces a plan with no milestone row
- [ ] The conventions under "How this plan is driven" hold

**UAT.** Use this branch's skills, loaded as "How this plan is driven" describes, on a scratch GitHub repo that deletes head branches on merge.
- [ ] Drive a plan of two phases and one milestone row depending on both, phases targeting a feature branch, plan on the default branch, YOLO off, with a one-line `milestone.prepare`. After you merge the second phase, the driver should make the preparation commit, open a PR from the feature branch to the default branch with a UAT script, and tell you it is yours to merge
- [ ] Say `merge now`. It should decline and say why
- [ ] Have the reviewer, or a second account, leave an inline thread on the milestone PR about code one of the two phases wrote. The driver should fix it with a commit on the feature branch, reply, resolve the thread, and re-evaluate the gates at the new head
- [ ] Leave a thread asking for something neither phase covered. The driver should decline it as out of scope, record it in Carried findings, and resolve the thread
- [ ] Break a check on the feature branch by hand. The driver should fix it. When everything passes it should tell you the PR is ready, and still not merge it
- [ ] Add a third phase that depends on the milestone and say `go` before merging the milestone PR. Nothing should start
- [ ] Merge the milestone PR with a squash. The driver should record it, re-create the feature branch from the default branch, and start the third phase from it
- [ ] Repeat with a merge commit and with the branch restored by hand before the driver wakes. It should fast-forward, and force nothing
- [ ] Kill the session after the preparation commit and before the PR opens; start a new one. It should open the PR and not prepare twice
- [ ] Turn YOLO on and run a plan with no milestone row whose phases target a feature branch. The integration PR should open at the end exactly as it does today
- [ ] Run the same plan with YOLO off. No PR to the default branch should open

**Risks.** This changes the two most sensitive paths in the driver, what happens after a merge and what happens at the end, and it is the first thing in the plan to reach every GitHub user. The compatibility criterion is the control, and the last two UAT steps are its test. Moving a branch is the only force the driver ever applies to a ref it did not create, so the re-sync has to refuse on any doubt. Sandboxed sessions that refuse ref deletion may refuse this too. Working a milestone PR means the driver commits fixes to a `target_branch` with no phase PR in between; what keeps that honest is that each fix moves the head, so the reviewer and the checks see it again before anyone is told the PR is ready, and a person still does the merge.

---

### Phase 0c — Milestones: planner, hygiene, documentation (sixoverground/claude-phases)

**Scope.** Teach the planner to propose milestones, and say in the project's documents what they are.

- `skills/phase-planner/SKILL.md`:
  - §4 **Design the phases**: propose a milestone row when phases target a feature branch and a later phase needs earlier work to be released, deployed or installed to do its job. Ask what that later phase needs, since it cannot be read from the repo. Choose the fewest milestones the real dependencies allow, and say what each one is needed by. A plan in which nothing needs an early release gets none, and ends as plans do today.
  - §3 refusals: a `plan_branch` that a milestone row ships; a milestone row in a repo whose `target_branch` is its default branch, where there is nothing to ship; a milestone whose `Depends` names a phase in another repo; a phase that depends on a milestone in a repo it does not use, without a stated reason. Warn when phases would merge after the plan's last milestone, since with explicit rows no implicit PR ships them.
  - §5: set `plan_branch` off the shipped branch, and write `milestone.prepare`.
- `skills/phase-planner/references/detection.md`, a new section **Release conventions → `milestone.prepare`**: read `CONTRIBUTING.md`, release scripts, a changelog, and any check that fails a PR into the default branch for a missing version bump. Write `prepare` from what the repo actually requires and quote the source. Where the repo has no release convention, leave the key out. Note whether such a check also fires on PRs into the feature branch, which forces a bump per phase and is worth fixing first, as phase 0a did here.
- `skills/phase-planner/references/hygiene.md`: head-branch auto-delete and a milestone's branch, which the driver re-creates; a protected feature branch, which turns the preparation into a PR; version checks scoped to the default branch.
- `README.md`, **Finishing**: a paragraph on milestones, and that the integration PR is the final, implicit one. `docs/design.md`: a section **Milestones generalise the integration PR**, with why a dependency replaced a pause, why preparation is committed directly, and why the plan may not live on a shipped branch.
- `examples/`: one short example plan with a milestone row.

**Depends on.** Phase 0b.

**Acceptance criteria.**
- [ ] The planner's rule for proposing a milestone names the condition and asks the one question it cannot answer from the repo
- [ ] The four refusals and the warning are in §3, each saying what to change
- [ ] `detection.md` has the release-conventions section, with an Observed and Set table like its neighbours
- [ ] Run against this repo, detection would produce a `milestone.prepare` equivalent to the one in this plan's front matter; the PR body shows the result
- [ ] A plan the planner writes with no need for early release contains no milestone row and no `milestone` key
- [ ] The example plan parses by the rules in `format.md`
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] With this branch's skills, ask the planner for a three-phase plan on a scratch repo with a feature branch, and say the third phase needs the first two deployed. It should propose one milestone between them, put the plan on the default branch, and say why
- [ ] Ask for the same plan and say nothing needs an early release. It should propose no milestone
- [ ] Ask it to put the plan on the feature branch with a milestone. It should refuse and explain
- [ ] On a repo with a version-bump check, read the `milestone.prepare` it writes. It should name the files the check reads

**Risks.** A planner that proposes milestones too readily turns every plan into a series of releases. The rule has to start from a named need, and the default has to be none.

---

### Phase 0d — Bootstrap release prep (sixoverground/claude-phases)

**Scope.** The one version change a phase makes in this plan, so that milestones can reach `main` and be installed. After this merges, the maintainer ships the feature branch to `main` by hand, as "The bootstrap, by hand, once" describes. Every later shipment is a milestone row.

- `.claude-plugin/plugin.json`: a minor version bump. Both skill descriptions end with the new `This copy is claude-phases <version>.`
- `CHANGELOG.md`: one `## [<version>]` section at the top, from the changelog sentences of 0a to 0c: milestone rows, the two keys, the integration PR as the implicit final milestone with nothing changed for existing plans, and the version check scoped to `main`.

**Depends on.** Phase 0c.

**Acceptance criteria.**
- [ ] `plugin.json` carries a version above the one on `main`, and `scripts/check-version-bump.sh origin/main` and `scripts/check-skill-versions.sh` both pass when run by hand on this branch
- [ ] `CHANGELOG.md` has exactly one new section, and `scripts/release.sh --dry-run` prints its notes
- [ ] The diff touches no file under `skills/` beyond the two description lines
- [ ] The driver's ready-to-merge message for this PR says the next step is the maintainer's and points at the bootstrap steps
- [ ] The conventions under "How this plan is driven" hold, apart from the first, which this phase is the exception to

**UAT.**
- [ ] Follow "The bootstrap, by hand, once" from step 1. At step 2, `Version bumped` should run on the PR to `main`, not skip, and pass. After the merge a GitHub release should appear with the CHANGELOG notes and both skill zips
- [ ] **The restart question.** At step 4, after the two update commands and before restarting, ask the still-running session: "does your phase-driver skill have a Milestones section?" Then invoke `phase-driver` in it and ask again. Record both answers in a comment on this phase's PR, with the Claude Code version. If either is no, a restart is required after every milestone, and the driver will say so each time
- [ ] In the fresh session, ask which version of claude-phases it has. It should name the new one
- [ ] Say `resume`. The driver should start phase 1 on the re-created feature branch
- [ ] In a cloud session on any existing GitHub plan, run one phase on the new release. It should behave as it did on 0.9.3

**Risks.** If `main` took another release meanwhile, the version chosen here may already be used and the PR to `main` will conflict in `plugin.json`, the descriptions and the CHANGELOG; redo the bump on what `main` says then. A forgotten `pause` starts phase 1 against a branch about to be re-cut; the bootstrap section says what to do then. This is the one handoff in the plan that depends on a person following steps in order, and it is the reason the feature is built first.

---

### Phase 1 — Review contract v1 (sixoverground/claude-phases)

**Scope.** Specify the contract between claude-phases and any reviewer, and teach gate 6 to read it. This is the foundation both tracks build on. The entry is forge-neutral from the first line: the rule lives in the core gate, and on GitHub it is read from PR comments, so any self-hosted reviewer that meets the contract works there, and a review workflow that posts the marker no longer needs `proof: completed`.

- New `docs/review-contract.md`, the normative spec for people building a reviewer, written without reference to any one forge. Version 1 says: (1) findings are inline, resolvable threads on the diff; (2) after every completed review, clean ones included, the reviewer posts a top-level note containing `<!-- phases:review v=1 reviewer=<name> sha=<full sha> -->` on a line of its own; (3) the marker is written by the tool's code after the review process has exited successfully, with the sha taken from the environment; (4) text produced by a model is scrubbed of the string `<!-- phases:review` before it is posted; (5) `<name>` matches `[a-z0-9-]+` and `sha` is the full 40-character head sha that was reviewed. It also says what the contract does not promise: nothing about approval, and nothing about whether findings were addressed.
- `skills/phase-planner/references/configuration.md`, section **Review**: a third entry type, `{ marker: "<reviewer>" }`, with an optional `logins` list that pins who may author the marker note. Add it to the "Each entry is satisfied when any of these is true" list and to the **Reviewer setups** table as "any reviewer that emits the contract". State that `proof` and `rereview` do not apply to it.
- `skills/phase-driver/references/gates.md`, **Gate 6**: a new satisfier, "a top-level comment on the PR containing a v=1 marker whose `reviewer` equals the entry's `marker` and whose `sha` equals `head.sha`, authored by one of the entry's `logins` when it lists any". A new subsection, **The review marker**, covering: an unknown `v` is not proof and blocks, an abbreviated sha is not proof, a marker inside an inline thread comment is not proof, and the driver never writes a marker itself. Add the gate report line `6 reviewer     PASS (codex marker @ a1b2c3d)`.
- `skills/phase-driver/SKILL.md`, **Stop when the rounds stop converging**, the paragraph "Count reviewed heads, not reviews": a marker counts for the sha it names, which needs none of the bounding a reaction does.
- `skills/phase-planner/SKILL.md` §3: refuse a `marker` entry when no comment on any recent PR carries that reviewer's marker and nothing in the repo could post one. Warn when a `marker` entry has no `logins` on a repo where outsiders can comment.

**Depends on.** Phase 0d, and the bootstrap that follows it.

**Acceptance criteria.**
- [ ] `docs/review-contract.md` exists, states `v=1`, the exact marker grammar, the five rules above, and one worked example of a clean review and of a review with findings
- [ ] `configuration.md` documents the `marker` entry, its optional `logins`, and that `proof` and `rereview` are ignored for it
- [ ] `gates.md` gate 6 lists the marker satisfier, and **The review marker** covers the four non-proofs named in the scope
- [ ] The rule is stated in terms any forge has, a top-level comment on the change request and its author, and names GitHub only where it says which API returns those comments
- [ ] Nothing in this phase adds or changes a rule about how the driver answers a review
- [ ] The reviewed-heads count in `SKILL.md` names the marker
- [ ] No existing gate 6 satisfier is reworded: the diff to `gates.md` under gate 6 is additions only
- [ ] The planner refusal and the warning are in `phase-planner/SKILL.md` §3
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] Read `docs/review-contract.md` as someone who has never seen claude-phases. You should be able to say what your tool must post, and when, without opening any other file
- [ ] On a scratch GitHub repo with a plan whose `review.required` is `[{ marker: "test" }]`, open a phase PR and ask the driver `why`. Gate 6 should report that no marker for the head exists
- [ ] Comment `<!-- phases:review v=1 reviewer=test sha=<the PR's full head sha> -->` on that PR and say `check`. Gate 6 should pass and name the marker
- [ ] Push another commit and say `check`. Gate 6 should block again, because the marker names the old sha
- [ ] Comment a marker with the first seven characters of the sha. Gate 6 should still block

**Risks.** Anyone who can comment can type a marker, so on a public repo an entry without `logins` is forgeable by a passer-by. The spec has to say that plainly, and the planner has to warn. The format is hard to change once a tool ships against it, which is why it carries `v=1` from the start.

---

### Phase 2a — Forge-neutral driver core (sixoverground/claude-phases)

**Scope.** Move, do not rewrite. Every sentence in `skills/phase-driver/SKILL.md` that is true only of GitHub moves to a new `skills/phase-driver/references/forge-github.md`, and the core keeps the rule with a pointer. **This phase changes no behaviour for a GitHub user.**

What moves, by section of `SKILL.md` as it stands at 0.9.3:

- §2 Reconcile, step 3: `list_pull_requests` filtered by head branch and `pull_request_read{get}` become "find the change request for that row's branch, in any state".
- §3 step 8 and all of **Who opens the PR decides whether it gets reviewed**: the MCP tools against `gh pr create`, `get_me`, the `user.login` read-back. The core keeps one sentence: after opening, do what the forge reference says about opener identity.
- §4 Watch: "Subscribe to PR activity", and the two paragraphs on which events arrive without a webhook. The core keeps: arm whatever wakes you, schedule the check-in, end the turn.
- §5: the merge call, **Deleting the branch is yours because the API will not** and the two paragraphs after it, and the `@codex review` example under "Resolving a thread does not clear gate 4".
- §7 step 1, Unsubscribe.
- **Milestones** and §8: opening a milestone PR and the integration PR, finding a milestone PR by head and base, the calls that re-create or move a branch in the re-sync, and **The fallback** (a GitHub issue titled `UAT: <project>`). The re-sync's rule about when each is allowed stays in the core.
- **Writing to the plan**: `create_or_update_file` and the blob `sha`. The core keeps the rules about the lock: read the write token at the start of every transition, and on a conflict re-run the Driver-ID decision before retrying. Golden rule 3 names "the write token the forge reference defines".
- The §5 table that sends a standalone defect to "A GitHub issue", and the arbiter's `issue` verdict, say "an issue on the forge".

What is added, and nothing else: a short section after the golden rules, **The forge**, saying that the forge is GitHub unless the repo's config says otherwise and that `references/forge-github.md` is read at Reconcile and again after any compaction. The core says "change request" where it means the object and keeps "PR" where it names the plan format (`## PR Sequence`, the `PR` column, `Phase N:` titles). The frontmatter description is not touched.

`SKILL.md` has no `## 6` heading: the text that evaluates the gates and merges sits at the end of §5 and the numbering jumps from 5 to 7. Leave that alone in this phase. See Open questions.

**Depends on.** Phase 1, so the marker text it added moves with everything else.

**Acceptance criteria.**
- [ ] `skills/phase-driver/references/forge-github.md` exists, with one section per operation: find, open, opener identity, watch, write the plan, merge, delete the branch, milestone and integration change requests, re-sync a branch, issue fallback
- [ ] The PR body contains a move table: every sentence or block removed from `SKILL.md`, and the heading in `forge-github.md` where it now lives. Nothing removed is absent from the table
- [ ] `git diff main -- skills/phase-driver/SKILL.md` contains no added rule other than **The forge** section and the pointers that replace moved text
- [ ] No GitHub API name, MCP tool name or `gh` command remains in `SKILL.md` outside **The forge**
- [ ] `gates.md`, `recovery.md` and `vocabulary.md` are unchanged in this phase
- [ ] `scripts/check-skills.sh` passes with the new reference linked from `SKILL.md`
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] On a scratch GitHub repo with CI, drive `examples/two-phase-demo.md` with YOLO off using this branch's skills. A PR should open under your own login, the driver should report the gates, and after you merge it the second phase should start without being asked
- [ ] Kill the session while the second phase is `In Progress`, start a new one, and say `status`. It should recover to the right state from the plan and GitHub alone
- [ ] Turn YOLO on for the last phase. The driver should merge it and delete the branch
- [ ] Ask the driver to name the file it read the PR-opening rule from. It should name `references/forge-github.md`

**Risks.** The skills are prose, so a move that drops half a sentence is a behaviour change nobody sees in review. The move table is the control. The reference is read lazily and can be lost to compaction, so a driver could act on the neutral core alone and, for instance, open a PR with `gh pr create`; **The forge** section and golden rule 9 are what bring it back. This plan is itself driven by the skill being edited. Until `M1` that does not matter, since the driver runs the bootstrap release and `main` does not have the refactor. From `M1` on, the installed driver is this refactor, so a mistake in it breaks the driver of this plan; the way back is to install the previous release and fix forward on the feature branch.

---

### Phase 2b — Forge-neutral gates and recovery (sixoverground/claude-phases)

**Scope.** The same move for the driver's references. Still no behaviour change.

- `skills/phase-driver/references/gates.md` keeps the six gates as questions: not a draft, no blocking label, checks green, no changes requested, threads resolved, reviewer saw this commit. It keeps what is true on any forge: which checks count and in what precedence, that zero checks blocks, one re-run per head, why gate 6 asks only whether the reviewer looked, why `proof` is configurable, the marker rules from phase 1, the report shape. What moves to `forge-github.md`, under a heading per gate: check runs and commit statuses and the exact passing and blocking conclusions, the `ci.logs` values `actions` and `check-output`, review states and `CHANGES_REQUESTED`, `isResolved`, `commit_id == head.sha`, all of **The decline reaction** including the `gh api .../reactions` command and the attribution trap, all of **`rereview: optional`**, which API returns the top-level comments a marker is looked for in, and the sentence under **Merging** that the merge API takes no expected sha.
- `skills/phase-driver/references/recovery.md`: "GitHub says" becomes "The forge says", and "GitHub is the truth" becomes "The forge is the truth". "Subscribe" and "Re-subscribe" become "watch". The table's logic is untouched.
- `skills/phase-driver/references/vocabulary.md`: "a webhook was missed" becomes "a wake was missed", and "verified against GitHub" becomes "verified against the forge".
- `skills/phase-driver/SKILL.md`: only link targets that moved.

**Depends on.** Phase 2a.

**Acceptance criteria.**
- [ ] `gates.md` names no GitHub API field, endpoint or tool; each gate points at its heading in `forge-github.md`
- [ ] `forge-github.md` has a section per gate, and the decline reaction and `rereview: optional` text is byte-identical to what left `gates.md`, apart from heading levels
- [ ] The PR body carries the move table for `gates.md`, as in phase 2a
- [ ] The marker rule, with its optional `logins`, is still stated in `gates.md` itself; only the name of the API that lists comments moved
- [ ] The recovery table has the same number of rows and the same "Do this" cells as before, apart from the word substitutions listed in the scope
- [ ] Every anchor that `SKILL.md` links into `gates.md` still resolves
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] Repeat the scratch-repo run from phase 2a with a failing check on the first PR. The driver should read the Actions log, fix it and push
- [ ] On a PR reviewed by Codex on smart detect, push a trivial commit and ask `why` before and after the grace period. Gate 6 should block first and then pass as a decline, with the same report line as before this phase
- [ ] On a PR Codex only gave a thumbs up, ask `why`. Gate 6 should pass and name the reaction
- [ ] Ask for `status` on this plan itself. The gate report shape should be unchanged

**Risks.** Gate 6 is the most carefully worded text in the project, and each sentence in it exists because of a failure someone observed. Moving it byte for byte is the point; improving it in passing is how a rule gets lost.

---

### Phase 3 — Local sessions: the watcher (sixoverground/claude-phases)

**Scope.** Let a session with no webhooks wait correctly, and stop treating an unreachable forge as a blocked phase. GitHub only in this phase; the GitLab watcher command arrives in 4b.

- New `skills/phase-driver/references/watching.md`. It holds the rule for choosing: if the session can subscribe to change-request activity, subscribe exactly as before; if it cannot, arm the watcher. And it holds the watcher itself, as a command template the driver fills in and runs under the Monitor tool: a polling loop, 60 seconds between polls, that snapshots each open phase change request and prints **one line only when something changed**. What counts as a change: the head sha, the state of any check, a new comment or thread from someone other than the driver, merged, closed. The GitHub form reads through `gh api`. The template is given verbatim, to be used as written with only the bracketed values replaced, because a loop improvised on every wake is where a silent failure would hide.
- Every line the watcher prints is a complete wake message for a session that has nothing: invoke `phase-driver`, the plan's path, reconcile, then what changed. The fallback check-in, by wall clock so it survives the Mac sleeping, prints the same message with no event, 45 to 60 minutes out, or 10 to 15 when the answer being waited on has no event of its own.
- Monitor expires after its timeout, 30 minutes at most. **An expiry with no events is not a wake**: re-arm and end the turn, without invoking a reconcile, without writing a heartbeat, and without posting anything. The reference says so, and says to fall back to a background shell command that exits on the first change where Monitor is unavailable.
- The watcher holds nothing the plan needs. A session that dies loses it, and the next reconcile re-arms it. `recovery.md`: the `In Review` and PR open row says "re-arm the watch".
- **Forge unreachable is not `Blocked`.** `SKILL.md` §3 step 1 separates two things it currently treats as one: access denied (the forge answered 401, 403 or 404) still marks the row `Blocked`; unreachable (DNS failure, timeout, connection refused, a gateway error) does not. New golden rule 10 and a new `recovery.md` section, **The forge is unreachable**: do not mark anything `Blocked`, do not count the wake toward `stuck.max_cycles`, tell the user once, keep the watcher polling with a backoff capped at five minutes, and reconcile when it answers. The watcher prints one line when the forge stops answering and one when it returns. A status write that could not be made means the action it describes has not started.
- `SKILL.md` §4 Watch and §7 step 1 point at `watching.md`. The frontmatter description's last sentence becomes "Also use when a PR webhook, a watcher event or a check-in wakes the session and a plan file is present."
- `skills/phase-planner/references/plan-template.md` and `format.md`: the **For the driver** text is not changed. It says "a check-in or a webhook", and a watcher line carries its own instruction to invoke the skill. See Open questions.

**Depends on.** Phase 2b.

**Acceptance criteria.**
- [ ] `watching.md` contains the choice rule, the verbatim watcher template for GitHub, the wake message format, the fallback timing, and the Monitor expiry rule
- [ ] The template prints nothing on a poll where nothing changed, tolerates a failed request without exiting, and uses only `gh`, `jq` and POSIX shell that runs under macOS's bash 3.2
- [ ] Run for real against an open PR on a scratch repo: pushing a commit, a check finishing, a comment from another account and a merge each produce exactly one line; ten quiet minutes produce none. The PR body records the run
- [ ] With the network off, the watcher prints one unreachable line, keeps running, and prints one line when the network returns
- [ ] `SKILL.md` §3 step 1 distinguishes denied from unreachable; golden rule 10 and the `recovery.md` section exist
- [ ] A session that can subscribe is told to subscribe: the cloud path in `forge-github.md` is unchanged by this diff
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] In a terminal on the Mac, start `claude` in a scratch GitHub repo with a two-phase plan and say "run the next phase". After the PR opens the driver should say it has armed a watcher and end its turn
- [ ] Push an empty commit to the phase branch from another terminal. Within about two minutes the session should wake by itself and re-evaluate the gates
- [ ] Leave it idle for 35 minutes. It should re-arm the watcher without posting anything on the PR and without writing to the plan
- [ ] Turn Wi-Fi off for five minutes, then on. You should see one message that the forge is unreachable, no row should go to `Blocked`, and the driver should carry on by itself afterwards
- [ ] Close the laptop lid for ten minutes and reopen it. The session should still be waiting, and a comment posted while it slept should wake it shortly after
- [ ] In a cloud session on the same repo, start a phase. It should subscribe to the PR as it always has and mention no watcher

**Risks.** Monitor's limits are read from the tool's own description and can change between Claude Code releases; the acceptance run is what confirms them. Every wake invokes the skill and reconciles, so a watcher that prints too readily costs real tokens overnight; "one line only when something changed" is a cost control as well as a correctness rule. If the driver and a reviewer post under the same identity, the watcher cannot tell their comments apart and the driver wakes itself once per reply, which is noisy and harmless.

---

### Milestone M1 — Local running and the forge-neutral driver (sixoverground/claude-phases)

**Ships.** Phases 1, 2a, 2b and 3: the review contract and the `marker` entry, the driver split into a forge-neutral core and `forge-github.md` with nothing changed for GitHub, the watcher for sessions without webhooks, and an unreachable forge as a wait.

**Needed by.** Phase 9, which must be driven from a session on the Mac, and so needs the installed driver to have the watcher. Phase 4 depends on it too, so that GitLab work starts from a branch level with `main`.

**UAT.** What only makes sense once the four are together, on the milestone PR before you merge it:
- [ ] Load the feature branch's skills and drive `examples/two-phase-demo.md` on a scratch GitHub repo from a local session, YOLO off. The PR should open under your login, the watcher should be armed, a push from another terminal should wake the session, and after you merge, the second phase should start by itself
- [ ] On the same run, add `review.required: [{ marker: "test" }]`, comment the marker with the head sha, and ask `why`. Gate 6 should pass on the marker, reading it through `forge-github.md`
- [ ] Drive one phase of the same plan from a cloud session. It should subscribe to the PR as it always has
- [ ] Read the milestone PR's diff to `skills/phase-driver/` as one change. Nothing GitHub-specific should have been lost between the core and `forge-github.md`

After merging:
- [ ] The driver should record `M1` as `Merged`, re-create `feature/local-gitlab` from `main`, and report the installed version or say the update has to be run on the Mac
- [ ] On the Mac, with the plugin updated, start `claude` and say `resume`. Phases 4 and 9 should start, each PR with a watcher

**Risks.** This release puts the refactored driver in front of every GitHub user, so the UAT of 2a, 2b and 3 is the real gate, and this PR should not be merged with any of it outstanding. It is also the first milestone the driver has ever driven outside a scratch repo. The driver moves from cloud to the Mac here, which is a person's step whatever the restart question turned out to be.

---

### Phase 4 — Forge configuration (sixoverground/claude-phases)

**Scope.** The keys a non-GitHub repo needs, and the driver's rule for picking a forge.

- `skills/phase-planner/references/configuration.md`:
  - Opening paragraph: the assumptions become "a forge, GitHub by default, and Claude Code".
  - New per-repo section **Forge**: `forge` (`github` or `gitlab`, default `github`) and `host` (default `github.com` or `gitlab.com`; set it for a self-managed instance, for example `gitlab.example.com`). The home repo's `forge` and `host` decide where the plan is read and written.
  - **Top level**: `home_repo` and the keys of `repos` are the forge's project path, `owner/name` on GitHub and `group/project` on GitLab, subgroups included.
  - **Branch and merge**: `integration_pr`, default `true`. `false` means the driver never opens the implicit final milestone, the change request from `target_branch` to the default branch when a plan without milestone rows completes. It has no effect on explicit milestone rows, which a plan author wrote on purpose.
  - **CI**: a `ci.logs` value `gitlab-jobs`, the full job trace, and `auto` resolves to it on GitLab. `ci.required` names jobs on GitLab. A sentence that `ci.dispatch` values other than `push` and `none` are GitHub-only for now.
  - **YOLO** and **Where the plan lives**: say what `integration_pr: false` does to the cumulative UAT script.
- `skills/phase-planner/references/format.md`: the first sentence stops saying "committed to a GitHub repo"; the `Repo` and `Link` rows of the table accept `group/project` and `group/project!42`; **When UAT reaches a human** gains the case where no integration change request will exist by configuration.
- `skills/phase-planner/references/plan-template.md`: a commented `# forge: github` and `# host:` under `defaults`.
- `skills/phase-driver/SKILL.md`: **The forge** section resolves `forge` per repo and reads `references/forge-<forge>.md`. A configured forge with no such file in this copy stops and says so, which is also what a plan written for a newer release does on an older install. §8 honours `integration_pr: false`: no implicit final milestone, and the cumulative UAT goes to the fallback. **The fallback** becomes: an issue where the forge reference says issues are available, and otherwise the script is posted on the last merged change request, `UAT-pending` stays as it is, and the completion summary says so.
- `skills/phase-driver/references/recovery.md`: the last row, all rows terminal, honours `integration_pr`.
- New `profiles/forge-gitlab.yml`, and a **Forge** table in `profiles/README.md`.

**Depends on.** `M1`. No capability check is needed at the top of this phase: the dependency holds it until `M1` is merged and the branch is level with `main`, and writing it needs nothing a milestone-aware driver lacks.

**Acceptance criteria.**
- [ ] Every new key has a default, an off switch or a statement that it has none, and a profile that shows it, as CONTRIBUTING requires
- [ ] A plan with no `forge` key anywhere resolves to GitHub, and nothing in the driver's GitHub path reads the new keys
- [ ] `format.md`, `configuration.md` and `plan-template.md` agree on the repo id and `Link` forms
- [ ] `SKILL.md` §8, **The fallback** and the last recovery row agree with each other on what happens when `integration_pr` is `false`
- [ ] A plan with `forge: gitlab` makes this copy of the driver stop at Reconcile and say that it has no reference for that forge
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] Run a two-phase plan on a scratch GitHub repo whose phases target a feature branch, YOLO on, with `integration_pr: false`. When the last phase merges, no PR to `main` should appear, a `UAT: <project>` issue should, and the driver should go idle
- [ ] Run the same plan without the key. The integration PR should open as it does today
- [ ] Add `forge: gitlab` to a scratch plan and say `status`. The driver should stop and say why, and write nothing

**Risks.** Between this phase and 5b the branch documents a forge the driver cannot yet drive. Nothing reaches `main` in that state, since `M2` ships all of it together, and the stop in the driver covers anyone running the branch. `integration_pr: false` takes away the one place the cumulative UAT had leverage, and the fallback is weaker on a project with issues turned off. That trade is the client's, and the doc has to state it.

---

### Phase 5a — GitLab driver: plan, merge requests, merging (sixoverground/claude-phases)

**Scope.** New `skills/phase-driver/references/forge-gitlab.md`, with the same headings as `forge-github.md`, covering everything except the gates. Every operation is a `glab` command or a `glab api` call, against the repo's `host`.

- **Setup the session needs.** `glab` authenticated for `host` with a token that has `api` scope; how to check it (`glab auth status --hostname <host>`); the project path URL-encoded in API calls.
- **Reading and writing the plan.** The Repository Files API on the plan branch. The write token is `last_commit_id` from the read, passed back on the write, and a mismatch is the stale-write conflict the core's lock rules handle. The commit message still ends `[skip ci]`, which GitLab honours for branch pipelines.
- **`plan_writes: plan-pr` on GitLab.** A one-file merge request against the plan branch, merged at once by the driver where the token may merge, and reported as a hard stop where it may not.
- **Finding a merge request.** By `source_branch`, with `state=all`, so a merged or closed one is found too.
- **Opening one.** `glab mr create` with the source and target branch, the title and body the core specifies, `--remove-source-branch` unless `merge.delete_branch: false`, and squash set from `merge.method`. Record the `Link` as `group/project!<iid>`.
- **Opener identity.** Does not apply. Reviewers here are triggered by the pipeline, whoever opened the merge request. Skip the read-back.
- **Merging.** `glab mr merge <iid> --sha <head>` with the method from `merge.method` and auto-merge explicitly off. The head check is atomic on the server: a moved head refuses the merge, which closes the window GitHub leaves open. The core's "re-read the head as your last read" still applies, and the sha it read is the one passed.
- **Deleting the branch.** The server does it at merge when the merge request was created with the flag, for a person's merge as well as the driver's. The driver deletes nothing itself.
- **Milestone merge requests.** Finding one by source and target branch, opening it without `--remove-source-branch`, and the re-sync: re-creating or moving the branch through the branches API, under the core's rule for when each is allowed.
- **The integration merge request and the issue fallback.** Open it unless `integration_pr: false`. An issue only where the project has issues enabled; otherwise the core's no-issues fallback.
- **Unreachable against denied.** Which `glab` failures are which, for golden rule 10. A self-managed host behind a VPN commonly fails as a DNS error or a timeout.
- **Working copy.** A local driver works in a clone of its own, never the directory a person or the runner is using.

**Depends on.** Phase 4.

**Acceptance criteria.**
- [ ] `forge-gitlab.md` has every heading `forge-github.md` has, with either a mapping or an explicit "does not apply, because"
- [ ] Each operation gives the exact command or endpoint, its required parameters, and the fields of the response the driver reads
- [ ] Each endpoint and flag is checked against the current GitLab API and `glab` documentation, linked in the PR body
- [ ] Where the session has `glab` access to the scratch project from Prerequisites, each command is run once and its real output shape is noted in the PR body. Where it does not, the PR body says so and the UAT below covers it
- [ ] The merge section passes `--sha` and turns auto-merge off, and says what the refusal looks like when the head has moved
- [ ] The driver's **The forge** section no longer stops on `forge: gitlab`
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] On the Mac, with `glab` logged in to the gitlab.com scratch project, read a file through the Files API command from the reference and write it back with the `last_commit_id` it returned. The write should succeed
- [ ] Change the file in the web UI, then repeat the write with the old `last_commit_id`. It should be refused
- [ ] Create a branch with one commit, open a merge request with the reference's command, then find it with the `source_branch` query. Merge it in the UI and run the query again: it should still be found, as merged, and the source branch should be gone
- [ ] Open another, push a second commit, and run the merge command with the first commit's sha. The merge should be refused
- [ ] Disconnect from the network and run any one command. Note the error, and check that the reference classifies it as unreachable

**Risks.** This is prose about an API that no session has exercised end to end until phase 13. A Developer-role token may be unable to push to or merge into a protected branch, and on a long-lived branch that is also the plan branch that stops plan writes as well as merges; the reference has to say what the driver does then. `glab` flags differ between versions, so the reference names the version it was checked against. Self-managed instances lag gitlab.com, and a field that exists there may not exist on an older server.

---

### Phase 5b — GitLab driver: gates, logs, discussions (sixoverground/claude-phases)

**Scope.** The second half of `forge-gitlab.md`: one section per gate, and the things answering a review needs.

- **Gate 1.** The merge request's `draft`.
- **Gate 2.** Its `labels` against `blocking_labels`.
- **Gate 3.** The jobs of the pipeline for the head sha, plus external commit statuses on that sha. `ci.required` names jobs. A table mapping job status to the core's verdicts: `success` and `skipped` pass; `failed` with `allow_failure: true` passes, as GitHub's `neutral` does; `failed`, `canceled` and a blocking `manual` job block; `created`, `pending`, `running` and the other in-flight states wait. A pipeline whose sha is not the head sha is not this head's pipeline, which matters for merged-results pipelines. No pipeline at all is the zero-checks case and blocks unless `ci.allow_none: true`.
- **`ci.logs: gitlab-jobs`.** The failed job's full trace through `glab ci trace` or the jobs API, read from the end. One retry of a failed job per head for a suspected flake, disclosed on the merge request.
- **Gate 4.** `detailed_merge_status` reporting requested changes, on tiers and versions that have it. Where the instance does not report it, the gate is off and the report line says so.
- **Gate 5.** Every resolvable discussion on the merge request is resolved. On GitLab a general thread is resolvable too, so a finding posted as a thread without a diff position still gates. Replying and resolving through the discussions API.
- **Gate 6.** The `marker` entry, read from the merge request's notes: v=1, the reviewer name, `sha` equal to the head sha, and the author in `logins` where given. `logins` and `check` entries, reactions, and `rereview: optional` do not apply on GitLab, and a plan that configures them there is told so.
- **Whose thread it is.** The core resolves a bot's thread on disagreement and leaves a person's open. On GitLab a bot is the author named in a marker entry's `logins`, or a user the API marks as a bot.
- **Asking a reviewer to look again.** Create a merge request pipeline, or retry the review job.
- **The watcher command for GitLab**, added to `watching.md`: the same template through `glab api`, watching the head sha, pipeline and job states, new notes and discussions, merged and closed. It lives in `watching.md` beside the GitHub one so the choice rule stays in one place.
- **The reviewed-heads count** for `stuck.max_review_rounds`: the distinct shas named by a configured reviewer's markers.

**Depends on.** Phase 5a.

**Acceptance criteria.**
- [ ] `forge-gitlab.md` has a section per gate, and each names the endpoint, the fields read, and the off switch from the core's table
- [ ] The job-status table covers every status the GitLab jobs API documents, and each maps to pass, block or wait
- [ ] Gate 4 says how the driver tells "no changes requested" from "this instance cannot tell me", and the gate report has a line for the second
- [ ] The GitLab watcher template is in `watching.md`, and meets the same three criteria as the GitHub one in phase 3: silent when nothing changed, survives a failed request, runs under bash 3.2
- [ ] Each endpoint is checked against GitLab's API documentation, linked in the PR body, and run against the scratch project where the session can
- [ ] `forge-gitlab.md` says plainly which `review.required` entry types work on GitLab: `marker` only
- [ ] The section on whose thread it is, and every other section here, maps GitLab objects onto the core's existing review-handling rules and states no new one: the PR body lists each core rule a section relies on
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] On the gitlab.com scratch project with the runner online, open a merge request whose pipeline has one passing and one failing job. Run the gate 3 commands from the reference by hand: you should get both jobs with their statuses, and the trace command should print the failing job's real error
- [ ] Mark the failing job `allow_failure: true` and push. The same commands should show a status the table maps to pass
- [ ] Start a thread on a diff line and a general thread in the web UI. The gate 5 query should list both as unresolved. Resolve one with the reference's command and check the UI agrees
- [ ] Post a note containing a v=1 marker with the head sha, using the reviewer token. The gate 6 query should find it. Push a commit: it should no longer match
- [ ] Run the GitLab watcher template against that merge request for ten minutes while you push, comment and retry a job. One line per change, and silence otherwise

**Risks.** Gate 3 is where GitLab differs most from GitHub: manual jobs, `allow_failure`, merged-results pipelines whose sha is not the branch head, and child pipelines. A wrong row in the status table is either a false pass or a permanent wait. Requested changes is a paid-tier feature, and the client's tier is unknown. A review job counts in gate 3 like any other job, so a reviewer that cannot run goes red, which is the behaviour the project prefers.

---

### Phase 6 — Planner on GitLab (sixoverground/claude-phases)

**Scope.** Detection and refusals for a GitLab project, as additions. The GitHub procedure is not edited.

- New `skills/phase-planner/references/detection-gitlab.md`, with the same headings as `detection.md`. What it reads: the project and its default branch; `.gitlab-ci.yml` on the target branch, with its includes, for job names, `rules`, `only` and `except`, and `tags`; recent merge request pipelines into `target_branch` and the jobs that actually ran in them, which is the ground truth for the same reason check runs are on GitHub; whether an online runner serves each tag a required job needs; whether the plan branch accepts a push from this token, and whether `target_branch` accepts its merge; whether issues are enabled; marker notes on recent merge requests; `AGENTS.md`, `CLAUDE.md` and the contributing guide for the repo's own review rules.
- Where the runners endpoint refuses a Developer token, infer the runner from the one recorded on recent jobs with that tag, and say in the findings that it is inferred.
- `skills/phase-planner/SKILL.md`: §1 asks which forge and host when a repo is not on github.com, inferring it from the checkout's remote where it can. §2 reads `detection-gitlab.md` for a GitLab repo and shows the same findings table, with job names where check names were. §3 gains four refusals for GitLab: a name in `ci.required` that is no job in the CI file; a required job whose `rules` cannot fire for a merge request into `target_branch`; a required job whose tags no online runner serves; a `marker` reviewer configured with no job that could post it and no marker on any recent merge request. It also warns when a token cannot merge into `target_branch`, because YOLO then cannot merge.
- `skills/phase-planner/references/detection.md`: one pointer at the top to `detection-gitlab.md`.
- `skills/phase-planner/references/hygiene.md`, a GitLab subsection: the review job and `build-test` must run on merge request pipelines; `[skip ci]` is honoured, and a `rules: changes` exclusion for `docs/plans/**` is belt and braces; "Delete source branch" as a project default; a protected plan branch and the role that may push to it; the runner and the driver sharing one Mac.
- New `profiles/ci-gitlab-runner-macos.yml`, and its row in `profiles/README.md`.
- §5 of the planner: propose `integration_pr: false` when the person says the merge to the default branch is someone else's decision.

**Depends on.** Phase 5b.

**Acceptance criteria.**
- [ ] `detection-gitlab.md` gives, for each fact, the `glab` command or endpoint that reads it and the config it implies, in the same Observed and Set tables `detection.md` uses
- [ ] Each of the four refusals names what it checked and what to change, as the base-branch trap does today
- [ ] The Developer-token fallback for runners is written down, with the wording the planner uses when a finding is inferred
- [ ] `detection.md` gains only the pointer; `git diff` shows no other change to it
- [ ] `profiles/ci-gitlab-runner-macos.yml` is valid YAML and uses only keys `configuration.md` documents
- [ ] The planner still asks its three questions in one `AskUserQuestion` call
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] On the Mac, in a clone of the gitlab.com scratch project, say "plan a project" and describe a two-phase toy change. The findings table should show the default branch, the jobs from `.gitlab-ci.yml`, the runner, and whether issues are enabled, each as observed or as inferred
- [ ] Ask it to require a job name that does not exist. It should refuse and name the CI file
- [ ] Give the review job a rule that only fires for the default branch, then plan against a feature branch. It should refuse and name the rule
- [ ] Pause the runner and plan again. It should refuse on the tag, or say it could only infer the runner
- [ ] Plan a GitHub repo afterwards. Detection should read exactly as it did before this phase

**Risks.** `rules` in a CI file can depend on variables and includes the planner cannot evaluate; where it cannot tell, it has to say so and ask. A project with no merge request history gives it nothing to observe, and the degraded path is one question. Permissions on a self-managed instance differ by role in ways the documentation states imprecisely, so the trial in phase 13 is the first real check.

---

### Phase 7 — Running locally: guide, and iOS verified on the Mac (sixoverground/claude-phases)

**Scope.** The documentation for a local run, and the one config rule that is wrong for it.

- New `docs/running-locally.md`: when to run locally (a forge a cloud session cannot reach, a toolchain only your machine has); what is different (a watcher where webhooks were, the session is a process on your machine); keeping the session alive (a terminal multiplexer, `caffeinate`, the Mac's sleep settings, what happens across a VPN drop); steering it from a phone with `claude --remote-control`; resuming after a crash with `claude --continue`, and why even that is optional since the plan is the state; a clone for the driver separate from your own and from the runner's; tokens and which identity posts what; what a night of waiting costs.
- `README.md`: the diagram caption and **How it works** step 3 mention the watcher; a short **Running locally** section links the guide; **Where tests run** says iOS is CI-only in a cloud container and `local` on a Mac; **Installing** notes the plugin route for a local session; **Related** sharpens the difference from claude-project-manager: both can now run on your Mac, cpm keeps the loop outside the model in a launchd job that fires a routine per phase, and claude-phases keeps it inside one session you can talk to, with the watcher as that session's own tool.
- `skills/phase-planner/references/configuration.md`, **Verification**, "What's realistic": iOS is `ci` in a cloud session and `local` when the session runs on macOS with Xcode.
- `skills/phase-planner/references/detection.md` and `detection-gitlab.md`, **Toolchain**: an Xcode project is `ci` unless the planning session is on macOS with `xcodebuild` present, in which case `local`, with the advice to make the local step a quick build for the simulator and leave the test suite to CI.
- `skills/phase-planner/references/hygiene.md`, **Makes local verification possible**: when the driver and a CI runner share a Mac, give the driver its own `-derivedDataPath`, build for a generic simulator destination or a simulator the runner does not use, and keep the runner at one concurrent job. A `SessionStart` hook is a cloud concern.
- `docs/design.md`, **Where tests run**: a paragraph on the same.
- `profiles/ci-xcode-cloud.yml`: its last comment says "in a cloud session".

**Depends on.** Phase 6.

**Acceptance criteria.**
- [ ] `docs/running-locally.md` exists and covers each item in the scope, and every command in it was run on a Mac or is marked unverified
- [ ] The README **Related** paragraph states the difference from claude-project-manager in terms of where the loop lives
- [ ] `configuration.md`, both detection references, `hygiene.md` and `design.md` agree on when iOS is `local`
- [ ] No sentence left in the repo says iOS can only ever be verified in CI
- [ ] Every Claude Code flag and feature the guide names is checked against the current Claude Code documentation, linked in the PR body
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] Follow `docs/running-locally.md` from the top on the Mac with nothing set up. You should end with a session driving a scratch plan, without having had to look anything up elsewhere
- [ ] Connect to that session from your phone as the guide describes and say `status`. You should get the per-phase report
- [ ] Quit the terminal mid-wait, reopen it as the guide describes, and say `status`. It should recover
- [ ] In an Xcode project on the Mac, run the planner. It should propose `verify: local` and say that the full test suite stays in CI
- [ ] Start a local build by hand while a runner job is building the same project. Following the hygiene advice, neither should fail on a locked build directory or a busy simulator

**Risks.** The guide describes Claude Code features that move between releases. Simulator and DerivedData contention is intermittent, so advice that worked once can still be wrong. "Keep a session alive" is the part of local running with no recovery beyond the plan file: a session that dies overnight is noticed in the morning, which is the known gap `docs/design.md` already records.

---

### Phase 8 — Tool scaffold (sixoverground/codex-mr-review)

**Scope.** The base of a small Node CLI. The repo must already exist with an initial commit, per Prerequisites.

- `package.json`: name `codex-mr-review`, a `bin` of the same name, `"type": "module"`, `engines.node >= 20`, no runtime dependencies to begin with, MIT.
- `src/cli.js` with `--help`, `--version`, and a `review` subcommand that parses its flags and exits with "not implemented".
- Tests with `node --test`, a linter, `npm test` and `npm run lint`.
- `.github/workflows/ci.yml` on `pull_request` and on pushes to `main`, one job named `test`, on Linux and macOS.
- `README.md` saying what the tool is for and what it is not, `LICENSE`, `SECURITY.md`, `.gitignore`.
- `AGENTS.md` with the repo's own review guidance, since this repo's reviewer reads it.
- `docs/contract.md`: a link to claude-phases' `docs/review-contract.md` at a pinned commit, and the statement that this tool implements v1.

**Depends on.** Phase 1. The contract is what the tool is built against.

**Acceptance criteria.**
- [ ] `npm ci && npm test && npm run lint` pass on a clean clone
- [ ] `node src/cli.js --help` lists `review` and its flags, and `--version` prints the version from `package.json`
- [ ] The `test` check runs on this PR and passes on both operating systems
- [ ] No file in the repo mentions claude-phases other than `docs/contract.md`

**UAT.**
- [ ] Clone the repo, run `npm ci && npm test`. It should pass
- [ ] Run `npx . --help`. You should see usage text naming the `review` subcommand
- [ ] Open the Actions tab. The `test` job should have run on this PR for both operating systems

**Risks.** The repo is new, so its checks and its reviewer have never been observed on a PR; this one is the first. `ci.allow_none` is `false` for this repo although it has no CI yet, on the reasoning that this PR adds the workflow and Actions runs a workflow from the PR that introduces it. If no check reports on this PR, the gate blocks, loudly, and that is the signal to look at the org's Actions settings. If cloud Codex is not enabled for the repo, gate 6 waits and never times out, by design.

---

### Phase 9 — Review runner and dry run (sixoverground/codex-mr-review)

**Precondition, checked before this phase is claimed.** The session is on the Mac, `codex` is installed and logged in, and the `phase-driver` skill it is running has `references/watching.md`, which means `M1` is installed and this session has loaded it. If any of these fails, start nothing and say which. The dependency on `M1` guarantees the release exists; this check covers a session that was not restarted or a machine that was not updated.

**Scope.** Run Codex's own review mode on a diff and turn what it returns into findings. No network use by the tool yet.

- `codex-mr-review review --base <ref> [--head <ref>] --dry-run [--format text|json]`.
- The runner starts `codex exec` with the read-only sandbox and the built-in `review` subcommand against the base, with `--json`, `--ephemeral`, and a structured final message. No custom review prompt. The child process gets an allowlisted environment, so no token in the tool's own environment reaches it.
- Review guidance comes from `AGENTS.md`, which Codex reads by itself. The tool reviews in a temporary worktree of the head commit in which `AGENTS.md` is the **base** branch's copy, so a merge request cannot rewrite the instructions for its own review. When the head changes `AGENTS.md`, the summary says so.
- `src/findings.js`: normalise to `{ path, start_line, end_line, priority, title, body, fingerprint }`. Priority is P0 to P3. The fingerprint hashes the path, the normalised title and the text of the flagged lines, and not the line numbers, so a finding survives lines moving.
- **The same shape as cloud Codex.** A finding is rendered the way cloud Codex renders one on a GitHub PR: the same P0 to P3 priority labelling in the same position, then the title, then the body, and one summary for the review. `docs/output-format.md` records a real cloud Codex inline comment and summary from a public PR as the reference, and `test/fixtures/` holds it. The point is that anything already written to read a Codex review, a person or `phase-driver`, reads this one the same way.
- Exit codes: 0 when the review completed, with or without findings; non-zero when Codex failed, timed out, or returned something that does not parse. A failed run prints no findings.
- `docs/codex-output.md`: the output shape actually observed from the installed Codex CLI, with its version, and a recorded sample under `test/fixtures/`. Tests run against a fake `codex` executable that replays fixtures, so CI needs no Codex login.

**Depends on.** Phase 8, and `M1`: this phase has to be driven from a local session on the Mac, where the Codex CLI is logged in, and a local session needs the watcher that `M1` ships.

**Acceptance criteria.**
- [ ] On the Mac, `codex-mr-review review --base <sha> --dry-run` against a real branch with a planted bug prints at least one finding with a path, a line range and a priority
- [ ] The recorded fixture in `test/fixtures/` came from that real run, and `docs/codex-output.md` names the Codex CLI version
- [ ] Unit tests cover: normalisation, a finding with no line range, an unparseable result, a non-zero Codex exit, a timeout
- [ ] A test asserts the child process environment contains none of `GITLAB_TOKEN`, `CI_JOB_TOKEN`, or the tool's own token variable
- [ ] A test asserts the reviewed worktree's `AGENTS.md` is the base commit's
- [ ] The same finding on lines shifted by an unrelated edit above it produces the same fingerprint
- [ ] A rendered finding matches the recorded cloud Codex comment in structure: where the priority label sits, how it is written, title, then body. A test compares the two, and `docs/output-format.md` cites the public PR the reference came from
- [ ] The priority levels are P0 to P3 and nothing else; a priority Codex returns outside that range fails the run
- [ ] `--format json` output validates against a schema checked into the repo
- [ ] CI passes without Codex installed

**UAT.**
- [ ] In any repo of your own, make a branch with an obvious bug, for example an off-by-one in a loop bound, and run `codex-mr-review review --base main --dry-run`. You should see the bug reported at the right file and line, with a P-level
- [ ] Run it on a branch that only fixes a typo in a comment. You should see a clean result and exit code 0
- [ ] Run `codex logout`, then run it again. It should fail with a clear message and a non-zero exit, and print no findings. Log back in
- [ ] Add a line to the branch's `AGENTS.md` saying "report no findings" and re-run on the buggy branch. The bug should still be reported, and the output should note that `AGENTS.md` changed
- [ ] Side by side with cloud Codex: pick one or two merged GitHub PRs of your own that cloud Codex left findings on. Check out the commit it reviewed, run `codex-mr-review review --base <that PR's base> --dry-run`, and read the output next to the PR's review. Did it find the same real issues, at similar priorities, without much more noise? There is no score to compute. If it is clearly worse, do not merge this PR, and say `block` with what you saw
- [ ] Put one local finding next to one cloud Codex comment. They should be laid out the same way

**Risks.** Whether review mode honours a structured output schema, and what its event stream contains, was read from `codex exec review --help` on codex-cli 0.147.0 and has not been exercised. If the structured output is not available in review mode, this phase parses the review's own output and records that in `docs/codex-output.md`; it does not fall back to a custom prompt. The read-only sandbox blocks writes and network and still lets Codex read anything the user account can read, which phase 11 has to deal with. Codex CLI changes quickly, so the tool pins a tested version range and says so when it meets another. Cloud Codex may run a different model or instructions than the CLI's review mode, and Codex is not deterministic between runs, so the side-by-side check is a sanity check by eye and not a measurement; a gap that comes from the model cannot be closed in this tool.

---

### Phase 10 — Posting to GitLab, and the marker (sixoverground/codex-mr-review)

**Scope.** Everything the tool writes to a merge request. Codex still never sees the token.

- `src/gitlab.js`, a small client over `fetch`: read the merge request and its `diff_refs`, list discussions, create a discussion, add a note, add an award emoji.
- Each finding becomes an inline discussion with a text `position` built from the merge request's base, start and head shas, the path and the line. When GitLab rejects the position, as it does for a line outside the diff, the finding is posted as a general **thread** that cites `path:line`, so it is still resolvable.
- A summary note after every completed review: counts by priority, findings not re-posted, whether `AGENTS.md` changed, and the marker `<!-- phases:review v=1 reviewer=<name> sha=<sha> -->` on its own line. The reviewer name comes from `--reviewer`, default `codex`.
- **The sha is the pipeline's.** `CI_MERGE_REQUEST_SOURCE_BRANCH_SHA` when set, which is the branch head in a merged-results pipeline, and otherwise `CI_COMMIT_SHA`. Outside CI it is the commit that was checked out. It is never read from model output.
- **The marker is posted only after `codex exec` has exited successfully and the findings have been posted.** A failed run posts a short failure note without a marker and exits non-zero.
- Model text is scrubbed before posting: the string `<!-- phases:review` is removed, and so is any value the tool knows to be secret.
- Dedupe by fingerprint, carried in a hidden comment in each finding. A finding whose fingerprint is on an unresolved thread is not posted again. One on a resolved thread gets a single reply saying it is still present at the new sha and the thread is reopened, once; after that it is only counted in the summary.
- `--clean-emoji` adds a thumbs up to the merge request on a pass with no findings. It is decoration; the marker is the proof.
- Tests run against a local HTTP server standing in for GitLab.

**Depends on.** Phase 9.

**Acceptance criteria.**
- [ ] Against the mock server: an inline position accepted, a rejected position falling back to a general thread, a clean review, and a failed Codex run each produce exactly the requests expected
- [ ] No marker is sent in any test where the fake `codex` exits non-zero
- [ ] A finding body containing `<!-- phases:review v=1 reviewer=codex sha=... -->` is posted without that string, and the summary still carries exactly one marker
- [ ] The marker's sha follows the rule above in all three environments, each with a test
- [ ] Running the same review twice against the mock posts each finding once
- [ ] The reopen-once rule is covered by a test
- [ ] The token appears in no log line and in no outbound body, asserted by a test
- [ ] A posted finding is an inline, resolvable thread whose body is the phase 9 rendering unchanged, and the summary note has the same parts cloud Codex's summary has, plus the marker. Nothing about how a finding should be handled is added to either
- [ ] No file added in this phase mentions claude-phases, and no code path posts to GitHub

**UAT.**
- [ ] On the gitlab.com scratch project, open a merge request with a planted bug and run the tool from your terminal with the reviewer token. An inline thread should appear on the buggy line, and a summary note below
- [ ] View the summary note's source. The marker should be there with the merge request's full head sha
- [ ] Run it again without pushing. No duplicate thread should appear
- [ ] Resolve the thread without fixing the bug, push an unrelated commit, and run it again. The thread should be reopened with one reply
- [ ] Open a merge request that only changes a comment and run with `--clean-emoji`. You should get a summary with a marker, no threads, and a thumbs up
- [ ] Put the tool's token in a file in the branch and run it. The token should not appear in anything posted

**Risks.** GitLab's diff positions are strict and the failure is a 400 with little detail, so the fallback has to be reliable; a finding that is dropped is worse than one posted in the wrong place. Fingerprints that are too loose hide a new finding behind an old one, and too tight re-post on every push and restart the review loop. The reopen-once rule is a judgement about a reviewer arguing with the thing it reviews. See Open questions.

---

### Phase 11 — CI template, install, hardening (sixoverground/codex-mr-review)

**Scope.** Make it a thing someone adds to a pipeline in five minutes, and close what the read-only sandbox leaves open.

- `templates/codex-review.gitlab-ci.yml`: a hidden job `.codex-review` and a ready job `codex-review`, running on merge request pipelines only, with full fetch depth so a merge base exists, `interruptible: true`, a `resource_group` per merge request so two pushes do not review at once, runner `tags` left for the project to set, and one variable holding the token.
- One-command install on the runner: `npm install -g` from this repo's release tag, with no registry account needed. `README.md` shows it, and the `include:` snippet for a project's `.gitlab-ci.yml`.
- Hardening. Before Codex starts, the tool removes credentials from the review worktree's git config, where a CI checkout leaves the job token in the remote URL. It redacts its own token and `CI_JOB_TOKEN` from everything it posts. `SECURITY.md` states what remains: the read-only sandbox can read any file the runner's user can, so a shell-executor runner on a personal Mac should run as a dedicated user, and what a finding quotes is visible to everyone on the project.
- `README.md` completed: what it does, the contract it implements and the link to it, setup for a shell-executor runner on macOS, Codex authentication on the runner, the token and the role it needs, configuration flags, and how to run a reviewer other than Codex through the same job by having it emit the contract.
- Tag `v0.1.0` and a `CHANGELOG.md`.

**Depends on.** Phase 10.

**Acceptance criteria.**
- [ ] The template parses as valid GitLab CI, checked with GitLab's CI lint for the scratch project where the session has access, and otherwise stated as unchecked
- [ ] A test proves the reviewed worktree's git config holds no credential
- [ ] A test proves a finding quoting the token value is posted redacted
- [ ] The install command in the README, run on a clean Node 20, produces a working `codex-mr-review --version`
- [ ] `SECURITY.md` names the residual risk of the read-only sandbox and the dedicated-user recommendation
- [ ] The README describes the tool with no reference to claude-phases beyond naming the contract it implements

**UAT.**
- [ ] On the Mac's runner user, run the README's install command. `codex-mr-review --version` should print 0.1.0
- [ ] In the gitlab.com scratch project, add the `include:` snippet, set the runner tag, and add the token as a masked CI variable. Open a merge request with a planted bug. The `codex-review` job should run on your Mac, pass, and leave an inline thread and a summary with a marker
- [ ] Push a fix. The job should run again and the summary's marker should name the new sha
- [ ] Push twice in quick succession. Only one review should be running at a time, and the earlier one should be cancelled or finish first
- [ ] Remove the token variable and push. The job should fail red with a message saying the token is missing, and post nothing
- [ ] Open a merge request from a fork or with a protected-only variable, if the project allows either. The job should fail visibly. It should never pass having posted nothing

**Risks.** A CI variable marked protected is not given to pipelines on unprotected branches, which is every phase branch, and the symptom is an empty token. The runner uses the Mac user's Codex login, so reviews draw on that account's usage, and a rate limit looks like a failed job. A shell executor shares the machine with whoever else uses it. Installing from a git tag avoids needing npm credentials and means no `npx` one-liner; see Open questions.

---

### Phase 12 — Reviewer setup for a marker reviewer (sixoverground/claude-phases)

**Scope.** Connect the two tracks, in documentation and detection only. The driver already reads markers.

- `docs/review-setup.md`: the opening table gains a sixth row, and a new section **GitLab with a local Codex review**. It covers installing the tool on the runner, the `include:` snippet, the token and why it should be a different identity from the driver's, the config below, and what to check on the first merge request. A subsection, **Another reviewer through the same job**, says the snippet can run any command, a Claude review for example, as long as it emits the contract, and links `docs/review-contract.md`. **Verifying your setup** gains the GitLab steps: the job ran, the threads are on diff lines, the summary carries a marker with the head sha, and a second push produces a second marker.

  ```yaml
  review:
    required:
      - marker: "codex"
        logins: ["<the reviewer token's username>"]
  ```

- `skills/phase-planner/references/configuration.md`, **Reviewer setups**: a row for it.
- New `profiles/review-codex-local.yml`, and its row in `profiles/README.md`.
- `skills/phase-planner/references/detection-gitlab.md`, **Who actually reviews**: recognise a marker reviewer from a CI job that includes or extends the tool's template or calls its command, and from marker notes on recent merge requests; read the reviewer name and the author's username off a real note; propose the entry above. The phase 6 refusal for a marker reviewer with nothing behind it now names this setup as the fix.
- `skills/phase-driver/references/forge-gitlab.md`, **Asking a reviewer to look again**, and `watching.md`: a note from a person that says `@codex review` is a request to run the review job again, and the driver answers it by creating a merge request pipeline. Document that nothing answers it when no driver is running.
- `skills/phase-planner/references/hygiene.md`: the review job must not be `allow_failure: true`, and its token variable must not be protected.
- **Experimental, in three places and no more**, because `M2` ships this before anything has driven GitLab with it: the **Forge** section of `skills/phase-planner/references/configuration.md`, the top of `skills/phase-driver/references/forge-gitlab.md`, and `README.md` **Requirements and integrations**. Each says GitLab support is experimental until it has driven a real project end to end.
- `README.md` **Documentation** lists `docs/running-locally.md` and `docs/review-contract.md`.

**Depends on.** Phase 7, and phase 11 for the job's name, the install command and the template path.

**Acceptance criteria.**
- [ ] `docs/review-setup.md` has the new section, the row, the "another reviewer" subsection and the GitLab verification steps, and every command in it matches the tool's README at v0.1.0
- [ ] `profiles/review-codex-local.yml` uses only documented keys and carries a comment on why `logins` is there
- [ ] `detection-gitlab.md` reads the reviewer name and author from a real note and does not guess them
- [ ] The `@codex review` handling is in `forge-gitlab.md` and `watching.md`, and both say it needs a running driver
- [ ] The three experimental statements exist and say what would lift them
- [ ] claude-phases names the tool only in `docs/review-setup.md`, the profile, and the detection reference. The driver's gate text still speaks only of the contract
- [ ] The setup section says the driver handles this reviewer's findings by its existing rules for a Codex review, links them, and restates none. `git diff` shows no change under **Answering a review** in the driver skill
- [ ] The section says a reviewer meeting the contract can also gate a GitHub repo through the same `marker` entry, and that this tool does not post to GitHub
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] Follow the new section of `docs/review-setup.md` on the gitlab.com scratch project from nothing. You should end with a merge request that has an inline thread and a marker note
- [ ] Run the planner on that project. Its findings should name the marker reviewer, the reviewer name and the author it read them from, and propose the config above
- [ ] Remove the review job from `.gitlab-ci.yml` on a branch and plan against it with the marker entry kept. The planner should refuse and point at the setup section
- [ ] With a driver waiting on an open merge request, post `@codex review` as yourself. A new pipeline should start within about two minutes

**Risks.** The docs describe a tool at one version, and the two will drift; the section links the tool's README for anything that changes often. A reviewer and a driver sharing one token make `logins` meaningless and make the watcher wake on the driver's own notes. The setup section has to say that two identities are the supported arrangement.

---

### Milestone M2 — GitLab support (sixoverground/claude-phases)

**Ships.** Phases 4, 5a, 5b, 6, 7 and 12: the `forge`, `host` and `integration_pr` keys, the GitLab driver and gates, the planner on GitLab, the local guide and iOS verified on a Mac, and the setup for a marker reviewer. Labelled experimental.

**Review scope.** A finding on this PR is in scope when it falls within the scope of phases 4, 5a, 5b, 6, 7 and 12, taken together. The driver answers it by its usual rules and commits fixes to `feature/local-gitlab`. Anything beyond those scopes goes to Carried findings.

**Needed by.** Phase 13, which drives a real gitlab.com project with the installed driver and planner.

**UAT.** On the milestone PR before you merge it:
- [ ] Load the feature branch's skills on the Mac and run the planner on the gitlab.com scratch project. It should detect the project, its jobs, the runner and the marker reviewer, and write a plan with `forge: gitlab`
- [ ] Say "run the next phase" on that plan and stop after the merge request opens. It should exist, with the right source and target, and the plan's row should say `In Review` with a `group/project!N` link
- [ ] Drive one phase of an existing GitHub plan with the same skills. Nothing should have changed for it
- [ ] Read the three experimental statements. Each should say what is untested

After merging:
- [ ] The driver should record `M2`, re-create the feature branch, update the plugin, and say whether to restart
- [ ] Ask the session that will drive phase 13 whether its `phase-driver` has `references/forge-gitlab.md`. It should

**Risks.** This puts GitLab support on `main` before the trial, and that is the reason for the label; a user who ignores the label is the first tester. The UAT above is a smoke test and not the trial.

---

### Phase 13 — End-to-end trial on gitlab.com (sixoverground/claude-phases)

**Precondition, checked before this phase is claimed.** The session is on the Mac, `glab` is authenticated for gitlab.com, and the `phase-driver` skill it is running has `references/forge-gitlab.md`, which means `M2` is installed and this session has loaded it. If any of these fails, start nothing and say which.

**Scope.** The first time everything runs together, on a personal gitlab.com project with no VPN and no client. A toy plan of two phases, driven from a local session on the Mac, through merge request, pipeline, Codex review, a fix, and merge.

- Set up the scratch project as `docs/running-locally.md` and `docs/review-setup.md` describe: a small Node or Swift package, a `.gitlab-ci.yml` with a `build-test` job and the `codex-review` job on the Mac's runner, a long-lived branch as both `target_branch` and `plan_branch`, `integration_pr: false`.
- Write the toy plan with the planner. Phase one plants a real bug on purpose so the reviewer has something to find; phase two depends on it.
- Drive it locally with the installed `M2` release. Give the toy plan one milestone row of its own, so a milestone is exercised on GitLab too. YOLO, in the toy plan's own Driver State, off for the first phase and on for the second.
- New `examples/gitlab-local.md`: the plan as it ran, with links, and what each wake was.
- Fix what the trial exposes in `forge-gitlab.md`, `watching.md`, `detection-gitlab.md` and the docs. A problem too large for this phase goes to Carried findings, and a problem in the tool is an issue on the tool's repo.
- `docs/design.md`: a short account of the trial under a new heading, in the style of the README's "First production run".

**Depends on.** `M2`.

**Acceptance criteria.**
- [ ] The PR body links both merge requests of the toy plan, merged, and the pipelines that gated them
- [ ] The PR body states the installed claude-phases version the toy plan was driven with
- [ ] On the first: a Codex finding as an inline thread, a fix pushed by the driver, the thread resolved by the driver, a second marker at the new head, and gate 6 passing on that marker
- [ ] The driver answered that finding by its existing review-handling rules, with no GitLab-specific instruction beyond the mappings in `forge-gitlab.md`; anything it could not handle that way is recorded as an observation
- [ ] On the second: merged by the driver with `--sha`, and the source branch deleted by the server
- [ ] The toy plan's milestone: a merge request from the long-lived branch to the default branch opened by the driver, not merged by it, and after you merged it, the long-lived branch back in line with the default branch
- [ ] The plan file on the scratch project shows both rows `Merged`, each status commit ending `[skip ci]`, and no pipeline having run for a plan commit
- [ ] The session was killed once mid-phase and a new one recovered from the plan and GitLab alone; the PR body says at which point
- [ ] The network was dropped once during a wait; no row went to `Blocked`, and the driver reported it once
- [ ] Every correction made to a reference or doc in this PR names the observation behind it
- [ ] `examples/gitlab-local.md` exists and matches what ran
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] Read both merge requests on gitlab.com from top to bottom. The review thread, the driver's reply and the resolution should tell a story you can follow without the session's transcript
- [ ] In the scratch project's branch list, only the default and long-lived branches should remain
- [ ] Open the plan file's history. You should see three status commits per phase and nothing else from the driver
- [ ] Start a fresh local session in the project and say `status`. It should report the plan complete and name any carried findings and outstanding UAT
- [ ] On the scratch project, start one more toy phase and, while its merge request is open, push a commit to it yourself right as the driver is about to merge. The merge should be refused and the driver should re-evaluate

**Risks.** This is where the prose written in phases 5a to 6 meets a real server, and it will be wrong somewhere. The phase is sized for small corrections; a structural problem is a replan, and the plan should stop here if one appears. gitlab.com is not the client's instance: a different version, a different tier, no VPN, and an owner's permissions where the client grants Developer. The trial proves the design and leaves those four differences untested, and the handoff has to say so. The answers still owed about the client's instance decide that rollout and do not block this phase. Corrections made here are on the feature branch, so the toy plan keeps running on the `M2` release; a correction the trial cannot proceed without is tried with `--plugin-dir` on this phase's branch, as "How this plan is driven" describes.

---

### Phase 14 — Cleanup (sixoverground/claude-phases)

**Scope.** Say in the project's own documents what it now is. This is the last phase. `M3` ships it, with the version bump and the changelog entry made by the milestone's preparation.

- `.claude-plugin/plugin.json`: the description and keywords mention GitLab. The version is left to `M3`.
- The three experimental statements from phase 12: remove them, or keep them and say exactly what is untested, depending on what phase 13 found.
- `README.md`: the diagram, **Quick start** and **Requirements and integrations** say GitHub or GitLab; **The merge gate** table is worded for both; **Project status** gains the GitLab line and the trial; **Documentation** lists `examples/gitlab-local.md`.
- `CONTRIBUTING.md`, **Scope**: replace "support for forges other than GitHub" being out of scope with how to add a forge, one reference file per skill with the same headings. **Keep the contract files in sync** names the forge references and the review contract. Add that PRs into a feature branch skip `Version bumped` and the bump happens once before the branch reaches `main`.
- `SECURITY.md`: the trust boundary names merge request notes and job traces, and a local session's exposure, which is the maintainer's own machine and credentials where a cloud session had a container.
- `docs/design.md`: **Design at a glance** gains the forge-neutral core; new sections on the review contract and why the script owns the marker, and on the watcher; **Known gaps** says the head-moved window is closed on GitLab and open on GitHub, and says what the trial left untested; **Things deliberately not done** records shipping the watcher as a script, GitHub posting in the review tool, and new rules for reading a self-hosted Codex review.
- `.github/ISSUE_TEMPLATE/setup_not_supported.yml` and `bug_report.yml`: a forge field.
- Search the repo for claims this plan made false: "The only required platforms are GitHub", "iOS is CI-only", "there is nothing to poll".

**Depends on.** Phase 13.

**Acceptance criteria.**
- [ ] This phase's diff leaves `version`, the description version sentences and `CHANGELOG.md` alone
- [ ] The PR body's changelog sentences say what the trial found and fixed and what became of the experimental label, for `M3` to assemble
- [ ] No document says GitHub is the only supported forge, or that iOS can only be verified in CI
- [ ] Every remaining "experimental" statement is followed by what is untested, and where the docs claim something about GitLab, phase 13 observed it
- [ ] `CONTRIBUTING.md` describes adding a forge
- [ ] `docs/design.md` has the three new sections and the updated known gap
- [ ] The conventions under "How this plan is driven" hold

**UAT.**
- [ ] Read the README from the top as a GitLab user who has never seen the project. You should know within the first screen that your forge is supported, and find the local guide and the reviewer setup from the Documentation list
- [ ] Read it again as an existing GitHub cloud user. Nothing should suggest you need to change anything

**Risks.** A cleanup phase is where a last unreviewed behaviour change slips in under a docs diff. Keep it to documents, the manifest and the labels. The claims about GitLab should be exactly as strong as phase 13's evidence.

---

### Milestone M3 — The finished feature (sixoverground/claude-phases)

**Ships.** Phases 13 and 14: the corrections the trial produced, `examples/gitlab-local.md`, and the documentation that says GitHub or GitLab.

**Review scope.** A finding on this PR is in scope when it falls within the scope of phases 13 and 14, taken together. The driver answers it by its usual rules and commits fixes to `feature/local-gitlab`. Anything beyond those scopes goes to Carried findings.

**Needed by.** Nothing in the plan. It is the end, and the last row.

**UAT.** On the milestone PR before you merge it:
- [ ] Read the CHANGELOG section the preparation wrote. It should tell what the trial found, and link the two earlier entries so the plan can be read in order
- [ ] Read the whole diff as one change

After merging:
- [ ] The release should appear with its notes and both skill zips
- [ ] The driver should record `M3`, leave the feature branch deleted since no row targets it any more, set `Driver: idle`, and name any outstanding UAT and carried findings
- [ ] Ask Claude which version of claude-phases it has. It should name the new one
- [ ] Drive one phase of any existing GitHub plan in a cloud session on the released version. It should behave as it did before this plan started

**Risks.** If `main` moved while the trial ran, the preparation's bump may collide; the driver redoes it on what `main` says. The claims this release makes about GitLab should be exactly as strong as phase 13's evidence.

## Open questions

**Open until phase 0d's UAT answers it.**

1. **Whether a running session picks up an updated plugin.** Unknown. Phase 0d's UAT finds out. If it does not, a restart after each milestone stays manual.

**Can be settled when the phase that raises them is reached.**

2. **Where the UAT goes with `integration_pr: false` and issues disabled.** Phase 4 proposes posting the script on the last merged change request and leaving `UAT-pending` set. The alternative is a section in the plan file, which is a format change.
3. **Should watching be configurable?** Phase 3 chooses by capability: subscribe where the session can, poll where it cannot. There is no `watch` key. Say if you want one.
4. **The For the driver text.** It says "woken by a check-in or a webhook" and both skills forbid editing it. A watcher wake is neither, in name. Phase 3 leaves the text alone, on the grounds that every watcher line carries its own instruction to invoke the skill.
5. **The missing `## 6` in the driver skill.** Gate evaluation and merging sit unheaded at the end of §5 and the numbering jumps to §7. No phase here restores it. Phase 0b adds its Milestones section before §8 without taking the number.
6. **`blocking_labels`.** `gates.md` gives it a default and an off switch; `configuration.md` does not document the key. Not in any phase's scope here. Say if phase 4 should add it.
7. **A finding that comes back after its thread was resolved.** Phase 10 has the tool reopen the thread once with a reply and then only count it. This is the tool's posting behaviour; how the driver answers a re-raised finding is already in its skill and is not changed.
8. **How the tool is installed.** Phase 11 installs from a git tag with `npm install -g`. Publishing to npm gives a shorter command and needs an npm account and a name that is free.
9. **`AGENTS.md` from the base branch.** Phase 9 reviews with the target branch's copy, so a merge request cannot change its own review instructions. A merge request that legitimately improves `AGENTS.md` is then reviewed under the old one. Confirm.

**Owed for the client rollout, and not blocking this plan.** The trial in phase 13 runs on gitlab.com, so none of these stops a phase. They decide whether and how the result can be used on the client's instance afterwards.

10. **One token or two on the client's GitLab.** The supported arrangement is a driver identity and a separate reviewer identity. Creating a project access token usually needs the Maintainer role. With one token, `logins` cannot tell the reviewer from the driver and the watcher wakes on the driver's own notes.
11. **What the Developer-role token may do on the long-lived branch.** If that branch is protected and only Maintainers push or merge, the driver cannot write plan status to it and cannot merge under YOLO. With milestones there is a second consequence: a plan with milestone rows keeps its plan off the shipped branch, which on the client's project means the default branch or a branch of its own.
12. **The client instance's GitLab version and tier.** Gate 4 on GitLab depends on both, and so do some fields phase 5b reads. Unknown means gate 4 is off there and says so.

**A possible follow-up, in no phase here.** GitHub posting in `codex-mr-review`, so the same tool could serve as a self-hosted reviewer on GitHub through the `marker` entry.

## Driver State

- Driver: running
- YOLO: off
- Driver-ID: drv-550f5e23
- Active: 0a — sixoverground/claude-phases
- UAT-pending: -
- Review-baselines: -
- Arbitrations: -
- Heartbeat: 2026-11-17T15:16:59Z
- Note: -

---
name: phase-planner
description: Write a phased implementation plan to a docs/plans markdown file named for the project. Break work into one-PR phases, detect each repo's CI and review setup, and propose matching configuration. Use when asked to plan a project, break work into phases, set up a phased plan, or create a plan for phase-driver to execute. Also use when revising an existing plan's phases or configuration. This copy is claude-phases 0.11.0.
model: fable
---

# Phase planner

You write the plan that `phase-driver` executes. Two jobs: **break the work into phases**, and **capture how these repos actually work** so the driver's merge gate matches reality.

Read `references/detection.md` for the detection procedure, or `references/detection-gitlab.md` for a GitLab repo, and `references/hygiene.md` for the repo checklist when you reach those steps.

The format you're writing is specified in `references/format.md`, and every front-matter key in `references/configuration.md`. Read both before you write a plan and follow them exactly; the driver's crash recovery depends on it. `references/plan-template.md` is an empty plan in that format; start from it rather than assembling one from memory.

## 1. Ask three things

Only three. Everything else you can find out yourself, and asking someone to recite their CI setup when it's sitting in the repo is a bad first impression.

1. **What are we building or changing?** A few sentences.
2. **Which repos?** `owner/name`, possibly several, or `group/project` on GitLab.
3. **Project name?** Lowercase, hyphenated. Becomes the plan's filename.

**Ask with `AskUserQuestion`, all three in one call, and keep every later question in the same tool.** This skill sets `model` in its front matter, and Claude Code applies that for the rest of the turn it was invoked in and no longer: the session model comes back the moment a turn ends and the person replies. A question asked as ordinary text ends the turn, so the detection, the confirmation and the plan itself would run on whatever model the session was started with. `AskUserQuestion` blocks inside the turn, and planning stays on one model from the first question to the written file.

Offer what you can infer as options, so the common answer is a click: the current repo for *which repos*, its name for *project name*. Anything else arrives typed under Other. *What are we building* cannot be inferred and cannot be answered by an option, so its options exist only because the tool requires some. Offer the kind of work, a new feature, a refactor or migration, a fix, and treat whatever comes back as a category rather than a description. If no description arrived, ask again for the description alone before you do anything else. A plan cannot be cut from "a new feature".

**Which forge and host, when a repo is not on github.com.** A repo on github.com needs nothing: GitHub is the default. Otherwise the plan needs `forge` and `host` for it, and both decide where the driver reads and writes (see `references/configuration.md`, **Forge**). Infer them from the checkout's remote where you can: `git remote get-url origin` naming a host other than `github.com` is proposed as `forge: gitlab` with that host, and `gitlab.com` needs no `host`. Then confirm, through `AskUserQuestion`, with the inferred forge and host as the first option. Ask this after the three questions, not among them, and only for a repo that is not on github.com: a remote says which host a clone came from, not which forge runs there, so it is never taken as settled without the person's yes. A repo named with no checkout to read gets the same question with no inferred option.

One more thing you need but shouldn't have to ask for: **`home_repo`**, where the plan file lives and the only repo the driver writes state to. With a single repo it's that repo. With several, propose the one the work centres on. Usually the backend or the repo with the most phases, and confirm it in the same breath as your detection findings. Don't leave it unset: it's required, and a plan without it doesn't load.

## 2. Detect how each repo works

Never assume. Inspect, then show your evidence. See `references/detection.md` for what to query and what each result implies, or `references/detection-gitlab.md` for a GitLab repo.

Report findings as a short table before writing anything:

```
acme/acme-web
  default branch   main              (from the repo)
  CI               2 checks on recent PRs: build, test
  dispatch         workflow_dispatch declared in ci.yml
  reviewer         Copilot reviewed the last 5 PRs
  review rules     CLAUDE.md caps fix rounds at 3; escalate on follow-ups
  verify           local (package.json, node)
```

A GitLab repo gets the same table, with job names where check names were, the host beside the project path, and three lines more: the runner, issues, and whether the token can merge. Mark anything you could not observe directly as inferred, as `detection-gitlab.md` says:

```
acme/platform/web   (gitlab.example.com)
  default branch   main              (from the project)
  CI               3 jobs on recent MR pipelines: build-test, lint, codex-review
  external         none seen on recent MR heads
  dispatch         push (GitLab)
  runner           mac-mini (#12) for tag macos, online, ran MR jobs from unprotected branches (inferred from recent jobs)
  reviewer         codex marker on the last 4 MRs, posted by codex-bot
  merge            Developer; target branch unprotected, so YOLO can merge
  issues           enabled
  review rules     none found
  verify           local (package.json, node)
```

Then say what you inferred, and ask whether it holds, through `AskUserQuestion` again: one confirmation for the lot, with *correct something* as an option, or one question per repo where a finding is genuinely uncertain. People will tell you "we're moving off Copilot" or "that repo's CI is broken, ignore it", facts you cannot read from the API.

**Where detection comes up empty**, such as a new repo with no PR history, say so plainly and ask, through the same tool. Guessing produces a config that fails on the first PR, which is worse than one question.

## 3. Refuse configurations that can never pass

Before writing, check the config you're about to produce against what you observed. Refuse and explain if:

- a name in `ci.required` matches no check seen on any recent PR
- a login in `review.required` has never reviewed in that repo. For a `marker` entry, check its `logins` against the authors of marker notes instead: a reviewer that has only ever found nothing has posted markers and no reviews, and is set up correctly
- a `check` in `review.required` matches no check run you've seen
- `ci.allow_none: false` on a repo with no CI at all
- `target_branch` names a branch that doesn't exist
- `plan_branch` names a branch that doesn't exist
- a required check comes from a workflow that **can't fire on `target_branch`** (see below)

Every one of these produces a gate that waits forever. The failure surfaces as "waiting for CI" long after the plan was written, when nobody remembers what was configured, so it must be caught here.

**The base-branch trap.** A check seen on recent PRs is not proof it will appear on *your* PRs. `on: pull_request:` with a `branches:` filter fires only for PRs targeting the branches listed, and PRs into a feature branch commonly fall outside it. Read the filter for every workflow producing a name in `ci.required` or `review.required[].check`, and refuse if `target_branch` isn't matched. Naming which workflow and which filter is most of the fix.

The same applies to checks you *can't* read: CodeQL default setup and external providers like Xcode Cloud configure their own start conditions, often scoped to the default branch. Don't put those in `ci.required` when targeting a feature branch. Left unnamed they're counted only if they actually appear, which is the behaviour you want while their scope is unverified.

**Also warn** when a reviewer is configured but is only known to post top-level comments. `threads_must_resolve` needs diff-anchored comments to mean anything.

**A `marker` entry has a refusal and a warning of its own.**

- **Refuse** a `marker` entry when no top-level comment on any recent PR carries that reviewer's marker **and** nothing in the repo could post one: no CI job, workflow or installed tool that runs the reviewer. A marker no one will ever write is a gate that waits forever. Change: name the reviewer that is actually set up, or set the reviewer up first. Where the repo does contain the job that will post it but no PR has run it yet, say so in the findings rather than refusing, and let the first phase PR confirm it.
- **Warn** when a `marker` entry has no `logins` on a repo where people outside the project can comment, which includes every public repo. A marker is plain text, so anyone can type one for the current head and make an unreviewed commit pass gate 6. Change: set `logins` to the account the reviewer posts as.

**A GitLab repo has four refusals of its own**, from [`detection-gitlab.md`](references/detection-gitlab.md). Each ends in a gate that waits forever, and each names what it checked and what to change:

- **A name in `ci.required` that matches no CI job and no external status seen on recent merge requests.** Checked against two sources: the jobs of the CI file on `target_branch` (`ci/lint`, includes expanded, inheritance resolved, hidden templates excluded), and the external commit statuses on the heads of recent MRs into `target_branch`. Change: use the job's or status's name exactly as it appears, one per `parallel` instance, or drop the name. A `parallel` job's base name is refused: only its expanded names, such as `test 1/3`, ever appear. Name the CI file, and its path when the project sets `ci_config_path`, and say which MRs' statuses you read. A name that is a job still has to pass the next two refusals.
- **A required job that does not run by itself in a merge request pipeline into `target_branch`.** Checked against the job's `rules`, `only` and `except` after resolving `extends`, `!reference` and `default`, the project's own `workflow: rules`, the `when` of the first matching rule, and the `needs` it depends on, for a merge request pipeline into that branch. That covers a job with no conditions and no `workflow` creating merge request pipelines, a first matching rule of `when: never`, a blocking manual job, and a `needs` on a job that is not added. An inherited rule is named with the template it came from. Change: quote the rule that excludes it, and either widen the rule to merge request pipelines into `target_branch`, as its own phase before any other, or drop the job from `ci.required`. This is the base-branch trap in GitLab's form. Where a rule depends on a variable you cannot read, inheritance you cannot resolve, or a keyword the detection tables do not cover, do not refuse: say you could not tell, name the rule, the parent or the keyword, and ask. Refuse only on unconditional, documented behaviour, and never against a job seen finishing on a recent merge request pipeline into `target_branch`: there, show both and ask.
- **A required job that no online runner serves, by its tags or, untagged, as a runner that takes untagged jobs.** Not asked of a trigger job, which runs on GitLab rather than a runner. Checked against the resolved job's tags and the project's runners: one, project, group or instance alike, counts only when it is online, not paused, has every tag (or, for an untagged job, takes untagged jobs), and is not protected-only (`access_level: ref_protected` runs merge request pipelines only when both branches are protected, and phase branches normally are not). Where the token cannot list runners, against the runner recorded on recent jobs with those tags, said to be inferred, with what is known of its access level. Change: bring a matching runner online, register it as not protected, turn on `run_untagged` for an untagged job, change the job's `tags`, or drop it from `ci.required`. Name the job, its tags, the runners seen and why each does not count.
- **A `marker` reviewer with no job that could post it and no marker on any recent merge request.** Checked against the notes on recent MRs into `target_branch`, or the default branch where none exist, and against the CI file for a job that runs the reviewer. Change: name the reviewer that is actually set up, or add its job first. Where the job exists and no MR has run it yet, say so in the findings instead, as for the general `marker` refusal above.

**Also warn, for a GitLab repo:**

- **When the token cannot merge into `target_branch`.** A protected branch that a Developer may not merge into stops YOLO: every phase then waits for a person to press merge, whatever `YOLO` says. Say which branch, the token's role, and that a Maintainer, or `developers_can_merge` on the branch, would let the driver merge.
- **When `review.required` has entries other than `marker`.** On GitLab, gate 6 reads markers only, so an entry with only `logins`, a `check`, or `rereview` blocks every phase there. Change: make it a `marker` entry, or remove it.
- **When `ci.logs` is `actions` or `check-output`.** Those are GitHub's. On GitLab use `gitlab-jobs`, or leave the default `auto`, which resolves to it. Set `ci.dispatch: push` for every GitLab repo, since `auto` is GitHub-only.

**Milestone rows have four refusals of their own.** Each produces a plan the driver either stops on or that destroys its own state:

- **`plan_branch` is a branch a milestone row ships.** The branch is deleted on merge and re-created, and the plan goes with it. Change: leave `plan_branch` at the default branch.
- **A milestone row in a repo whose `target_branch` is its default branch.** There is nothing to ship. Change: drop the row, or target a feature branch in that repo.
- **A milestone whose `Depends` names a phase in another repo.** A milestone ships one repo's branch, so another repo's phase cannot be part of it. Change: give that repo its own milestone row, and have the later phase depend on both.
- **A phase that depends on a milestone in a repo it does not use, with no stated reason.** Usually a typo for the right milestone, or a dependency on a release that this phase never touches. Change: name the right row, or write the reason in the phase's **Depends on.**

**Warn** when a plan with any milestone row leaves work on a feature branch with nothing to ship it. A plan that has milestone rows opens no implicit integration PR in **any** repo, not only in the repos that have milestones. So check every repo whose `target_branch` is not its default branch: a repo with phases after its last milestone row, and a repo with phases and no milestone row at all, would both end the plan with that work never having reached the default branch. Change: add a final milestone row in that repo covering what remains, or record in the plan that leaving it on the feature branch is intended.

## 4. Design the phases

The rules that make a phased plan work. They're carried over from cpm, where they're already proven:

- **One phase = one PR = one repo.** Never split a phase across repos; use two rows and a `Depends`.
- **Every phase leaves the project working.** A phase that needs the next one to compile isn't a phase.
- **Size each to one session.** Roughly two hours. If it's bigger, split it into `3a` and `3b`. This is the most common planning mistake, and it produces PRs nobody wants to review.
- **Independently mergeable**, so an abandoned plan still leaves value behind.
- **Phase 0 is foundation.** Dependencies, config, base structure.
- **The last phase is cleanup.** Remove the legacy path, drop unused deps.
- **Sequential within a repo, parallel across repos.** Blank `Depends` means "the previous row," so phases meant to run in parallel across repos need their real dependency named explicitly. Leaving it blank there creates a dependency, not the absence of one.

For multi-repo work, order by what genuinely blocks what. Usually the API before the clients that call it. When platforms must ship together, don't pretend a simultaneous merge exists: add a dependency plus an explicit cutover phase.

### Milestones: only for a named need

A [milestone row](references/format.md#milestone-rows) ships a feature branch to the default branch part-way through a plan, and a person merges it. **Propose one only when phases target a feature branch and a later phase needs earlier work released, deployed or installed to do its job.** A phase that calls a deployed API, runs against a published package, or is driven by an installed copy of what earlier phases built is the usual case.

That need cannot be read from the repo, so ask it, once, through `AskUserQuestion`: *does any phase need earlier work to be live on the default branch, deployed or installed before it can start?* With a yes, ask which phase and what it needs.

Then:

- **Choose the fewest milestones the real dependencies allow.** Each one is a merge to the default branch, which in many repos is a release. Two phases that need the same earlier work share one milestone.
- **Say what each milestone is needed by**, in its section's **Needed by.** A milestone with nothing named there has no reason to exist.
- **The later phase depends on the milestone row**, not on the phases it ships. That dependency is the wait; nothing has to be paused by hand.
- **The default is none.** A plan in which nothing needs an early release gets no milestone row and no `milestone` key, and ends as plans always have, with the integration PR under YOLO. Once any repo has a milestone row, that end is gone for every repo, so each feature-branch repo needs a final milestone of its own; the warning in §3 catches the one that lacks it.

A planner that proposes milestones readily turns every plan into a series of releases. Start from the named need, every time.

### Write the details

Each phase gets scope, `Depends on`, acceptance criteria, UAT, and risks.

**Acceptance criteria** are what the driver verifies before opening the PR. Checkable, machine-verifiable where possible.

**UAT** is what a human does by hand afterward. Different audience: write steps someone can follow without reading the diff. What to open, what to do, what they should see. Cover the happy path, the obvious failure, and anything adjacent this phase could plausibly have broken. "Test the login flow" is not a UAT step.

## 5. Write the plan

To `docs/plans/<project>.md` in the home repo, **committed directly to the plan branch**. Not through a PR. The driver reads it from there, and a plan sitting in an unmerged PR is invisible to it.

The plan branch is the home repo's default branch unless you set `plan_branch`. Propose setting it when every repo's `target_branch` is the same non-default branch **and the plan has no milestone rows**: that's feature-branch work, and the plan belongs with the feature rather than on a `main` the feature hasn't reached. Set both keys, and confirm the branch exists in the home repo before writing.

**With milestone rows, leave `plan_branch` at the default branch**, and say why in the front matter: a milestone ships the feature branch, which is deleted and re-created when it merges, and a plan on it would go too. Then write `milestone.prepare` for each repo with a milestone row, from what [detection](references/detection.md#release-conventions--milestoneprepare) found, and `milestone.after_merge` only where something has to happen after a person merges. Leave either key out where there is nothing to say.

**Propose `integration_pr: false`** for a repo when the person says the merge from its feature branch to the default branch is someone else's decision, such as a release manager's, or goes through a process of its own. With it, the driver never opens that change request at the end of the plan, and the cumulative UAT goes to the fallback, as `references/configuration.md` describes under **YOLO**. Say that loss when you propose it. Leave it at its default otherwise: the integration PR is the handoff a person has to act on.

**If the plan branch rejects the commit**, branch protection is on. `plan_writes: plan-pr` doesn't rescue this. That key lives inside the plan file, so the commit that would deliver it is the one being refused. Instead: open a PR with the plan file, tell the user it must merge before the driver can start, and set `plan_writes: plan-pr` in the front matter so the driver uses the same path for every later status write. Don't hand off until it's merged; a driver pointed at a plan that isn't on the plan branch will report the project as unstarted.

Carry the **For the driver** section over from the template unchanged, between the title paragraph and the table. It is what sends a session that has lost the driver skill back to it, and a plan without it can stall on the first merge after a compaction.

Front matter carries the config you detected. Set the initial `YOLO` in Driver State: default it **off**, and say why. Unattended merging is a decision someone should make deliberately once they trust the setup, not inherit from a default.

Leave `Driver-ID`, `Driver-Host` and `Active` empty. The driver claims those.

## 6. Hand off

Tell them:

- where the plan is, and how many phases
- anything in `references/hygiene.md` still worth doing
- how to start: open a Claude Code session on the repo and say **"run the next phase"**
- that they can steer it from a phone, `status`, `pause`, `yolo on`, `skip`

## Revising an existing plan

When asked to change a plan already in flight:

- **Read Carried findings first.** The driver appends there when a reviewer raised something that belonged to the plan but not to the phase it came up on. It is the one part of the plan written by execution rather than planning, and it is where the answer to "what else should this plan do" usually already is. Propose phases for what deserves them, say plainly what you would leave, and tick an entry with the phase that now covers it. Never delete one silently.
- **Never renumber phases.** Append, or subdivide into `3a`/`3b`.
- **Add the For the driver section if the plan predates it**, verbatim from the template, between the title paragraph and the table.
- **Never edit a `Merged` row.** It's a record of what shipped; editing it makes the plan disagree with history.
- **Don't touch Driver State** beyond what you were asked to change. A driver may be live, and `Driver-ID`, `Driver-Host` and `Heartbeat` are its lock.
- Re-run detection if the repo set changed.

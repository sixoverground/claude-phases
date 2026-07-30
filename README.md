# claude-phases

Break work into phases. Let a Claude Code session build them one PR at a time — and steer the whole thing from your phone.

```
   docs/plans/my-app.md              a Claude Code cloud session              GitHub
  ┌──────────────────────┐          ┌────────────────────────┐          ┌──────────────┐
  │ Phase 0  Merged      │          │  reconcile             │          │  PR #12  ✓   │
  │ Phase 1  Merged      │◀────────▶│  implement             │◀────────▶│  PR #14  ✓   │
  │ Phase 2  In Review   │  status  │  open PR, watch        │  webhook │  PR #17  ⋯   │
  │ Phase 3  Pending     │  writes  │  fix CI, answer review │  events  │              │
  │ Driver: running      │          │  merge when green      │          │              │
  └──────────────────────┘          └───────────┬────────────┘          └──────────────┘
                                                │
                                          "run the next phase"
                                          "status"  "yolo off"
                                                │
                                         📱 Claude mobile app
```

## Quick start

**1. Install the skills.** Upload both `skills/phase-planner/` and `skills/phase-driver/` from this repo in your claude.ai skills settings. Account-level skills appear in every Claude Code **cloud** session automatically — including sessions started from your phone — with nothing added to your own repos. (Using the local CLI instead? See [Install — the other ways](#install--the-other-ways).)

**2. Write a plan.** Open a Claude Code session on your repo and say:

> plan a project

It asks what you're building, inspects the repo to work out your CI and review setup, and writes `docs/plans/<project>.md`.

**3. Build it.** Say:

> run the next phase

It implements the first phase, opens a PR, and waits. Fixes CI if it breaks. Answers review comments. Merges when the gates pass, then starts the next phase.

**4. Steer it from anywhere.** `status`, `why`, `pause`, `yolo off`, `skip phase 3`, `merge now`.

That's the whole loop. The rest of this README explains why it's built the way it is — worth reading before you trust it with a real project, but not before your first one.

---

## The problem

Long-running agent work needs somewhere durable to keep its place. A cloud session's container gets reclaimed, its context compacts, and it can die between opening a PR and recording that it did.

So the plan file *is* the state. A session that remembers nothing can read `docs/plans/my-app.md`, look at GitHub, work out exactly what happened, and carry on. That's the whole design, and everything else follows from it.

The second problem is control. Scheduled routines aren't visible in the Claude mobile app, so if a phase wedges while you're away from your desk, you wait. A regular cloud session *is* visible — you can message it, and it can message you.

## How it works

1. **Plan.** `phase-planner` inspects your repos, proposes configuration from what it finds, and writes `docs/plans/<project>.md` — a table of phases, one PR each.
2. **Run.** Tell a Claude Code session "run the next phase". `phase-driver` picks the first `Pending` phase, branches, implements it, verifies it, and opens a PR.
3. **Watch.** It subscribes to the PR and sleeps. CI failures and review comments wake it; it fixes them and pushes.
4. **Merge.** With YOLO on, when the gates pass it squash-merges and deletes the branch. With YOLO off it pings you and waits while you merge from your phone — and merges nothing, deletes nothing.
5. **Continue.** Either way, the merge advances the plan and the next phase starts. Repeat until done.

At any point, from anywhere: `status`, `why`, `pause`, `yolo off`, `skip phase 4`, `smaller`, `merge now`.

## The merge gate

Nothing merges until every gate passes. Each one is configurable, and each has an explicit off switch — "no CI" and "no bot reviewer" are supported setups, not degraded ones.

| Gate | Passes when |
|---|---|
| Not a draft | The PR isn't a draft |
| No blocking label | No `do-not-merge` / `wip` / `blocked` |
| Checks green | Every counted check concluded `success`, `skipped`, or `neutral`. Zero checks **blocks** unless you opt out |
| No changes requested | No reviewer's latest review is `CHANGES_REQUESTED` |
| Threads resolved | Every review thread is resolved |
| Reviewer saw *this* commit | Required reviewers evaluated the current head, not an older push |

That last one is the subtle one. A reviewer's approval of an earlier commit says nothing about the code you're about to merge, so proof is anchored to the head SHA — and it asks only whether the reviewer *looked*, not what it concluded. Whether findings were addressed is the threads gate; whether the review check itself must be green is the checks gate. Keeping those three apart is what lets one set of rules work for reviewers that signal findings by failing and reviewers that never fail by design.

## YOLO

One switch, one meaning: **who presses merge.**

- **On** — the driver merges once the gates pass, then starts the next phase.
- **Off** — the driver does everything else (fixes CI, answers review comments, resolves threads, checks the gates), then pings you with the PR link and waits.

**The next phase always continues after a merge, either way.** Merge from the GitHub app with YOLO off and the driver notices and moves on. Turning it off gives you a review checkpoint, not a manual pipeline.

Flip it any time — `yolo on` / `yolo off` — including with a PR already open.

It also decides where **UAT checklists** land. Off, every PR carries its own phase's manual-test steps, because you're there to read them. On, phases merge unattended and UAT is deferred to a single script at the end. Toggle mid-plan and nothing is lost — the driver tracks which phases nobody has verified and hands you the backlog with the next PR you're asked to merge.

## What a YOLO run looks like

The shape the whole design is aiming at:

> Kick off a phased plan with YOLO on. Each phase opens a PR, clears CI, squash-merges into the target branch, and deletes its branch. That repeats to the last phase. What you're left with is **one clean PR against your default branch, with a UAT checklist ready to run.**

Blockers don't break that, they interrupt it. When the driver can't get a phase green on its own it hands you *that* PR — one phase, small, with the failure explained. You resolve it, and the moment CI clears the run continues unattended to the next blocker or to the end. You are the exception handler, not a step in the loop.

Two consequences worth naming, because they follow from this and not from taste:

- **Branches are deleted as they merge**, so a branch that still exists means work that hasn't landed. That is only a useful signal if it holds without exception.
- **UAT accumulates rather than arriving per-phase.** A checklist on a PR the driver merges two minutes later isn't a prompt, it's a filing. It goes on the one PR you actually have to decide about.

## Finishing

Phases normally target a feature branch, so nothing reaches `main` until the feature is whole. When the last one merges **under YOLO**, the driver opens an **integration PR** from that branch to your default branch — what shipped phase by phase, what was deliberately left out, what setup the feature needs — and **never merges it, even with YOLO on.** YOLO is about phase PRs the driver built and verified; this one is the whole feature landing on the branch everything else builds on.

That PR is also where the UAT goes, and it arrives as **one comprehensive test script** — ordered so you can run it top to bottom, deduplicated, with later phases' corrections folded into the steps they supersede. Not a per-phase changelog with checkboxes: which phase produced which step is an artifact of how the work was built, not of how you verify it.

It is also the first thing in the entire plan a human has to act on, which makes it the only place a checklist actually asks anyone to do something.

With YOLO **off** none of this happens, and shouldn't: you merged every phase yourself and read each checklist as it came, so you already know where the branch stands. The handoff exists because YOLO means nobody was watching.

## Multi-repo

A project can span a web app, an iOS app, and an Android app. One plan file in the home repo covers all of them, and one session drives all of them.

**Independent repos run concurrently.** Only declared dependencies serialize anything — Android never waits on iOS. Phases stay sequential *within* a repo.

```markdown
| PR | Branch              | Repo              | Scope         | Phase | Status    | Link | Depends |
|----|---------------------|-------------------|---------------|-------|-----------|------|---------|
| 2  | claude/auth-api     | acme/acme-web     | Endpoints     | 1     | Merged    | #14  |         |
| 3  | claude/auth-ios     | acme/acme-ios     | Sign-in       | 2     | In Review | #17  | 1       |
| 4  | claude/auth-android | acme/acme-android | Sign-in       | 3     | In Review | #9   | 1       |
| 5  | claude/cutover      | acme/acme-web     | Retire legacy | 4     | Pending   | -    | 2,3     |
```

There is no atomic cross-repo merge — three PRs can't land as one transaction. If platforms must ship together, express it as a dependency plus an explicit cutover phase.

## Bring your own everything

The only assumptions are **GitHub** and **Claude Code**.

CI is modeled as three separable capabilities rather than a list of vendors, so a setup nobody anticipated still works:

- **Observe** — universal. Every CI that integrates with GitHub reports check runs on the commit, so the merge gate reads Actions, Xcode Cloud, CircleCI, Buildkite, and Jenkins identically.
- **Dispatch** — optional. GitHub Actions can be triggered on demand; everything else starts on its own conditions, or on a push.
- **Read logs** — tiered. Actions gives real failure text; other providers give a check summary and a link. When that isn't enough to diagnose a failure, the driver says so and links out instead of guessing.

Same for review: Copilot, a Claude review workflow, humans only, several at once, or nobody.

See [docs/configuration.md](docs/configuration.md), and [profiles/](profiles/) for copy-paste starting points.

## Where tests run

Running tests in the session is preferred — the loop is seconds instead of a CI round-trip. It isn't always possible, so `verify` is per repo and defaults to `auto`: try locally, fall back to CI, **and record which path actually ran in the PR body.**

Web and backend code runs locally. Android runs its JVM unit tests locally and leaves instrumented tests to CI. iOS is CI-only — building needs macOS and Xcode, which no Linux container has.

## Install — the other ways

The [quick start](#quick-start) covers the account-level install, which is the one to use. These are the alternatives.

### Why account-level is the one that matters

A cloud session started from the mobile app arrives with account skills already present, so driving a plan from your phone needs no setup in the repo you're driving. The other two options below don't have that property.

### For the local CLI

```bash
git clone https://github.com/sixoverground/claude-phases
mkdir -p ~/.claude/skills
cp -r claude-phases/skills/* ~/.claude/skills/
```

### For one project only

Copy the same directories into `.claude/skills/` in the repo. Note that many projects gitignore `.claude/`, in which case this won't survive a fresh clone — prefer the account-level install.

### Then

1. Open a Claude Code session on your repo and say **"plan a project"** — `phase-planner` will interview you, inspect the repo, and write `docs/plans/<project>.md`.
2. Work through [the hygiene checklist](skills/phase-planner/references/hygiene.md) it gives you.
3. Say **"run the next phase"**. From anywhere, including your phone.

## Status

Working, and built with its own phased plan — every commit here arrived through the loop described above.

- [x] Plan format and configuration spec
- [x] `phase-driver` skill
- [x] `phase-planner` skill
- [x] Examples, profiles, and install instructions

Not yet done: the skills have been written and reviewed but never run end to end against a repo other than this one. Treat the first plan you drive as a test.

## Documentation

- [Plan file format](docs/format.md) — structure, status vocabulary, recovery
- [Configuration](docs/configuration.md) — every key, its default, and its off switch
- [Reviewer setup](docs/review-setup.md) — managed Code Review, Actions, Copilot, or none
- [Design notes](docs/design.md) — why the rules are what they are, and what a green check doesn't tell you
- [Examples](examples/) — a two-phase single repo, and a four-repo cross-platform plan
- [Profiles](profiles/) — copy-paste config for common CI and review setups

## Related

[claude-project-manager](https://github.com/sixoverground/claude-project-manager) runs the same idea from a macOS launchd job, firing a scheduled routine per phase. It's the right tool when you're at your desk and want the loop outside the model. This one puts the loop inside a session you can talk to.

## License

MIT

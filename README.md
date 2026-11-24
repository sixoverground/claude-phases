# claude-phases

Plan a large change as a series of small pull requests, then let a Claude Code session build and drive them one at a time. You can monitor, pause, or redirect the work from any Claude client, including your phone.

```
   docs/plans/my-app.md              a Claude Code session               GitHub or GitLab
  ┌──────────────────────┐          ┌────────────────────────┐          ┌──────────────┐
  │ Phase 0  Merged      │          │  reconcile             │          │  PR #12  ✓   │
  │ Phase 1  Merged      │◀────────▶│  implement             │◀────────▶│  PR #14  ✓   │
  │ Phase 2  In Review   │  status  │  open PR, watch        │  webhook │  PR #17  ⋯   │
  │ Phase 3  Pending     │  writes  │  fix CI, answer review │  or      │              │
  │ Driver: running      │          │  merge when green      │  watcher │              │
  └──────────────────────┘          └───────────┬────────────┘          └──────────────┘
                                                │
                                          "run the next phase"
                                          "status"  "yolo off"
                                                │
                                         📱 Claude mobile app
```

In a cloud session, webhook events wake the driver. In a session on your own machine, a watcher it runs itself does the same job. See [Running locally](#running-locally).

## Quick start

You need a Claude Code session and a repository on GitHub, or a project on GitLab, where it can create branches and pull requests (GitLab calls them merge requests). On GitLab, read [Running locally](docs/running-locally.md) and [GitLab with a local Codex review](docs/review-setup.md#gitlab-with-a-local-codex-review) first: the session usually runs on your own Mac, and review runs as a CI job on a runner you own.

**1. Install the plugin.**

```
/plugin marketplace add sixoverground/claude-phases
/plugin install claude-phases@sixoverground
```

Both skills arrive together, and `/plugin marketplace update` picks up new versions. Other install routes, including account-level skills for cloud sessions started from your phone, are in [Installing](#installing).

**2. Write a plan.** Open a Claude Code session on your repo and say:

> plan a project

It asks what you're building, inspects the repository to understand its CI and review setup, and writes `docs/plans/<project>.md`.

**3. Build it.** Say:

> run the next phase

It implements the first phase, opens a PR, and waits. When CI fails or a reviewer comments, the session wakes, responds, and pushes a fix. Once the merge gates pass, it merges or asks you to merge, then starts the next phase.

**4. Steer it from anywhere.** `status`, `why`, `pause`, `yolo off`, `skip phase 3`, `merge now`.

That is the loop. Start with YOLO off while you learn how the driver behaves in your repository. Read [Security](SECURITY.md) before allowing unattended merges.

---

## What this project is

`claude-phases` is a plugin containing two skills. It is not a background service or a separate workflow engine.

- **`phase-planner`** turns a project into a dependency-aware sequence of PR-sized phases.
- **`phase-driver`** implements those phases and coordinates their branches, checks, reviews, and merges.

The plugin uses a Markdown plan in your repository as its durable state and the forge, GitHub or GitLab, as its view of the outside world. The skills themselves are instructions for Claude Code, so the session acts with the same repository permissions you gave it.

## Why the plan is the state

Long-running agent work needs somewhere durable to keep its place. A cloud session's container can be reclaimed, its context can compact, and the session can stop between opening a PR and recording that it did.

So the plan file *is* the state. A new session can read `docs/plans/my-app.md`, compare it with the forge, reconstruct what happened, and continue without relying on memory. Everything else in the design follows from that. The plan also points back at the driver skill, since a session that has lost the skill still has the plan, and the plan is where it will look.

A regular cloud session also remains conversational. You can ask what it is waiting for, pause it, change merge authority, or resolve a blocker without being at the machine where the run began.

## How it works

1. **Plan.** `phase-planner` inspects your repositories, proposes configuration from the evidence it finds, and writes `docs/plans/<project>.md`: a table with one PR-sized row per phase.
2. **Run.** Tell a Claude Code session "run the next phase". `phase-driver` picks the first `Pending` phase, branches, implements it, verifies it, and opens a PR.
3. **Watch.** It subscribes to the PR, or in a local session arms a watcher that polls it, and ends its turn. CI failures and review comments wake it; it fixes them and pushes.
4. **Merge.** With YOLO on, it squash-merges once the gates pass and deletes the branch. With YOLO off it pings you and waits while you merge from your phone, merging nothing and deleting nothing itself.
5. **Continue.** Either way, the merge advances the plan and the next phase starts. Repeat until done.

At any point, from anywhere: `status`, `why`, `pause`, `yolo off`, `skip phase 4`, `smaller`, `merge now`.

## The merge gate

The driver merges a phase PR only after every configured gate passes. Each gate has an explicit off switch, so repositories without CI or an automated reviewer can state that deliberately.

| Gate | Passes when |
|---|---|
| Not a draft | The PR or MR isn't a draft |
| No blocking label | No `do-not-merge` / `wip` / `blocked` |
| Checks green | Every counted check concluded `success`, `skipped`, or `neutral`: check runs on GitHub, the head pipeline's jobs and any external statuses on GitLab. Zero checks blocks unless you opt out |
| No changes requested | No reviewer's latest review requests changes. On GitLab this needs an instance that can record a request for changes; where it can't, the gate says it is off rather than passing |
| Threads resolved | Every review thread is resolved |
| Reviewer saw *this* commit | Required reviewers evaluated the current head, not an older push. On GitLab the proof is a review marker naming that head |

The final gate is the subtle one. Approval of an earlier commit does not cover code pushed later, so reviewer proof is anchored to the current head SHA. Three separate gates answer three separate questions:

- Did the reviewer evaluate this commit?
- Were its findings addressed?
- Must the review check itself be green?

That separation supports reviewers that report findings in different ways.

## YOLO

YOLO controls who presses the merge button. It does not disable CI or review gates.

- **On.** The driver merges once the gates pass, then starts the next phase.
- **Off.** The driver does everything else, then pings you with the PR link and waits.

The next phase continues after a merge either way. If you merge from GitHub with YOLO off, the driver notices and moves on. Turning YOLO off adds a human merge checkpoint without making you operate the rest of the pipeline.

Flip it any time with `yolo on` / `yolo off`, including with a PR already open.

It also decides where **UAT checklists** land. Off, every PR carries its own phase's manual-test steps, because you're there to read them. On, phases merge unattended and UAT is deferred to a single script at the end. Toggle mid-plan and nothing is lost: the driver tracks which phases nobody has verified and hands you the backlog with the next PR you're asked to merge.

## What a YOLO run looks like

A typical unattended run looks like this:

1. Each phase opens a PR against the target branch.
2. The driver clears CI and review findings.
3. It merges the phase and deletes the phase branch.
4. After the final phase, it opens one integration PR against the default branch with a UAT checklist.

Blockers interrupt that rather than breaking it. When the driver can't get a phase green on its own it hands you that PR: one phase, small, with the failure explained. You resolve it, and the moment CI clears the run continues unattended to the next blocker or to the end. You are the exception handler, not a step in the loop.

Two consequences follow from this rather than from taste:

- **Branches are deleted as they merge**, so a branch that still exists means work that hasn't landed. That signal is only useful if it holds without exception.
- **UAT accumulates rather than arriving per phase.** A checklist on a PR the driver merges two minutes later is filing, not a prompt. It goes on the one PR you actually have to decide about.

## Finishing

Phases normally target a feature branch, so nothing reaches `main` until the feature is whole. When the last one merges under YOLO, the driver opens an **integration PR** from that branch to your default branch, describing what shipped phase by phase, what was deliberately left out, and what setup the feature needs. It never merges that PR, even with YOLO on. YOLO covers phase PRs the driver built and verified; this one is the whole feature landing on the branch everything else builds on.

That PR is also where the UAT goes, and it arrives as one comprehensive test script, ordered so you can run it top to bottom, deduplicated, with later phases' corrections folded into the steps they supersede. Which phase produced which step is an artifact of how the work was built, not of how you verify it.

It is also the first thing in the entire plan a human has to act on, which makes it the only place a checklist asks anyone to do something.

With YOLO off none of this happens, and shouldn't. You merged every phase yourself and read each checklist as it came, so you already know where the branch stands. The handoff exists because YOLO means nobody was watching.

**Milestones** do the same thing part-way through. When a later phase needs earlier work released, deployed or installed, the plan carries a milestone row (`M1`) that depends on the phases it ships, and the later phase depends on the milestone. When those phases have merged, the driver runs the repo's release preparation on the feature branch, opens a PR to the default branch with the UAT so far, fixes its checks and answers its review, and leaves the merge to you, with YOLO on or off. After you merge, it brings the feature branch back in line and starts what was waiting. The integration PR above is the implicit final milestone of a plan that has no milestone rows. A plan that has them ships through them instead, and keeps its plan file on the default branch, since the feature branch is deleted and re-created at each one.

## Multi-repo

A project can span a web app, an iOS app, and an Android app. One plan file in the home repo covers all of them, and one session drives all of them.

Independent repos run concurrently. Only declared dependencies serialize anything, so Android never waits on iOS. Phases stay sequential within a repo.

```markdown
| PR | Branch              | Repo              | Scope         | Phase | Status    | Link | Depends |
|----|---------------------|-------------------|---------------|-------|-----------|------|---------|
| 2  | claude/auth-api     | acme/acme-web     | Endpoints     | 1     | Merged    | #14  |         |
| 3  | claude/auth-ios     | acme/acme-ios     | Sign-in       | 2     | In Review | #17  | 1       |
| 4  | claude/auth-android | acme/acme-android | Sign-in       | 3     | In Review | #9   | 1       |
| 5  | claude/cutover      | acme/acme-web     | Retire legacy | 4     | Pending   | -    | 2,3     |
```

There is no atomic cross-repo merge, because three PRs can't land as one transaction. If platforms must ship together, express it as a dependency plus an explicit cutover phase.

## Requirements and integrations

The required platforms are Claude Code and a forge: GitHub, or GitLab on gitlab.com or a self-managed instance. Languages, CI providers, review tools, and branch conventions are configurable.

**GitLab** is `forge: gitlab`, with `host` set for a self-managed instance. One plan has been driven end to end on gitlab.com, on the Free plan, with the driver, the reviewer and the maintainer on one account ([examples/gitlab-local.md](examples/gitlab-local.md)). **Still experimental**, because still untried: a self-managed instance, a token with the Developer role, a protected target branch, a reviewer on an identity of its own, and moving a feature branch back in line after a milestone. Expect a command to be wrong there, and report it. Review there runs as a CI job that posts the [review contract](docs/review-contract.md)'s marker; see [GitLab with a local Codex review](docs/review-setup.md#gitlab-with-a-local-codex-review).

CI is modelled as three separable capabilities rather than a list of vendors, so a setup nobody anticipated still works:

- **Observe.** Universal. Every CI that integrates with GitHub reports check runs on the commit, so the merge gate reads Actions, Xcode Cloud, CircleCI, Buildkite, and Jenkins identically. On GitLab it reads the jobs of the head's pipeline and any commit statuses an outside CI posts.
- **Dispatch.** Optional. GitHub Actions can be triggered on demand; everything else, GitLab CI included, starts on its own conditions, or on a push.
- **Read logs.** Tiered. Actions and GitLab jobs give real failure text. Other providers give a check summary and a link, and when that isn't enough to diagnose a failure the driver says so and links out instead of guessing.

Review works the same way: Copilot, Codex, a Claude review workflow, humans only, several at once, or nobody. On GitLab a reviewer runs as a CI job and proves its review with a marker note, as the [review contract](docs/review-contract.md) defines; [`codex-mr-review`](https://github.com/sixoverground/codex-mr-review) does that for Codex. The reviewer may post from your own account or from one of its own: either works, and [the reviewer setup](docs/review-setup.md#the-token-one-account-or-two-identities) says when to pick which.

See [the configuration reference](skills/phase-planner/references/configuration.md), and [profiles/](profiles/) for copy-paste starting points.

## Where tests run

Running tests in the session is fastest, but it is not always possible. The per-repository `verify` setting defaults to `auto`: try locally, fall back to CI, and record in the PR body which path actually ran.

Web and backend code runs locally. Android runs its JVM unit tests locally and leaves instrumented tests to CI. A cloud session leaves iOS to CI, because building needs macOS and Xcode, which no Linux container has. When the session runs on a Mac with Xcode, iOS is `local`: a quick build for the simulator before each push, with the full test suite left to CI.

## Running locally

The driver can run in a Claude Code session in a terminal on your own Mac instead of in the cloud: for a forge only your machine can reach, such as a self-managed GitLab behind a VPN, or a toolchain only your machine has, such as Xcode. It arms a watcher where a cloud session would get webhooks, keeps working on a claimed phase while the VPN is down, can run the reviewer locally before each push, and you can still steer it from your phone with Remote Control. Keeping the session alive is then your job. [docs/running-locally.md](docs/running-locally.md) covers all of it.

## Installing

### As a plugin

The [quick start](#quick-start) route. Both skills install together and update together. This is also the route for a local session in a terminal: install it where the session runs, since a cloud session does not load plugins installed on your Mac, and a running session keeps the version it loaded until it reloads or restarts.

```
/plugin marketplace add sixoverground/claude-phases
/plugin install claude-phases@sixoverground
```

### As account-level skills

Account skills are present in every Claude Code **cloud** session automatically, including sessions started from the mobile app, with nothing added to the repo you're driving. That property is the reason to choose this route: driving a plan from your phone needs no setup in the target repo.

The uploader takes one zip per skill, so there are two of them. Download `phase-planner.zip` and `phase-driver.zip` from the [latest release](https://github.com/sixoverground/claude-phases/releases/latest), then in claude.ai go to **Settings → Capabilities → Skills → Upload skill** and upload each file.

To build the zips yourself from a clone, or from a branch that isn't released yet:

```bash
scripts/package-skills.sh          # writes dist/phase-planner.zip and dist/phase-driver.zip
```

Uploading a skill whose name already exists replaces it, which is also how you update: download the new zips and upload them again.

### As local skills

```bash
git clone https://github.com/sixoverground/claude-phases
mkdir -p ~/.claude/skills
cp -r claude-phases/skills/* ~/.claude/skills/
```

Or copy the same directories into `.claude/skills/` in one repo. Many projects gitignore `.claude/`, in which case that copy won't survive a fresh clone.

### Start a project

1. Open a Claude Code session on your repo and say **"plan a project"**. `phase-planner` will interview you, inspect the repo, and write `docs/plans/<project>.md`.
2. Work through [the hygiene checklist](skills/phase-planner/references/hygiene.md) it gives you.
3. Say **"run the next phase"**, from anywhere, including your phone.

## Project status

Working, and built with its own phased plan. Every commit here arrived through the loop described above.

- [x] Plan format and configuration spec
- [x] `phase-driver` skill
- [x] `phase-planner` skill
- [x] Examples, profiles, and install instructions
- [x] Driven a feature in repositories other than this one
- [x] GitLab: the driver, the planner, a local session with a watcher, and Codex reviewing in your own CI, driven end to end once on gitlab.com. See [The first GitLab run](docs/design.md#the-first-gitlab-run)

### First production run

A two-repo feature: Google Calendar sync between a Next.js backend and an iOS app. Eight phases, roughly twenty-four review rounds, three phases merged unattended with YOLO on, an integration PR at the end, merged to `main` and deployed to production.

That run validated the recovery model and exposed several limits:

- **The plan file did its job.** Sessions died and restarted repeatedly across two days. Recovery from a cold start worked every time, including twice mid-phase.
- **Review caught two blocking bugs that a green suite did not.** A cross-tenant write and a race that dropped a live webhook channel. Both were the same shape: code correct under an assumption nothing enforced.
- **Manual testing caught four more that review did not**, including a timezone bug that put every calendar event on the wrong day for anyone west of UTC. Phases merge on gates, and gates measure what CI and a reviewer can see. UAT is not a formality at the end of the plan; it is the first time anybody looks at the running feature.
- **Three portability problems came out of it**, all now in the planner and driver references: review workflows that can't diff against a non-default base, preview environments pinned to a branch the driver deletes, and remote-tracking refs that report stale SHAs after a container restart.

Treat the first plan you drive as a test, and read [SECURITY.md](SECURITY.md) before running it with YOLO on against anything public.

## Documentation

- [Plan file format](skills/phase-planner/references/format.md). Structure, status vocabulary, recovery.
- [Configuration](skills/phase-planner/references/configuration.md). Every key, its default, and its off switch.
- [Reviewer setup](docs/review-setup.md). Managed Code Review, Actions, Copilot, Codex on GitHub or on GitLab, or none.
- [Review contract](docs/review-contract.md). What a reviewer you build must post for the merge gate to read it.
- [Running locally](docs/running-locally.md). Driving a plan from a terminal on your own Mac, with a watcher instead of webhooks.
- [Design notes](docs/design.md). Why the rules are what they are, and what a green check doesn't tell you.
- [Examples](examples/). A two-phase single repo, a four-repo cross-platform plan, a feature-branch plan with a milestone, and the plan from the first GitLab run with an account of every wake.
- [Profiles](profiles/). Copy-paste config for common CI and review setups.
- [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md).

The first two are the spec, and they live inside `phase-planner` rather than in `docs/` because an installed skill is a zip of its own directory and can't read this repo. They're written to be read on their own.

## Field Report

[I Let Claude Merge 38 PRs. Here’s What Broke.](https://www.craigphares.com/i-let-claude-merge-38-prs-heres-what-broke/)

A real-world experience using claude-phases, and how that influenced PR auto-merge design decisions.

## Related

[claude-project-manager](https://github.com/sixoverground/claude-project-manager) runs the same idea, and both can now run on your Mac. The difference is where the loop lives. cpm keeps it outside the model: a launchd job polls GitHub and fires a Claude Code routine per phase, and each routine starts fresh. claude-phases keeps it inside one session you can talk to, which watches its own change requests with a watcher it runs as one of its tools, and can be asked what it is waiting on at any point.

## License

MIT. See [LICENSE](LICENSE).

This is an independent project. It is not affiliated with, endorsed by, or sponsored by Anthropic. "Claude" is a trademark of Anthropic, PBC.

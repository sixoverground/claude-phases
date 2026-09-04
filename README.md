# claude-phases

Plan a large change as a series of small pull requests, then let a Claude Code session build and drive them one at a time. You can monitor, pause, or redirect the work from any Claude client, including your phone.

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

You need a GitHub repository and a Claude Code session with permission to create branches and pull requests.

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

The plugin uses a Markdown plan in your repository as its durable state and GitHub as its view of the outside world. The skills themselves are instructions for Claude Code, so the session acts with the same repository permissions you gave it.

## Why the plan is the state

Long-running agent work needs somewhere durable to keep its place. A cloud session's container can be reclaimed, its context can compact, and the session can stop between opening a PR and recording that it did.

So the plan file *is* the state. A new session can read `docs/plans/my-app.md`, compare it with GitHub, reconstruct what happened, and continue without relying on memory. Everything else in the design follows from that.

A regular cloud session also remains conversational. You can ask what it is waiting for, pause it, change merge authority, or resolve a blocker without being at the machine where the run began.

## How it works

1. **Plan.** `phase-planner` inspects your repositories, proposes configuration from the evidence it finds, and writes `docs/plans/<project>.md`: a table with one PR-sized row per phase.
2. **Run.** Tell a Claude Code session "run the next phase". `phase-driver` picks the first `Pending` phase, branches, implements it, verifies it, and opens a PR.
3. **Watch.** It subscribes to the PR and ends its turn. CI failures and review comments wake it; it fixes them and pushes.
4. **Merge.** With YOLO on, it squash-merges once the gates pass and deletes the branch. With YOLO off it pings you and waits while you merge from your phone, merging nothing and deleting nothing itself.
5. **Continue.** Either way, the merge advances the plan and the next phase starts. Repeat until done.

At any point, from anywhere: `status`, `why`, `pause`, `yolo off`, `skip phase 4`, `smaller`, `merge now`.

## The merge gate

The driver merges a phase PR only after every configured gate passes. Each gate has an explicit off switch, so repositories without CI or an automated reviewer can state that deliberately.

| Gate | Passes when |
|---|---|
| Not a draft | The PR isn't a draft |
| No blocking label | No `do-not-merge` / `wip` / `blocked` |
| Checks green | Every counted check concluded `success`, `skipped`, or `neutral`. Zero checks blocks unless you opt out |
| No changes requested | No reviewer's latest review is `CHANGES_REQUESTED` |
| Threads resolved | Every review thread is resolved |
| Reviewer saw *this* commit | Required reviewers evaluated the current head, not an older push |

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

The only required platforms are GitHub and Claude Code. Languages, CI providers, review tools, and branch conventions are configurable.

CI is modelled as three separable capabilities rather than a list of vendors, so a setup nobody anticipated still works:

- **Observe.** Universal. Every CI that integrates with GitHub reports check runs on the commit, so the merge gate reads Actions, Xcode Cloud, CircleCI, Buildkite, and Jenkins identically.
- **Dispatch.** Optional. GitHub Actions can be triggered on demand; everything else starts on its own conditions, or on a push.
- **Read logs.** Tiered. Actions gives real failure text. Other providers give a check summary and a link, and when that isn't enough to diagnose a failure the driver says so and links out instead of guessing.

Review works the same way: Copilot, a Claude review workflow, humans only, several at once, or nobody.

See [the configuration reference](skills/phase-planner/references/configuration.md), and [profiles/](profiles/) for copy-paste starting points.

## Where tests run

Running tests in the session is fastest, but it is not always possible. The per-repository `verify` setting defaults to `auto`: try locally, fall back to CI, and record in the PR body which path actually ran.

Web and backend code runs locally. Android runs its JVM unit tests locally and leaves instrumented tests to CI. iOS is CI-only, because building needs macOS and Xcode, which no Linux container has.

## Installing

### As a plugin

The [quick start](#quick-start) route. Both skills install together and update together.

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
- [Reviewer setup](docs/review-setup.md). Managed Code Review, Actions, Copilot, or none.
- [Design notes](docs/design.md). Why the rules are what they are, and what a green check doesn't tell you.
- [Examples](examples/). A two-phase single repo, and a four-repo cross-platform plan.
- [Profiles](profiles/). Copy-paste config for common CI and review setups.
- [Contributing](CONTRIBUTING.md) and [Security](SECURITY.md).

The first two are the spec, and they live inside `phase-planner` rather than in `docs/` because an installed skill is a zip of its own directory and can't read this repo. They're written to be read on their own.

## Field Report

[I Let Claude Merge 38 PRs. Here’s What Broke.](https://www.craigphares.com/i-let-claude-merge-38-prs-heres-what-broke/)

A real-world experience using claude-phases, and how that influenced PR auto-merge design decisions.

## Related

[claude-project-manager](https://github.com/sixoverground/claude-project-manager) runs the same idea from a macOS launchd job, firing a scheduled routine per phase. It suits being at your desk with the loop outside the model. This one puts the loop inside a session you can talk to.

## License

MIT. See [LICENSE](LICENSE).

This is an independent project. It is not affiliated with, endorsed by, or sponsored by Anthropic. "Claude" is a trademark of Anthropic, PBC.

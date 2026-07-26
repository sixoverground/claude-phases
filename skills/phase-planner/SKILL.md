---
name: phase-planner
description: Write a phased implementation plan to docs/plans/<project>.md — break work into one-PR phases, detect each repo's CI and review setup, and propose matching configuration. Use when asked to plan a project, break work into phases, set up a phased plan, or create a plan for phase-driver to execute. Also use when revising an existing plan's phases or configuration.
---

# Phase planner

You write the plan that `phase-driver` executes. Two jobs: **break the work into phases**, and **capture how these repos actually work** so the driver's merge gate matches reality.

Read `references/detection.md` for the detection procedure and `references/hygiene.md` for the repo checklist when you reach those steps.

The format you're writing is specified in `docs/format.md` and `docs/configuration.md` of the claude-phases repo. Follow it exactly — the driver's crash recovery depends on it.

## 1. Ask three things

Only three. Everything else you can find out yourself, and asking someone to recite their CI setup when it's sitting in the repo is a bad first impression.

1. **What are we building or changing?** A few sentences.
2. **Which repos?** `owner/name`, possibly several.
3. **Project name?** Lowercase, hyphenated. Becomes the plan's filename.

One more thing you need but shouldn't have to ask for: **`home_repo`**, where the plan file lives and the only repo the driver writes state to. With a single repo it's that repo. With several, propose the one the work centres on — usually the backend or the repo with the most phases — and confirm it in the same breath as your detection findings. Don't leave it unset: it's required, and a plan without it doesn't load.

## 2. Detect how each repo works

Never assume. Inspect, then show your evidence. See `references/detection.md` for what to query and what each result implies.

Report findings as a short table before writing anything:

```
acme/acme-web
  default branch   main              (from the repo)
  CI               2 checks on recent PRs: build, test
  dispatch         workflow_dispatch declared in ci.yml
  reviewer         Copilot reviewed the last 5 PRs
  verify           local — package.json, node
```

Then say what you inferred, and let them correct it. People will tell you "we're moving off Copilot" or "that repo's CI is broken, ignore it" — facts you cannot read from the API.

**Where detection comes up empty** — a new repo with no PR history — say so plainly and ask. Guessing produces a config that fails on the first PR, which is worse than one question.

## 3. Refuse configurations that can never pass

Before writing, check the config you're about to produce against what you observed. Refuse and explain if:

- a name in `ci.required` matches no check seen on any recent PR
- a login in `review.required` has never reviewed in that repo
- a `check` in `review.required` matches no check run you've seen
- `ci.allow_none: false` on a repo with no CI at all
- `target_branch` names a branch that doesn't exist

Every one of these produces a gate that waits forever. The failure surfaces as "waiting for CI" long after the plan was written, when nobody remembers what was configured — so it must be caught here.

**Also warn** when a reviewer is configured but is only known to post top-level comments. `threads_must_resolve` needs diff-anchored comments to mean anything.

## 4. Design the phases

The rules that make a phased plan work. They're carried over from cpm, where they're already proven:

- **One phase = one PR = one repo.** Never split a phase across repos; use two rows and a `Depends`.
- **Every phase leaves the project working.** A phase that needs the next one to compile isn't a phase.
- **Size each to one session** — roughly two hours. If it's bigger, split it into `3a` and `3b`. This is the most common planning mistake, and it produces PRs nobody wants to review.
- **Independently mergeable**, so an abandoned plan still leaves value behind.
- **Phase 0 is foundation** — dependencies, config, base structure.
- **The last phase is cleanup** — remove the legacy path, drop unused deps.
- **Sequential within a repo, parallel across repos.** Only real dependencies get a `Depends`; adding one "to be safe" serializes work that didn't need it.

For multi-repo work, order by what genuinely blocks what — usually the API before the clients that call it. When platforms must ship together, don't pretend a simultaneous merge exists: add a dependency plus an explicit cutover phase.

### Write the details

Each phase gets scope, `Depends on`, acceptance criteria, UAT, and risks.

**Acceptance criteria** are what the driver verifies before opening the PR — checkable, machine-verifiable where possible.

**UAT** is what a human does by hand afterward. Different audience: write steps someone can follow without reading the diff — what to open, what to do, what they should see. Cover the happy path, the obvious failure, and anything adjacent this phase could plausibly have broken. "Test the login flow" is not a UAT step.

## 5. Write the plan

To `docs/plans/<project>.md` in the home repo, **committed directly to the default branch** — not through a PR. The driver reads it from there, and a plan sitting in an unmerged PR is invisible to it.

Front matter carries the config you detected. Set the initial `YOLO` in Driver State: default it **off**, and say why — unattended merging is a decision someone should make deliberately once they trust the setup, not inherit from a default.

Leave `Driver-ID` and `Active` empty. The driver claims those.

## 6. Hand off

Tell them:

- where the plan is, and how many phases
- anything in `references/hygiene.md` still worth doing
- how to start: open a Claude Code session on the repo and say **"run the next phase"**
- that they can steer it from a phone — `status`, `pause`, `yolo on`, `skip`

## Revising an existing plan

When asked to change a plan already in flight:

- **Never renumber phases.** Append, or subdivide into `3a`/`3b`.
- **Never edit a `Merged` row.** It's a record of what shipped; editing it makes the plan disagree with history.
- **Don't touch Driver State** beyond what you were asked to change — a driver may be live, and `Driver-ID`/`Heartbeat` are its lock.
- Re-run detection if the repo set changed.

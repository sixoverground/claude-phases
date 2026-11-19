---
phases:
  project: milestone-demo
  home_repo: acme/widget-sdk
  # plan_branch is left at the default branch (main). A plan with milestone
  # rows may not live on a branch a milestone ships: feature/v2-client is
  # deleted when M1 merges, and the driver re-creates it from main.

  defaults:
    branch_prefix: claude/
    target_branch: feature/v2-client
    verify: local
    merge: { method: squash }
    ci:
      required: []
      allow_none: false
      dispatch: auto
      logs: actions
    review:
      required:
        - logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"]
      changes_requested_blocks: true
      threads_must_resolve: true
    stuck: { max_cycles: 5 }

  repos:
    acme/widget-sdk:
      milestone:
        prepare: >
          On the feature branch: raise `version` in package.json by a minor step
          above what main has (the "Version bumped" check reads it on PRs into
          main), and add one "## [<version>]" section at the top of CHANGELOG.md
          assembled from the changelog sentences in the shipped phases' PR
          bodies. Run `npm run release -- --dry-run` and do not open the PR
          unless it passes.
        after_merge: >
          Confirm the release workflow published the new version to npm, and
          say which version is live.

  max_concurrent: null
---

# milestone-demo

A feature-branch plan with one milestone. Phases 0 and 1 build a v2 client on `feature/v2-client`. Phase 2 migrates the example apps to it, and they install the SDK from npm, so the client has to be published first. Milestone `M1` ships phases 0 and 1 to `main`, which releases them; phase 2 depends on `M1` and waits for it. Copy this shape when a later phase needs earlier work released, deployed or installed.

## For the driver

This plan is executed by the `phase-driver` skill, and nothing in this file stands in for it. If you are acting on this plan and that skill is not in your context, because the session was compacted or was woken by a check-in or a webhook, invoke `phase-driver` before you do anything else, then reconcile. The rule a session without it most often drops: **a merge always advances the plan.** After any phase PR merges, start whatever it unblocks in the same turn unless `Driver: paused`, and when the last row merges, finish the plan by the skill's finishing steps rather than going idle.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1 | claude/v2-transport | acme/widget-sdk | Fetch-based transport with retries, behind the v1 API | 0 | Pending | - |  |
| 2 | claude/v2-client | acme/widget-sdk | `WidgetClient` v2 surface on the new transport, v1 kept as a shim | 1 | Pending | - | 0 |
| 3 | feature/v2-client | acme/widget-sdk | Ship the v2 client to `main` and release it | M1 | Pending | - | 0, 1 |
| 4 | claude/v2-examples | acme/widget-sdk | Move `examples/` to the published v2 client | 2 | Pending | - | M1 |
| 5 | feature/v2-client | acme/widget-sdk | Ship the migrated examples to `main` | M2 | Pending | - | 2 |

## Phase Details

### Phase 0 — v2 transport (acme/widget-sdk)

**Scope.** A fetch-based transport with retries and timeouts, used by the existing v1 client. No public API change.

**Depends on.** Nothing.

**Acceptance criteria.**
- [ ] v1 client calls go through the new transport
- [ ] Retries on 502, 503 and 504 with backoff; no retry on 4xx
- [ ] The existing test suite passes unchanged

**UAT.**
- [ ] Run an example app against staging; requests succeed as before
- [ ] Point it at a server that returns 503 twice then 200; the call succeeds

**Risks.** Retrying a non-idempotent POST. Only retry methods the server marks safe.

---

### Phase 1 — v2 client (acme/widget-sdk)

**Scope.** The `WidgetClient` v2 surface on the new transport. v1 stays as a thin shim over it.

**Depends on.** Phase 0.

**Acceptance criteria.**
- [ ] `WidgetClient` v2 is exported, with typed responses
- [ ] v1 calls are routed through v2 and their tests still pass
- [ ] README documents v2 and marks v1 deprecated

**UAT.**
- [ ] In a scratch project, install from the branch and list widgets with v2
- [ ] Call the same endpoint with v1; same result, with a deprecation warning

**Risks.** The v1 shim drifting from v1's real behaviour on edge cases.

---

### Milestone M1 — Release the v2 client (acme/widget-sdk)

**Ships.** Phases 0 and 1: the new transport and the v2 client.

**Review scope.** A finding on this PR is in scope when it falls within the scope of phases 0 and 1, taken together, or within what `milestone.prepare` produced. The driver answers it by its usual rules and commits fixes to `feature/v2-client`. Anything beyond those goes to Carried findings.

**Needed by.** Phase 2, whose example apps install the SDK from npm.

**UAT.**
- [ ] After merging, `npm view @acme/widget-sdk version` shows the new version
- [ ] A fresh project installs it and lists widgets with v2

**Risks.** The first publish of v2. The dry run in `prepare` is the control.

---

### Phase 2 — Migrate the examples (acme/widget-sdk)

**Scope.** Move every app under `examples/` to the published v2 client.

**Depends on.** M1, because the examples install the SDK from npm.

**Acceptance criteria.**
- [ ] Each example's `package.json` names the released version
- [ ] No example imports a v1 symbol

**UAT.**
- [ ] Run each example from a clean `npm install`; each one lists widgets

**Risks.** None known.

---

### Milestone M2 — Ship the migrated examples (acme/widget-sdk)

**Ships.** Phase 2.

**Review scope.** Phase 2's scope, or what `milestone.prepare` produced. Fixes go to `feature/v2-client`.

**Needed by.** The end of the plan. Without it, phase 2 would stay on the feature branch: a plan with milestone rows opens no implicit integration PR.

**UAT.**
- [ ] On `main`, run each example from a clean install

**Risks.** None known.

## Driver State

- Driver: idle
- YOLO: off
- Driver-ID: -
- Driver-Host: -
- Active: -
- UAT-pending: -
- Review-baselines: -
- Arbitrations: -
- Heartbeat: -
- Note: -

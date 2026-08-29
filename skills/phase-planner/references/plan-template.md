---
phases:
  project: PROJECT_NAME
  home_repo: OWNER/REPO
  # plan_branch: feature/x     # where the plan file lives; defaults to the
                               # home repo's default branch. Set it for
                               # feature-branch work, matching target_branch.

  defaults:
    branch_prefix: claude/
    target_branch: main
    verify: auto
    merge: { method: squash }
    ci:
      required: []
      allow_none: false
      dispatch: auto
      logs: auto
    review:
      required: []
      changes_requested_blocks: true
      threads_must_resolve: true
    stuck: { max_cycles: 5 }

  repos:
    OWNER/REPO: {}

  max_concurrent: null
---

# PROJECT_NAME

One paragraph: what this plan delivers, and how many phases it takes to get there.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1  | claude/foundation | OWNER/REPO | Dependencies, config, base structure | 0 | Pending | - |   |
| 2  | claude/SLUG       | OWNER/REPO | ...                                  | 1 | Pending | - |   |
| 3  | claude/cleanup    | OWNER/REPO | Remove the legacy path, final polish | 2 | Pending | - |   |

## Phase Details

### Phase 0 — Foundation (OWNER/REPO)

**Scope.** Dependencies, project config, and the base structure later phases build on.

**Depends on.** Nothing.

**Acceptance criteria.**
- [ ] The project builds
- [ ] The existing test suite still passes

**UAT.**
- [ ] Launch the app/service and confirm it starts cleanly

**Risks.** None known.

---

### Phase 1 — ... (OWNER/REPO)

**Scope.** ...

**Depends on.** Phase 0.

**Acceptance criteria.**
- [ ] ...

**UAT.**
- [ ] Steps a human follows by hand: what to open, what to do, what they should see

**Risks.** ...

---

### Phase 2 — Cleanup (OWNER/REPO)

**Scope.** Remove the legacy path, drop unused dependencies, final polish.

**Depends on.** Phase 1.

**Acceptance criteria.**
- [ ] No references to the legacy path remain
- [ ] The test suite passes

**UAT.**
- [ ] Walk the primary user flow end to end and confirm nothing regressed

**Risks.** None known.

## Carried findings

<!-- Appended by the driver when a review raises something that belongs to this
     plan but not to the phase it came up on. Delete this section if you'd
     rather it appear only once there's something in it. -->

## Driver State

- Driver: idle
- YOLO: on
- Driver-ID: -
- Active: -
- UAT-pending: -
- Heartbeat: -
- Note: -

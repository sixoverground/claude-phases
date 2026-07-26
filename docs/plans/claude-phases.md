---
phases:
  project: claude-phases
  home_repo: sixoverground/claude-phases

  defaults:
    branch_prefix: claude/
    target_branch: main
    verify: none                   # markdown and skill definitions; nothing to build yet
    merge: { method: squash }
    ci:
      required: []
      allow_none: true             # no CI configured in this repo yet
      dispatch: auto
      logs: auto
    review:
      required: []                 # no bot reviewer configured yet
      changes_requested_blocks: true
      threads_must_resolve: true
    stuck: { max_cycles: 5 }

  repos:
    sixoverground/claude-phases: {}

  max_concurrent: null
---

# claude-phases

Build claude-phases itself: a plan format plus two Claude skills that execute it. Four phases, each independently useful — the format is usable by hand after phase 0, and the driver works on its own after phase 1.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1 | claude/session-plan-format | sixoverground/claude-phases | Plan format spec, configuration reference, plan template, README | 0 | In Progress | - |  |
| 2 | claude/phase-driver-skill | sixoverground/claude-phases | `skills/phase-driver/` + recovery, gates, vocabulary references | 1 | Pending | - | 0 |
| 3 | claude/phase-planner-skill | sixoverground/claude-phases | `skills/phase-planner/` — detect setup, propose config, write plans | 2 | Pending | - | 1 |
| 4 | claude/examples-and-install | sixoverground/claude-phases | `examples/`, `profiles/`, install instructions, `docs/design.md` | 3 | Pending | - | 2 |

## Phase Details

### Phase 0 — Plan format spec (sixoverground/claude-phases)

**Scope.** The specification everything else implements: plan file structure, the status state machine, the recovery table, the full configuration reference, an empty plan template, and a README explaining the idea.

**Depends on.** Nothing.

**Acceptance criteria.**
- [x] `docs/format.md` specifies front matter, the PR Sequence Table, the status vocabulary and legal transitions, transition ordering, Driver State, and per-row recovery
- [x] `docs/configuration.md` documents every key, its default, and its off switch
- [x] `templates/plan.md.tmpl` is a valid empty plan
- [x] `README.md` explains the problem, the loop, the merge gate, YOLO, multi-repo, and CI generality
- [x] This plan file exists and describes the remaining phases

**Risks.** The format is load-bearing for every later phase; changing it after the driver ships means a migration. Worth over-specifying now.

---

### Phase 1 — phase-driver skill (sixoverground/claude-phases)

**Scope.** The skill that executes a plan: reconcile, start phases, open PRs, watch, fix CI, answer review, evaluate gates, merge, advance. Plus reference files for the recovery table, the gate definitions, and the phone vocabulary.

**Depends on.** Phase 0 — it implements that spec.

**Acceptance criteria.**
- [ ] `skills/phase-driver/SKILL.md` with a description tuned for phrases like "run the next phase" and "continue the plan"
- [ ] `references/recovery.md`, `references/gates.md`, `references/vocabulary.md`
- [ ] The reconcile step is specified precisely enough to be crash-safe per the recovery table
- [ ] Gate evaluation covers all six gates including head-anchored reviewer proof, and honours every off switch
- [ ] YOLO on and off are both specified, including that a merge always advances the plan
- [ ] Multi-repo: lazy `add_repo`, per-repo config resolution, concurrent rows, per-row stuck counters

**Risks.** SKILL.md length works against trigger reliability — keep the main file short and push detail into references.

---

### Phase 2 — phase-planner skill (sixoverground/claude-phases)

**Scope.** The skill that authors plans: detect each repo's real setup, propose configuration with its evidence, refuse configurations that can never pass, and write the plan file.

**Depends on.** Phase 1 — the planner writes what the driver reads, so the driver's expectations must be settled first.

**Acceptance criteria.**
- [ ] `skills/phase-planner/SKILL.md`
- [ ] Detection covers default branch, workflows and `workflow_dispatch`, check runs appearing on recent PRs, and who actually reviews
- [ ] Proposes config with evidence rather than interrogating the user
- [ ] Rejects deadlocking config before writing
- [ ] Includes the repo-hygiene checklist
- [ ] Phase-sizing rules carried over from cpm's `prompts/setup.md`

**Risks.** Detection on a repo with no PR history has nothing to go on; must degrade to asking.

---

### Phase 3 — Examples, profiles, install (sixoverground/claude-phases)

**Scope.** Everything needed by someone who didn't write this: a single-repo example, a cross-platform example, copy-paste config profiles, verified install instructions, and the design rationale.

**Depends on.** Phase 2.

**Acceptance criteria.**
- [ ] `examples/two-phase-demo.md` and `examples/cross-platform.md`
- [ ] `profiles/` fragments for Actions, Xcode Cloud, external CI, no CI, Copilot review, Claude review, humans only, no review
- [ ] README install section covering each verified install surface
- [ ] `docs/design.md` explaining why status lives on the default branch, why phase PRs never touch the plan, and the known failure modes

**Risks.** Install instructions depend on how third-party skills are distributed; verify against current docs rather than assuming.

## Driver State

- Driver: idle
- YOLO: off
- Driver-ID: -
- Active: -
- Heartbeat: -
- Note: YOLO starts off — this repo has no CI and no reviewer, so gates would pass vacuously

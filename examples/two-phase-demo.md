---
phases:
  project: two-phase-demo
  home_repo: acme/widget-api

  defaults:
    branch_prefix: claude/
    target_branch: main
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
    acme/widget-api: {}

  max_concurrent: null
---

# two-phase-demo

This is the smallest useful example: one repository, two sequential phases, local verification, CI, and Copilot review. Copy its structure for a simple project or use it to test a fresh installation end to end.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1 | claude/rate-limit-middleware | acme/widget-api | Token-bucket limiter behind a flag, off by default | 0 | Pending | - |  |
| 2 | claude/rate-limit-enable | acme/widget-api | Turn it on, add limits per route, remove the flag | 1 | Pending | - | 0 |

## Phase Details

### Phase 0 — Rate-limit middleware (acme/widget-api)

**Scope.** Add a token-bucket rate limiter as middleware, wired in but disabled by a config flag defaulting to off. No behavior change in production.

**Depends on.** Nothing.

**Acceptance criteria.**
- [ ] Middleware registered, controlled by `RATE_LIMIT_ENABLED`, defaulting off
- [ ] Unit tests cover: under limit, at limit, over limit, and bucket refill
- [ ] With the flag off, existing tests pass unchanged

**UAT.**
- [ ] Start the service with the flag off; a normal request succeeds as before
- [ ] Set the flag on locally, hammer one endpoint past the limit, confirm a 429 with a `Retry-After` header
- [ ] Wait for the bucket to refill; confirm requests succeed again

**Risks.** Middleware order matters. Registering after auth means unauthenticated floods aren't limited.

---

### Phase 1 — Enable rate limiting (acme/widget-api)

**Scope.** Turn the limiter on, set per-route limits, and remove the flag now that it's the only path.

**Depends on.** Phase 0.

**Acceptance criteria.**
- [ ] Per-route limits configured; defaults documented in the README
- [ ] `RATE_LIMIT_ENABLED` removed along with the disabled code path
- [ ] Tests cover at least one route with a non-default limit

**UAT.**
- [ ] Exceed the limit on a cheap endpoint; confirm 429 and that the response body is a useful error, not a stack trace
- [ ] Confirm an expensive endpoint has its lower limit and returns 429 sooner
- [ ] Confirm normal usage never trips the limit: click through the main flow at human speed
- [ ] Check logs: rate-limit rejections should be visible without being noisy

**Risks.** Limits set too low break real users, and it looks like an outage rather than a config error. Start generous.

## Driver State

- Driver: idle
- YOLO: off
- Driver-ID: -
- Active: -
- UAT-pending: -
- Heartbeat: -
- Note: -

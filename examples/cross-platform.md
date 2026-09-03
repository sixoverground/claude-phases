---
phases:
  project: acme-signin
  home_repo: acme/acme-web

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
      required:
        - logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"]
      changes_requested_blocks: true
      threads_must_resolve: true
    stuck: { max_cycles: 5 }

  repos:
    # Node app, Actions CI, Copilot review, inherits everything.
    acme/acme-web: {}

    # Xcode Cloud: starts on its own PR conditions, no Actions log API.
    # Claude review instead of Copilot. Ships from develop.
    acme/acme-ios:
      target_branch: develop
      verify: ci
      ci:
        required: ["Xcode Cloud - Build", "Xcode Cloud - Test"]
        dispatch: none
        logs: check-output
      review:
        required:
          - check: "Claude review"
            proof: completed

    # Gradle: JVM unit tests run locally, instrumented tests need CI.
    acme/acme-android:
      verify: auto
      ci:
        dispatch: "workflow:android-ci.yml"

    # Docs: nothing to build, nothing reviews it, never auto-merge.
    acme/acme-docs:
      verify: none
      ci: { allow_none: true }
      review: { required: [] }
      yolo: false

  max_concurrent: null
---

# acme-signin

This example replaces legacy sign-in with session tokens across web, iOS, and Android. Its six phases span four repositories with different CI, verification, review, and merge settings. It shows how those configurations coexist in one plan without provider-specific orchestration.

## PR Sequence

| PR | Branch | Repo | Scope | Phase | Status | Link | Depends |
|----|--------|------|-------|-------|--------|------|---------|
| 1 | claude/session-schema | acme/acme-web | Sessions table, migration, no callers yet | 0 | Pending | - |  |
| 2 | claude/session-endpoints | acme/acme-web | `POST /sessions`, `DELETE /sessions`, refresh | 1 | Pending | - | 0 |
| 3 | claude/signin-ios | acme/acme-ios | Sign-in screen, keychain persistence | 2 | Pending | - | 1 |
| 4 | claude/signin-android | acme/acme-android | Sign-in screen, encrypted prefs | 3 | Pending | - | 1 |
| 5 | claude/signin-docs | acme/acme-docs | Auth guide, migration notes | 4 | Pending | - | 1 |
| 6 | claude/retire-legacy-auth | acme/acme-web | Delete the old path, drop the dependency | 5 | Pending | - | 2,3,4 |

**Phases 2, 3, and 4 all depend only on phase 1**, so they run **concurrently** in three different repos as soon as the endpoints merge. Phase 5 is the cutover and waits for all three.

Every parallel row names its dependency explicitly. A blank `Depends` means *"the previous row"*, so leaving these blank would chain iOS behind web and Android behind iOS, creating exactly the serialization this plan is designed to avoid.

## Phase Details

### Phase 0 — Session schema (acme/acme-web)

**Scope.** Sessions table and migration. Nothing reads or writes it yet.

**Depends on.** Nothing.

**Acceptance criteria.**
- [ ] Migration applies cleanly and rolls back cleanly
- [ ] Existing test suite unaffected

**UAT.**
- [ ] Run the migration against a copy of production data; confirm it completes in acceptable time
- [ ] Roll it back; confirm no data loss in adjacent tables

**Risks.** A long-running migration on a large table can lock writes. Check the row count before running it in production.

---

### Phase 1 — Session endpoints (acme/acme-web)

**Scope.** `POST /sessions` to create, `DELETE /sessions` to revoke, and token refresh. Legacy auth still works.

**Depends on.** Phase 0.

**Acceptance criteria.**
- [ ] All three endpoints implemented with tests for success and failure paths
- [ ] Tokens expire; expired tokens return 401
- [ ] Legacy auth still passes its existing tests

**UAT.**
- [ ] Create a session with valid credentials via curl; confirm a token comes back
- [ ] Use the token on a protected endpoint; confirm success
- [ ] Revoke it; confirm the same token now returns 401
- [ ] Confirm an existing legacy client still works untouched

**Risks.** Both auth paths live simultaneously. A route that accepts either could let a revoked session through the legacy path.

---

### Phase 2 — Sign-in on iOS (acme/acme-ios)

**Scope.** Sign-in screen wired to `POST /sessions`, token in the keychain.

**Depends on.** Phase 1: the endpoint must exist.

**Acceptance criteria.**
- [ ] Valid credentials navigate to Home
- [ ] Invalid credentials show an inline error
- [ ] Token persisted to the keychain and reused on launch

**UAT.**
- [ ] Sign in on a physical device; land on Home
- [ ] Wrong password: error appears inline, the field keeps focus, nothing crashes
- [ ] Force-quit and reopen; still signed in
- [ ] Airplane mode: a network error appears rather than a spinner that never ends
- [ ] Sign out, then confirm relaunching does not restore the session

**Risks.** Keychain access on first launch needs an entitlement. `verify: ci` here. No Linux container can build this, so CI is the only verification before review.

---

### Phase 3 — Sign-in on Android (acme/acme-android)

**Scope.** Sign-in screen wired to `POST /sessions`, token in encrypted shared preferences.

**Depends on.** Phase 1. **Not** on phase 2. The platforms are independent and run at the same time.

**Acceptance criteria.**
- [ ] Valid credentials navigate to Home
- [ ] Invalid credentials show an inline error
- [ ] Token persisted to encrypted prefs and reused on launch

**UAT.**
- [ ] Sign in on a physical device; land on Home
- [ ] Wrong password: inline error, no crash
- [ ] Kill the app from recents and reopen; still signed in
- [ ] Rotate the device mid-sign-in; confirm no lost state or duplicate request
- [ ] Airplane mode: a network error, not a hang

**Risks.** `verify: auto`. JVM unit tests run in-session, instrumented tests only in CI, so device behavior is unverified until UAT.

---

### Phase 4 — Auth documentation (acme/acme-docs)

**Scope.** Document the new flow and write migration notes for API consumers.

**Depends on.** Phase 1.

**Acceptance criteria.**
- [ ] The new flow documented with request and response examples
- [ ] Migration notes cover the legacy path and its removal date

**UAT.**
- [ ] Follow the guide start to finish as a new integrator would; confirm the examples actually work when pasted

**Risks.** None. This repo is pinned `yolo: false`. Docs read by customers get a human look regardless of the global toggle.

---

### Phase 5 — Retire legacy auth (acme/acme-web)

**Scope.** Delete the legacy path, drop its dependency, remove the dual-auth branch.

**Depends on.** Phases 2, 3, and 4. Every client must be on sessions before the old path disappears.

**Acceptance criteria.**
- [ ] No references to the legacy module remain
- [ ] Dependency removed from the manifest
- [ ] Full test suite passes

**UAT.**
- [ ] Sign in on web, iOS, and Android after deploy; all three work
- [ ] Confirm a legacy client now fails with a clear error rather than a 500
- [ ] Watch error rates for an hour after deploy

**Risks.** This is the irreversible one. If any client is still on legacy auth, this breaks it in production. Confirm real traffic on the old path is zero before merging, not just that the phases merged.

## Driver State

- Driver: idle
- YOLO: off
- Driver-ID: -
- Active: -
- UAT-pending: -
- Heartbeat: -
- Note: -

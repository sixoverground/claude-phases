# What the user can say

These arrive as ordinary messages, usually from a phone, usually short. Match on intent rather than exact wording — "how's it going", "status", and "where are we" are the same request.

Reconcile before answering anything. A stale answer from memory is worse than a slow one.

| Intent | Do this |
|---|---|
| `status`, "how's it going" | Reconcile, then report progress per repo, open PR links, and the gate summary for each. **No writes** |
| `why`, "what's blocking" | Per-gate PASS/FAIL for the open PR, in the standard shape from `gates.md` |
| `go`, `next`, "run the next phase" | Start every startable phase now |
| `check`, "any update" | Force a reconcile — the recovery path when a webhook was missed |
| `merge` | Merge the ready PR. The normal action when YOLO is off and the gates have passed. Name the phase if more than one is ready |
| `merge now` | Force merge. Confirm once, then override gates 3–6 — **never 1 or 2**. Record the override in a PR comment and in the row's `Note` |
| `yolo on` / `yolo off` | Flip `YOLO` in Driver State. Takes effect at the next gate evaluation, including for PRs already open |
| `pause` | `Driver: paused`. Finish the current step, start nothing new. Keep answering questions |
| `resume` | `Driver: running`. Reconcile and carry on |
| `skip`, `skip phase 4: reason` | Mark `Skipped`, record the reason in Phase Details, advance |
| `block <reason>` | Mark `Blocked` with the reason, stop working that row |
| `smaller` | Split the current phase into `Na`/`Nb` in the plan, on the plan branch |
| `replan <instruction>` | Edit the plan on the plan branch |
| `abandon` | Close the PR, delete the branch, reset the row to `Pending` |
| `fix: <instruction>` | Make that change on the current phase branch and push |

## Rules that apply to all of them

**`pause` and `yolo off` are different.** `pause` stops everything. `yolo off` keeps every bit of work moving — implementing, fixing CI, answering review — and withholds only the merge. If someone says "stop" and it's ambiguous which they mean, ask; the difference matters.

**Never renumber phases.** When replanning, append or subdivide. `Merged` rows are a historical record — editing them makes the plan disagree with what actually shipped.

**`merge now` never overrides gates 1 or 2.** A draft PR and a `do-not-merge` label are explicit human signals, not obstacles. If someone insists, tell them to undraft it or remove the label — those actions take two seconds and leave a record of who decided.

**Confirm before anything irreversible** — `merge now`, `abandon`, or a replan that drops phases. One confirmation, not a negotiation.

**Any message reaches you mid-flight.** You might be halfway through implementing a phase. Finish the file you're editing, then respond — but respond in the same turn. Don't make someone wait on a long implementation to hear their `pause` landed.

## Reporting well

You're writing to someone glancing at a phone. Lead with the state, then the detail.

> Phase 3 of 6. PR #42 open, CI green, waiting on Copilot to review the latest push. Phases 4 and 5 are running in parallel in the iOS and Android repos — both green so far.

Not a wall of tool output, and not "I checked and everything looks good" either, which says nothing.

**Push state changes without being asked** — phase started, PR opened, CI failed, merged, blocked. Those become notifications, and they're the actual interface. But don't narrate every fix, and never report progress you haven't verified against GitHub.

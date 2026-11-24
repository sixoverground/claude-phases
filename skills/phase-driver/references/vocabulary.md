# What the user can say

These arrive as ordinary messages, usually from a phone, usually short. Match on intent rather than exact wording. "How's it going", "status", and "where are we" are the same request.

Reconcile before answering anything. A stale answer from memory is worse than a slow one.

| Intent | Do this |
|---|---|
| `status`, "how's it going" | Reconcile, then report progress per repo, open PR links, and the gate summary for each. List milestone rows with what each is waiting on: its dependencies, its preparation, its checks or review, or a person's merge. **No writes** |
| `why`, "what's blocking" | Per-gate PASS/FAIL for the open PR, in the standard shape from `gates.md` |
| `go`, `next`, "run the next phase" | Start every startable phase now |
| `check`, "any update" | Force a reconcile: the recovery path when a wake was missed |
| `merge` | Merge the ready PR. The normal action when YOLO is off and the gates have passed. Name the phase if more than one is ready |
| `merge now` | Force merge. Confirm once, then override gates 3–6: **never 1 or 2**. Record the override in a PR comment and in the row's `Note` |
| `yolo on` / `yolo off` | Flip `YOLO` in Driver State. Takes effect at the next gate evaluation, including for PRs already open |
| `pause` | `Driver: paused`. Finish the current step, start nothing new. Keep answering questions |
| `resume` | `Driver: running`. Reconcile and carry on |
| `take over`, "that driver is gone" | The person says the driver named in `Driver-ID` is no longer running. Reconcile read-only: the Driver-ID stop row does not end this turn, as SKILL.md's **Driver-ID** says, and nothing is written yet. Then confirm once, naming the holder's ID, its heartbeat's age, and from `Driver-Host` its host and whether that process is still running where you can tell. On yes, mint a new ID, write it with your own `Driver-Host`, and carry on as a stale-heartbeat takeover does. Never say it to yourself: only a person can vouch for a driver this session cannot see |
| `skip`, `skip phase 4: reason` | Mark `Skipped`, record the reason in Phase Details, advance |
| `block <reason>` | Mark `Blocked` with the reason, stop working that row |
| `continue`, "keep going" | **Only when a row is `Blocked` at a review-round stop.** Anywhere else it means carry on: reconcile, act on whatever you were waiting for, and write nothing. A baseline written after an arbitration but before the stop puts that arbitration outside the new budget, so the phase gets a second arbiter and a fresh `max_review_rounds` that nobody decided to give it. At a stop, clear it: add `<phase id>:<count>` to `Review-baselines` in Driver State with that phase's current reviewed-head count, set the row back to `In Review`, and carry on. Without that baseline the next wake re-derives the same count and blocks again. The new budget gets its own arbitration at its threshold. Name the phase if more than one is stopped. At a repo-rule stop with `review.required: []`, where the row stays `In Review` and waits on an answer, `continue` is that answer: post it on the PR as a comment quoting it, which is what clears that head's stop, and carry on. Where a person wants a fresh arbiter at that stop rather than more of the old budget, `arbitrate` is the word: it is `continue` with an arbitration, and it writes its baseline one lower for the reason this row's warning gives |
| `arbitrate`, "get a second opinion" | **A person asks for a fresh arbitration.** It applies only where `stuck.arbiter` is configured and `review.required` is not empty, and it means one of two things by where the row is. **At a review-round stop** (the row `Blocked` by SKILL.md's **Stop for a person**, after the arbiter's extra rounds), it is `continue` plus an arbitration at once. With the current reviewed-head count *C*, write `Review-baselines` as `<phase id>:<C - 1>` and `Arbitrations` as `<phase id>:<C>`, and set the row back to `In Review`, **all in one plan write**, then arbitrate as SKILL.md's **Arbitrate** says from step 2. The baseline sits one below *C* on purpose: an arbitration belongs to a budget only when its entry is above the baseline, so `continue`'s baseline at *C* would leave an entry at *C* outside the new budget and the next wake would arbitrate again. At *C* - 1 the effective count is 1, the entry is in the budget, and the budget table's last two rows take over. The earlier `Arbitrations` entry stays where it is; it is at most *C* minus `extra_rounds`, so never above the new baseline. With the defaults: arbitrated at 3, stopped at 6, `arbitrate` writes `<id>:5` and `<id>:6`, the arbitration answers head 6, heads 7 and 8 are answered under the new verdict, and head 9 stops. **Before the threshold, with no arbitration yet in this budget** (the row `In Review`), it is an early arbitration in the current budget: record `<phase id>:<derived count>` in `Arbitrations` exactly as the threshold one is, write nothing to `Review-baselines`, and arbitrate. It needs an effective count of at least 1; at 0 no head in this budget has been reviewed, so say so and write nothing. **Everywhere else write nothing and say why:** with an arbitration already in this budget, the arbiter runs once per budget, so link its verdict, say at which count the stop comes, and that `arbitrate` there starts a new budget; with `stuck.arbiter: null`, no arbiter is configured, and at a stop `continue` is the word; with `review.required: []`, no head is ever counted, so an arbitration's stop could never come; on a row `Blocked` for any other reason, `arbitrate` clears only a review-round stop. Name the phase if more than one could be meant. A milestone row works the same way, as in `M1:5` |
| `smaller` | Split the current phase into `Na`/`Nb` in the plan, on the plan branch |
| `replan <instruction>` | Edit the plan on the plan branch |
| `abandon` | Close the PR, delete the branch, reset the row to `Pending` |
| `fix: <instruction>` | Make that change on the current phase branch and push |

## Rules that apply to all of them

**`pause` and `yolo off` are different.** `pause` stops everything. `yolo off` keeps every bit of work moving, implementing, fixing CI, answering review, and withholds only the merge. If someone says "stop" and it's ambiguous which they mean, ask; the difference matters.

**Never renumber phases.** When replanning, append or subdivide. `Merged` rows are a historical record. Editing them makes the plan disagree with what actually shipped.

**`merge now` never overrides gates 1 or 2.** A draft PR and a `do-not-merge` label are explicit human signals, not obstacles. If someone insists, tell them to undraft it or remove the label. Those actions take two seconds and leave a record of who decided.

**`merge` and `merge now` never apply to a milestone PR.** A milestone row's PR is merged by a person, every time, whatever YOLO says. Answer that it is theirs to merge, link it, and give the gate summary so they can. If it is the only ready PR, say so rather than merging something else.

**Confirm before anything irreversible.** `Merge now`, `abandon`, or a replan that drops phases. One confirmation, not a negotiation.

**Any message reaches you mid-flight.** You might be halfway through implementing a phase. Finish the file you're editing, then respond, but respond in the same turn. Don't make someone wait on a long implementation to hear their `pause` landed.

## Reporting well

You're writing to someone glancing at a phone. Lead with the state, then the detail.

> Phase 3 of 6. PR #42 open, CI green, waiting on Copilot to review the latest push. Phases 4 and 5 are running in parallel in the iOS and Android repos, both green so far.

Not a wall of tool output, and not "I checked and everything looks good" either, which says nothing.

**Push state changes without being asked.** Phase started, PR opened, CI failed, merged, blocked. Those become notifications, and they're the actual interface. But don't narrate every fix, and never report progress you haven't verified against the forge.

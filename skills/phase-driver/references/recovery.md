# Recovery

What to do when the plan and GitHub disagree. That's the normal state after a session dies, not an error.

Apply this **per non-terminal row**, not once per plan. With several repos in flight, each recovers independently.

**GitHub is the truth.** The plan records what a driver intended; GitHub records what happened. Where they differ, fix the plan.

| Plan says | GitHub says | What happened | Do this |
|---|---|---|---|
| `Pending`, stale heartbeat | no branch, no PR | Never started | Start it normally |
| `Pending` | open PR on that branch | Died after opening the PR, before recording it | Adopt the PR: write `In Review` + `Link`, subscribe, evaluate the gate |
| `In Progress`, foreign ID, heartbeat < 90 min | anything | Another driver is live | Stop. Report. Touch nothing |
| `In Progress`, stale | no branch | Claimed, died before doing anything | Reset to `Pending`, then start it normally |
| `In Progress`, stale | branch exists, no PR | Died mid-implementation | See below |
| `In Progress` | open PR on that branch | Died after opening the PR, before recording it | Write `In Review` + `Link`, adopt |
| `In Review` | PR open | Normal operation | Re-subscribe, re-evaluate the gate against the current head |
| `In Review` | PR merged | Died between merging and recording it | Write `Merged`, then start whatever it unblocks |
| `In Review` | PR closed, not merged | A human killed it | Ask why. Default to `Blocked` if there's no answer |
| `In Review` | no PR at all, branch gone | Someone cleaned up. **Not** the driver's own post-merge delete: that only ever runs on a branch whose PR is merged, and a merged PR still exists to be found | Reset to `Pending` |
| `Blocked` | anything | Waiting on a human | Leave it. Only a user instruction clears `Blocked` |
| all rows `Merged`/`Skipped` | - | Complete | Go to SKILL.md §8 and apply it, including its fallback where no integration PR is due. Where one is, the only reason not to open it is that one is already open, so check rather than assume a previous driver got there. Then `Driver: idle`, summarize, stop |

## The plan branch is gone

If `plan_branch` names a branch that no longer exists, whether it was deleted after a feature merged, renamed, or never created, **stop and report.** Do not fall back to the default branch, and do not recreate the branch.

Both fallbacks look helpful and are worse than stopping. A plan read from the default branch shows every row `Pending`, so the driver would start the whole project again on top of work that already shipped. Recreating the branch from the default branch does the same thing with an audit trail that makes it look deliberate.

Tell the user which branch is missing and where the plan was last seen. Restoring a branch is seconds of work for someone who knows what happened, and unrecoverable guesswork for you.

## The awkward one: a branch with no PR

You can't tell from the plan whether the previous driver got most of the way through the phase or died on its first commit. Look at the actual diff against the phase's scope and acceptance criteria.

- **Substantially complete.** Finish it, verify, and open the PR. Say in the PR body that it was resumed from an interrupted session, so a reviewer knows to look a little harder.
- **Partial or incoherent.** Don't try to salvage it. Reset the row to `Pending`, delete the branch, and start clean. Half-finished work from a session you can't ask questions of is worth less than starting over.
- **Can't tell.** Ask. This is one of the few decisions worth a round trip.

## Adopting a PR you didn't open

Once adopted, treat it as yours: subscribe, evaluate the gate, fix CI, answer review. Don't re-implement anything already in the diff, and don't force-push over commits you didn't write.

If its head is far behind the base, update the branch before evaluating the gate. A gate result against a stale base is meaningless.

## Remote-tracking refs lie after a session restart

Read remote state with `git ls-remote origin refs/heads/<branch>`, not `git rev-parse origin/<branch>`.

A container that was reclaimed and restarted comes back with a fetch cache from before it died, so `origin/<branch>` can report a SHA several commits behind the real one and report it confidently. During one plan this happened three times, and once a `git reset --hard origin/<branch>` moved the working tree back to a state from before the previous phase merged. Nothing warned; the reset succeeded.

`git ls-remote` asks the server every time. Use it before any decision that depends on where a branch actually points: comparing a phase head, confirming a merge, or resetting anything. A plain `git fetch` first is fine too, but only if you remember it every time, and the failure when you forget is silent.

## Two rules that prevent most of the damage

**Never start a phase that has an open PR.** Duplicate branches for one phase are the most confusing state to unpick, and every recovery path above is written to avoid creating one. If in doubt, search the row's repo for open PRs by head branch before you create anything.

**Never mark `Merged` without confirming it in GitHub.** Being wrong here starts the next phase on a base that doesn't contain the previous one.

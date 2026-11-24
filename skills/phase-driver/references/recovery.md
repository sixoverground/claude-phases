# Recovery

What to do when the plan and the forge disagree. That's the normal state after a session dies, not an error.

Apply this **per non-terminal row**, not once per plan, plus every `Merged` milestone row that is not yet settled (see [Milestone rows](#milestone-rows)). With several repos in flight, each recovers independently.

**The forge is the truth.** The plan records what a driver intended; the forge records what happened. Where they differ, fix the plan.

| Plan says | The forge says | What happened | Do this |
|---|---|---|---|
| `Pending`, stale heartbeat | no branch, no PR | Never started | Start it normally |
| `Pending` | open PR on that branch | Died after opening the PR, before recording it | Adopt the PR: write `In Review` + `Link`, watch, evaluate the gate |
| `In Progress`, foreign ID, heartbeat < 90 min | anything | Another driver is live, or one died recently | Stop. Report. Touch nothing. Two ways out, both in SKILL.md's **Driver-ID**: its `Driver-Host` shows a dead process on this host, or a person says `take over` |
| `In Progress`, stale | no branch | Claimed, died before doing anything | Reset to `Pending`, then start it normally |
| `In Progress`, stale | branch exists, no PR | Died mid-implementation | See below |
| `In Progress` | open PR on that branch | Died after opening the PR, before recording it | Write `In Review` + `Link`, adopt |
| `In Review` | PR open | Normal operation | Re-arm the watch, re-evaluate the gate against the current head |
| `In Review` | PR merged | Died between merging and recording it | Write `Merged`, then start whatever it unblocks |
| `In Review` | PR closed, not merged | A human killed it | Ask why. Default to `Blocked` if there's no answer |
| `In Review` | no PR at all, branch gone | Someone cleaned up. **Not** the driver's own post-merge delete: that only ever runs on a branch whose PR is merged, and a merged PR still exists to be found | Reset to `Pending` |
| `Blocked` | anything | Waiting on a human | Leave it. Only a user instruction clears `Blocked` |
| all rows `Merged`/`Skipped` | - | Complete | Go to SKILL.md §8 and apply it, including its fallback where no integration PR is due. None is due in a repo whose resolved `integration_pr` is `false`: open nothing there, and send the cumulative UAT to the fallback when that leaves no integration PR to carry it. Where one is due, the only reason not to open it is that one is already open, so check rather than assume a previous driver got there. Then `Driver: idle`, summarize, stop |

## Milestone rows

Every milestone row in a repo has the same head and base, so a milestone row is matched to its PR by SKILL.md's **Which PR is a milestone's**: the row's `Link` where it has one, and otherwise head equal to the target branch, base equal to the release branch, **and a title starting `Milestone <id>:`** with this row's id. A PR naming another id is never this row's, not even a merged one from an earlier milestone. The same per-row rule applies: the forge is the truth.

| Plan says | The forge says | What happened | Do this |
|---|---|---|---|
| `Pending`, dependencies `Merged` or `Skipped` | no PR with this row's identity | Ready to ship | Start it, by SKILL.md's Milestones section |
| `Pending` or `In Progress`, dependencies `Merged` or `Skipped` | an open PR with this row's identity | Died after opening the PR, before recording it | Adopt it: write `In Review` and the `Link`. Do not prepare again if the preparation's commits are on the branch. A row with a dependency that is neither `Merged` nor `Skipped` never adopts a PR: report the mismatch |
| `In Progress`, stale | no PR, preparation partly on the branch | Died mid-preparation | Finish the preparation from where the branch stands, by comparing it with `milestone.prepare`, then open the PR |
| `In Review` | PR open | Normal operation | Work it, by Working a milestone PR. **Never merge** |
| `In Review` | PR merged | A person merged it | Write `Merged`, re-sync, run `milestone.after_merge`, start what it unblocks |
| `In Review` | PR closed, not merged | A person closed it | Ask why. Default to `Blocked` |
| `Merged`, not settled | the branch lacks the milestone PR's merge commit, or is gone, and rows still target it | Died between recording the merge and re-syncing | Re-sync before starting anything in that repo |
| `Merged`, not settled | branch re-synced, but no `<!-- phase-driver:after-merge <id> -->` comment on the PR while `after_merge` is set | Died between re-syncing and finishing `after_merge` | Run `after_merge`, post the marker, then start what it unblocks |

The `Merged` rows are why reconcile looks past terminal rows for milestones: a `Merged` milestone looks finished from the table alone, and its dependents would otherwise start on a stale or missing base.

`In Progress` with no PR and no preparation commits on the branch at all is the first row of the table in disguise: prepare from the start, then open the PR. Where `milestone.prepare` is absent there is nothing to finish, and the third row reduces to opening the PR.

The last row is why re-sync comes before anything starts in §7. A session that dies after writing `Merged` and before moving the branch leaves a target branch that is gone, or still at its pre-merge head, and a phase branched from either starts from a base that is not the release branch.

## The forge is unreachable

The forge did not answer at all: a DNS failure, a timeout, a refused connection, a gateway error. A VPN that dropped and a Mac that lost its Wi-Fi look like this. It is not the same as access denied, where the forge answered 401, 403 or 404, which marks the row `Blocked` as SKILL.md §3 says.

- **Mark nothing `Blocked`.** Nothing is wrong with any phase. A row blocked for an outage stays blocked after the outage, until a person clears it.
- **Do not count the wake toward `stuck.max_cycles`.** No gate was evaluated, so no gate failed.
- **Tell the user once**, not once per poll.
- **Keep watching, and quietly.** The watcher backs off to at most five minutes between polls, prints one line when the forge stops answering and one when it answers again, and prints no check-in in between. With no change request open, arm it with an empty list so the host's own line still wakes you. A Monitor expiry in the meantime is re-armed without a word to the user. Reconcile when it answers, as on any wake. See [When the forge stops answering](watching.md#when-the-forge-stops-answering).

**A status write that could not be made means the action it describes has not started.** Golden rule 2 puts the write first, so a claim that failed to land is no claim: do not branch, push or open anything for it. Retry the write when the forge answers, after reconciling.

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

Once adopted, treat it as yours: watch it, evaluate the gate, fix CI, answer review. Don't re-implement anything already in the diff, and don't force-push over commits you didn't write.

If its head is far behind the base, update the branch before evaluating the gate. A gate result against a stale base is meaningless.

## Remote-tracking refs lie after a session restart

Read remote state with `git ls-remote origin refs/heads/<branch>`, not `git rev-parse origin/<branch>`.

A container that was reclaimed and restarted comes back with a fetch cache from before it died, so `origin/<branch>` can report a SHA several commits behind the real one and report it confidently. During one plan this happened three times, and once a `git reset --hard origin/<branch>` moved the working tree back to a state from before the previous phase merged. Nothing warned; the reset succeeded.

`git ls-remote` asks the server every time. Use it before any decision that depends on where a branch actually points: comparing a phase head, confirming a merge, or resetting anything. A plain `git fetch` first is fine too, but only if you remember it every time, and the failure when you forget is silent.

## Two rules that prevent most of the damage

**Never start a phase that has an open PR.** Duplicate branches for one phase are the most confusing state to unpick, and every recovery path above is written to avoid creating one. If in doubt, search the row's repo for open PRs by head branch before you create anything.

**Never mark `Merged` without confirming it on the forge.** Being wrong here starts the next phase on a base that doesn't contain the previous one.

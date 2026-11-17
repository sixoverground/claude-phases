# The forge: GitHub

What is true of GitHub and of no other forge. `SKILL.md` holds the rules, in terms any forge has: a change request, its branch, its comments, its merge. This file says how each of those is done on GitHub, and why the GitHub way matters where it does.

On GitHub a change request is a **pull request**, and this file calls it a PR.

Read this file at Reconcile, and again after any compaction. The core points here at every step that touches the forge; a driver acting on the core alone will reach for the wrong tool, and on GitHub one of the wrong tools still succeeds while breaking review (see [Opener identity](#opener-identity)).

## Find

Reconcile asks the forge what is actually true for each row. On GitHub: `list_pull_requests` filtered by that row's head branch in that row's repo, then `pull_request_read{get}` for any match. Ask for PRs in any state, since a merged or closed PR answers the question as much as an open one does.

A milestone row's PR has the target branch as head and the default branch as base, so list by both, then pick the one whose title names the row's id, per SKILL.md's **Which PR is a milestone's**.

## Open

Open the PR with the GitHub MCP tools, never `gh pr create`. The reason is [Opener identity](#opener-identity), below. This holds for phase PRs, milestone PRs and the integration PR alike.

## Opener identity

After opening, read back who opened it, from the PR's own `user.login`.

### Who opens the PR decides whether it gets reviewed

Some reviewer integrations attach to an account. Codex reviews pull requests opened by the user who connected it and ignores everyone else's. So for those, the identity that *opens* the PR is a functional part of the merge gate, not a cosmetic detail: open a phase PR as a bot or app identity and no review is ever requested, gate 6 waits on proof that was never coming, and YOLO stops with nothing red to look at.

**Not every reviewer works that way**, and saying so matters because the wrong diagnosis here recommends closing a healthy PR. A review workflow triggered by `pull_request` reviews whatever lands in the repo whoever opened it, and a `check:` entry has no connected user to compare against at all. The opener matters for a `logins` entry backed by an account-scoped integration; elsewhere an unexpected opener is worth a sentence, not an alarm.

**Open the PR with the GitHub MCP tools, not `gh pr create`.** This is the whole rule, and it is not a style preference. In a cloud session `gh` is authenticated as the integration rather than as you, so `gh pr create` opens the PR as that app identity; the MCP tools act with the user's own authorization and open it as them. Both succeed, both print a PR URL, and only one of them gets reviewed. Push with git as usual; it is the PR-opening call that decides the author.

This is about the opener only. Commit authorship and `Co-Authored-By` trailers change nothing here, and no trailer will make a reviewer look at a PR opened by an account it doesn't watch.

**Then check, against the account your GitHub tools authenticate as**, which is `get_me`, read once per session. That is the identity the MCP tools open PRs with, so a PR whose `user.login` differs was opened by some other path, which is the failure this catches. Nothing needs to be configured for this: the comparison is between two things you can read, and a plan carries no field naming the expected opener.

If they differ, say so in the phase report and on the PR before waiting on anything. Name the login that opened it, and name the affected `review.required` entries, the account-scoped ones, rather than asserting that review is broken in general. The fix is usually to close it and reopen from the right account, which is cheap now and expensive after five gate cycles.

Do not let this become a silent wait. A reviewer that was never asked looks exactly like a reviewer that is slow.

## Watch

Subscribe to PR activity for each open phase PR. Webhooks don't reliably deliver CI success or new pushes, and a missed event otherwise stalls the plan silently, which is why the core's check-in exists alongside the subscription. When the merge has happened, unsubscribe from that PR.

**Some reviewers finish without an event.** A 👍 reaction, or a check run that passes, often delivers no webhook at all. When the thing you are waiting on will finish that way, typically a reviewer that has answered with 👀 and is still working, arm the check-in 10 to 15 minutes out rather than 45 to 60, so its answer is picked up in minutes rather than an hour.

### Asking a reviewer for a newer review

The core's rule that resolving a thread does not clear gate 4 asks the reviewer for a newer review "where the integration has a way". On GitHub that is re-requesting the review, or its trigger comment such as `@codex review`.

## Write the plan

`create_or_update_file` against `home_repo` on the plan branch, passing the `sha` you read at the start of the transition. Message: `chore(plan): <project> phase <N> -> <Status> [skip ci]`.

**The write token is the plan file's blob `sha`.** Re-read that `sha` at the start of **every** transition. When the plan branch is also a `target_branch`, merging a phase PR moves it, and a sha cached from before the merge is already stale. A write with a stale sha fails, which is the compare-and-swap the core's lock rules rely on.

## Merge

Merge with that repo's `merge.method` (`squash`, `merge` or `rebase`). The merge API takes no expected head sha, which is why the core re-reads the head as the last call before merging.

## Delete the branch

**Deleting the branch is yours to do because the API will not.** GitHub's merge endpoint has no equivalent of the UI's "delete branch after merge" checkbox, so a driver that merges and stops leaves a branch behind for every phase it shipped, while phases a human merged get cleaned up. Nobody notices until the branch list is half stale and it is no longer obvious which of them are finished.

The core's guard on which branches may be deleted applies unchanged.

A failed delete is not a failed merge. Branch protection or a ruleset can forbid it, and so can the environment the session runs in: a sandboxed one may permit pushes and PR operations while refusing ref deletion at both the git and API layers. Say so once and carry on, because the phase is merged either way and nothing downstream depends on the branch being gone.

**A second failure for the same reason is not incidental, so stop reporting it as though it were.** Say once that deletions are refused here and recommend turning on GitHub's own *Automatically delete head branches* (Settings → General), which runs server-side on merge and needs nothing from the driver. Without that, the driver shrugs once per phase for the length of the plan and the user finds a fully stale branch list at the end, losing the signal the deletion exists to preserve: that a branch which still exists means work which has not landed.

## Milestone and integration change requests

Both are PRs from the repo's `target_branch` to its default branch, opened the GitHub MCP way and for the same reason as a phase PR (see [Opener identity](#opener-identity)). Find one by [Find](#find).

## Re-sync a branch

The core says which case applies and that every move is conditional on the head just checked. On GitHub the push for each case is:

| Case | Push |
|---|---|
| Re-create | `git push --force-with-lease=refs/heads/<target_branch>: origin <default sha>:refs/heads/<target_branch>` (an empty lease means "must not exist") |
| Fast-forward | `git push origin <default sha>:refs/heads/<target_branch>` (a plain push refuses anything but a fast-forward) |
| Squash or rebase | `git push --force-with-lease=refs/heads/<target_branch>:<merged head sha> origin <default sha>:refs/heads/<target_branch>` |

When the update is refused, report the matching command from the table, filled in.

## Issue fallback

Where the core sends something to "an issue on the forge", on GitHub that is a GitHub issue in that repo: a standalone defect, the arbiter's `issue` verdict, and the UAT fallback at the end of a plan, which is an issue titled `UAT: <project>` with the outstanding items.

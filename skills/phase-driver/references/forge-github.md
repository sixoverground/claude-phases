# The forge: GitHub

What is true of GitHub and of no other forge. `SKILL.md` holds the rules, in terms any forge has: a change request, its branch, its comments, its merge. This file says how each of those is done on GitHub, and why the GitHub way matters where it does.

On GitHub a change request is a **pull request**, and this file calls it a PR.

Read this file at Reconcile, and again after any compaction. The core points here at every step that touches the forge; a driver acting on the core alone will reach for the wrong tool, and on GitHub one of the wrong tools still succeeds while breaking review (see [Opener identity](#opener-identity)).

## Find

Reconcile asks the forge what is actually true for each row. On GitHub: `list_pull_requests` filtered by that row's head branch in that row's repo, then `pull_request_read{get}` for any match. Ask for PRs in any state, since a merged or closed PR answers the question as much as an open one does.

A milestone row's PR has the target branch as head and the release branch (SKILL.md, **Find the plan**) as base, so list by both, then pick the one whose title names the row's id, per SKILL.md's **Which PR is a milestone's**.

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

The core's rule that resolving a thread does not clear gate 4 asks the reviewer for a newer review "where the integration has a way". On GitHub that is re-requesting the review, or its trigger comment such as `@codex review`. The trigger comment is stamped like any other comment you post, as [Stamp what you write](../SKILL.md#stamp-what-you-write) says.

## The gates

`gates.md` asks each of the six gates as a question any forge can answer. This is how GitHub answers it.

### Gate 1: draft

The PR passes when `draft == false`.

### Gate 2: labels

The PR's own labels, compared with `blocking_labels`.

### Gate 3: checks

Read check runs and commit statuses for the head commit. Legacy integrations post statuses rather than check runs, so read both.

**Passing conclusions: `success`, `skipped`, `neutral`.** Everything else blocks: `failure`, `cancelled`, `timed_out`, `action_required`, `startup_failure`, `stale`. A check still running blocks until it finishes, wait, don't fail.

`neutral` passes because GitHub itself treats it as non-blocking, and advisory tools use it precisely so they never block a merge. Treating it as a failure deadlocks every merge on any repo with an advisory reporter.

#### Reading a failure

Per the repo's `ci.logs`:

- **`actions`**. Fetch the failed jobs' logs for the run and read the actual error. Same fix loop as local, just slower.
- **`check-output`**. Read the check run's `output.title`, `output.summary`, and `details_url`. Often enough to name the failing test; sometimes only enough to know it failed.
- **`auto`**. Actions logs when the check belongs to an Actions run, otherwise check output.

A check run's own page, the one to link when its output does not say why it failed, is its `details_url`.

### Gate 4: changes requested

A review's states include `APPROVED`, `CHANGES_REQUESTED` and `COMMENTED`. A request for changes is the latest review of one author being `CHANGES_REQUESTED`; a later `APPROVED` or `COMMENTED` review by the same author supersedes it.

### Gate 5: threads

A review thread is resolved when `isResolved == true`.

A reply you post in a thread, like every comment you post, ends with the driver's stamp, as [Stamp what you write](../SKILL.md#stamp-what-you-write) says.

#### Whose thread it is

The core decides whose a note is by [Whose note it is](gates.md#whose-note-it-is), and a thread is its first comment's. On GitHub the fields are:

- **The first comment** of a review thread: `comments(first: 1)` on the thread in GraphQL, or the review comment with no `in_reply_to_id` in REST. Its `body` holds any stamp or marker, and `author.login` (GraphQL) or `user.login` (REST) its author.
- **The account the driver acts as**: `gh api user --jq .login`. Compare logins case-insensitively, ignoring a trailing `[bot]`.
- **A bot account**: GitHub types it as one, `user.type == "Bot"` in REST or `author.__typename == "Bot"` in GraphQL. Cloud Codex, Copilot, `claude[bot]` and other GitHub Apps are found this way, exactly as before stamps.
- **An author in `logins`**: in the `logins` of a `review.required` entry and **not** the account the driver acts as. On one account the author is the driver's own, and only a reviewer stamp or marker in the body makes the comment a reviewer's.

So a thread is **a reviewer's** when its first comment carries no driver stamp and either its author is a `Bot`, or is in a `logins` that is not the driver's own, or the comment carries a reviewer stamp or marker naming a configured `marker` entry from one of its `logins` where it lists any. It is **the driver's** when its first comment is from the driver's account and carries the driver stamp. Anything else is **a person's**, including an unstamped comment from the driver's own account.

A comment the driver wrote before it stamped its comments reads as a person's, which errs toward a wake and an open thread, as the core says.

### Gate 6: reviewer

A review is of the head commit when its `commit_id == head.sha`, and the head sha is the PR's `head.sha`.

For a check run judged by `proof`, *completed* is `status == completed`, *skipped or cancelled* are those two conclusions, and *non-empty output* is a non-empty `output.title` or `output.summary`.

App accounts' logins carry a trailing `[bot]`, which login matching ignores.

A `marker` entry's comments are the PR's top-level ones. On GitHub those are the PR's issue comments (`gh api repos/{owner}/{repo}/issues/{number}/comments`), not its review comments.

The two sections below are GitHub's own, and "the rules above" in them means gate 6's satisfiers in `gates.md`.

#### The decline reaction

Some reviewers answer "this PR doesn't need a review" with a reaction rather than a review. Codex on **smart detect** leaves a 👍 on the PR and posts nothing else. It has evaluated the PR; it is telling you the verdict in the only place it writes.

A 👍 by one of the entry's `logins` **created at or after the head commit's committer date** is proof it evaluated this head, and gate 6 asks nothing more than that. An older one is not: GitHub allows one reaction per login per content, so the 👍 left at PR open cannot be left again for the commit you're about to merge, and its timestamp still points at the first evaluation. A stale 👍 proves only that the integration is alive, which is what [`rereview: optional`](#rereview-optional) does with it.

**Read it attributed, or not at all:**

```
gh api repos/{owner}/{repo}/issues/{number}/reactions --jq '.[] | {login: .user.login, content, created_at}'
```

PR body reactions live on the *issues* endpoint; that is not a typo. A reaction can also sit on a comment rather than the PR body, and those come from that comment's own `reactions` endpoint.

**Only 👍 is a verdict. The same reviewer uses other reactions to mean other things.** Codex answers a `@codex review this pr` comment with 👀 within seconds, meaning it has picked the job up. Observed on this repository, ten seconds after the request and with no review for minutes afterwards. Reading any reaction from a configured login as proof would merge on "I have started reading", which is worse than the silence it replaced because it arrives fast and looks like an answer. Match on the content, not on the presence of a reaction.

| Reaction from a `logins` entry | Means |
|---|---|
| 👍 `+1` | Evaluated; no review needed. A verdict |
| 👀 `eyes` | Picked it up, working. **Not** a verdict, and not a sign the PR was evaluated |
| Anything else | Nothing you can act on |

**The trap: `issue_read` reports reaction counts, not who reacted.** A `"+1": 1` in that payload looks like the answer and isn't, because a teammate giving the PR a thumbs up produces the identical field. Counting reactions instead of attributing them turns any human's 👍 into a merge, which is the silent false pass this gate exists to prevent. If you cannot reach the reactions endpoint, say so and fall back to the other rules. Never infer a reviewer's verdict from a count.

#### `rereview: optional`

An entry carrying `rereview: optional` has a second way to be satisfied, for reviewers that review a PR once and then decide per push whether to look again (OpenAI's Codex **smart detect**).

| State at the head sha | Verdict |
|---|---|
| A `logins` review, inline comment, or 👍 at `head.sha` | **PASS**, by the rules above |
| A completed review-state comment by a `logins` author naming `head.sha` | **PASS**, as [Codex's review-state comment](#codexs-review-state-comment) says |
| None at head, **at least one sign of that reviewer anywhere on this PR**, and `rereview_grace` has elapsed since the head was pushed | **PASS**, as a decline |
| None at head, at least one earlier sign, grace not yet elapsed | **BLOCK.** Keep waiting |
| **No sign of that reviewer anywhere on this PR** | **BLOCK. Never times out** |

A **sign** is a review, an inline comment, or a 👍 by one of the entry's `logins`, at any commit on this PR. Any one of them proves the integration is alive and that this reviewer has this PR. So does a completed [review-state comment](#codexs-review-state-comment) by one of them, naming any commit on this PR.

**When a PR carries no sign at all, check who opened it before you call the integration broken.** Some reviewer integrations attach to an account. Codex reviews the connected user's PRs and ignores a bot's, so a phase PR opened under the wrong identity is never reviewed by design. This applies to an account-scoped `logins` entry; a `check:` entry has no connected user, and a workflow-triggered reviewer runs whoever opened the PR. It presents identically to a dead integration and has a different, one-minute fix: reopen it from the right account. The usual cause is a PR opened with `gh pr create` in a cloud session, which authenticates as the integration rather than as the user. Read the PR's `user.login`, and if it isn't the human whose plan this is, report that as the cause instead of reporting a wait.

That last row is load-bearing. Smart detect always evaluates a PR once, so a PR carrying no sign at all is a broken integration, not a decline, and it must never age into a pass. Drop the precondition and `optional` becomes "wait fifteen minutes, then merge unreviewed."

**Counting the 👍 as a sign is what fixes the case where smart detect declines from the very first commit.** Its evaluation of a small PR can be "nothing here worth reviewing", and then the reaction is the only thing it ever writes. Reading signs as reviews-only, that PR looks identical to a dead integration and blocks forever, which is the state this rule was found in: a real project, YOLO on, a phase wedged behind a reviewer that had already answered.

**Measure the grace from the head commit's committer date**, which GitHub stamps at push. Measuring from when you started waiting means a driver that wakes an hour after the push times out on its first look, before the reviewer has had any chance at all.

`rereview_grace` defaults to `15m`.

**Say so when a pass came from a decline.** Under YOLO this is a merge with no fresh review, and it has to be legible afterward:

```
6 reviewer     PASS (codex @ a1b2c3d, declined re-review of 2 later commits, 18m elapsed)
```

Post the same line on the PR before merging. A decline recorded nowhere is indistinguishable from a review that happened, which is the exact failure the rest of this gate is built to avoid.

A pass carried by a 👍 says which one it was, because the two mean different things. A fresh reaction is the reviewer's verdict on this commit; a stale one is a decline inferred from silence:

```
6 reviewer     PASS (codex 👍 on the PR, 4m after this head was pushed)
6 reviewer     PASS (codex 👍 at PR open, no review of 3 commits since, 22m elapsed)
```

#### Codex's review-state comment

Codex keeps one top-level comment on the PR that records its review's state, and edits it in place as the review runs. Its body carries, on a line of its own:

```
<!-- codex-review-state:v1 {"code_review":{"commit_sha":"fc7229478f2d711021eb1bf3b4b25a197f576197","has_any_findings":false,"has_unresolved_findings":false,"status":"completed"},"security_review":{...}} -->
```

The comment's author is attributable through the same tools that read comments, which is what makes it useful: a session that can see only reaction counts can still see this. Codex has not documented the format, so read it strictly and fail closed.

**Proof for a head.** All of these, read from the comment as it is now, never from an earlier reading of it:

- its author is one of the entry's `logins`, matched as everywhere in this gate
- the line is exactly `<!-- codex-review-state:v1 ` followed by a JSON object and ` -->`, and the JSON parses
- `code_review.status` is `completed`
- `code_review.commit_sha` equals the full `head.sha`

Then the entry is satisfied at this head, as a review there would satisfy it.

**A sign** for [`rereview: optional`](#rereview-optional): the same comment with `status` `completed`, naming any commit on this PR.

**Not proof, and not a sign** (treat the comment as absent):

| Found | Why |
|---|---|
| `status` anything but `completed`, such as `running` | The review has not finished. This is the comment's 👀 |
| An author outside `logins` | Anyone can paste the line into a comment |
| A version other than `v1`, or JSON that does not parse | A format this rule was not written for. Treat the comment as absent |
| `commit_sha` shorter than the full sha | A prefix can match more than one commit, as with a marker |

A completed comment whose full `commit_sha` names an **earlier** head of this PR is not proof for the current head, and **is** a sign, by the rule above. That is the stale case `rereview: optional` exists for, and reading it as nothing would block that entry forever.

**It is not history.** Codex edits this comment in place, so it says what was true of its latest review and nothing about earlier heads. It never counts toward the reviewed heads in SKILL.md's review-round budget: that count is derived from records that stay put. A round in which Codex found something leaves a review at that commit, which the count already reads, and a round in which it found nothing ends the loop anyway.

**Never read a verdict from it.** `has_any_findings` and `has_unresolved_findings` are Codex's opinion of its own findings. Gate 6 asks only whether the reviewer looked; its findings are threads, and gate 5 owns those.

**When the reactions endpoint is out of reach**, as in a session whose tools report reaction counts only, say so, and look for this comment before reporting gate 6 as blocked. A 👍 you cannot attribute still counts for nothing.

```
6 reviewer     PASS (codex review-state comment @ fc72294, completed)
6 reviewer     BLOCK: codex review-state comment is running for fc72294
```

## Write the plan

`create_or_update_file` against `home_repo` on the plan branch, passing the `sha` you read at the start of the transition. Message: `chore(plan): <project> phase <N> -> <Status> [skip ci]`.

**The write token is the plan file's blob `sha`.** Re-read that `sha` at the start of **every** transition. When the plan branch is also a `target_branch`, merging a phase PR moves it, and a sha cached from before the merge is already stale. A write with a stale sha fails, which is the compare-and-swap the core's lock rules rely on.

## Merge

Merge with that repo's `merge.method` (`squash`, `merge` or `rebase`). The merge API takes no expected head sha, which is why the core re-reads the head as the last call before merging.

## Delete the branch

**Deleting the branch is yours to do because the API will not.** GitHub's merge endpoint has no equivalent of the UI's "delete branch after merge" checkbox, so a driver that merges and stops leaves a branch behind for every phase it shipped, while phases a human merged get cleaned up. Nobody notices until the branch list is half stale and it is no longer obvious which of them are finished.

The core's guard on which branches may be deleted applies unchanged. This deletes the branch on GitHub; the driver's local copy is removed separately, after any merge, by the core's [Tidy the local clone](../SKILL.md#tidy-the-local-clone).

A failed delete is not a failed merge. Branch protection or a ruleset can forbid it, and so can the environment the session runs in: a sandboxed one may permit pushes and PR operations while refusing ref deletion at both the git and API layers. Say so once and carry on, because the phase is merged either way and nothing downstream depends on the branch being gone.

**A second failure for the same reason is not incidental, so stop reporting it as though it were.** Say once that deletions are refused here and recommend turning on GitHub's own *Automatically delete head branches* (Settings → General), which runs server-side on merge and needs nothing from the driver. Without that, the driver shrugs once per phase for the length of the plan and the user finds a fully stale branch list at the end, losing the signal the deletion exists to preserve: that a branch which still exists means work which has not landed.

## Milestone and integration change requests

Both are PRs from the repo's `target_branch` to its release branch, `release_branch` or the repository's `default_branch`, opened the GitHub MCP way and for the same reason as a phase PR (see [Opener identity](#opener-identity)). Find one by [Find](#find).

**Warn about skip instructions before it is merged.** When you report one ready, read the messages of the commits it would squash, `gh api --paginate repos/<owner>/<repo>/pulls/<n>/commits --jq '.[] | [.sha[0:7], .commit.message] | @tsv'`, and look for any of GitHub's skip instructions: `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, `[actions skip]`, matched case-insensitively. A squash merge's default message quotes every one of those messages, and GitHub skips a push-triggered workflow on the release branch when the pushed commit's message contains one, so a release or deploy that runs on that push would not run. If any commit carries one, add to the ready message which commits, and that a squash merge would quote them, so the person can trim the squash message or check afterwards that the workflow ran. It changes nothing and blocks nothing: the merge is still theirs.

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

Issues are available on GitHub, so the core's UAT fallback opens one here rather than posting the script as a comment.

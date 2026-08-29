# The merge gate

Six gates. All must pass before a merge. Evaluate them against a specific commit (the PR's current head) and discard the result the moment the head moves.

Use the row's repo's resolved config (its entry deep-merged over `defaults`).

| # | Gate | Passes when | Off switch |
|---|---|---|---|
| 1 | Not a draft | `draft == false` | none: a draft is an explicit "not ready" |
| 2 | No blocking label | No label in `blocking_labels` (default `do-not-merge`, `wip`, `blocked`) | `blocking_labels: []` |
| 3 | Checks green | Every counted check concluded `success`, `skipped`, or `neutral` | `ci.allow_none: true` covers the zero-checks case |
| 4 | No changes requested | For each reviewer, their *latest* review is not `CHANGES_REQUESTED` | `review.changes_requested_blocks: false` |
| 5 | Threads resolved | Every review thread has `isResolved == true` | `review.threads_must_resolve: false` |
| 6 | Reviewer saw this commit | Every entry in `review.required` is satisfied at the head SHA, or declined it under `rereview: optional` | `review.required: []` (the default) |

## Gate 3: checks

Read check runs and commit statuses for the head commit. Legacy integrations post statuses rather than check runs, so read both.

**Which checks count**, in precedence order:

1. `ci.required` is non-empty → only those names count. Everything else is ignored.
2. Otherwise every reported check counts,
3. minus anything in `ci.ignore_checks`,
4. minus any check named in `review.required[].check`. A reviewer's own check never gates the merge unless you explicitly put it in `ci.required`.

**Passing conclusions: `success`, `skipped`, `neutral`.** Everything else blocks: `failure`, `cancelled`, `timed_out`, `action_required`, `startup_failure`, `stale`. A check still running blocks until it finishes, wait, don't fail.

`neutral` passes because GitHub itself treats it as non-blocking, and advisory tools use it precisely so they never block a merge. Treating it as a failure deadlocks every merge on any repo with an advisory reporter.

**Zero checks blocks** unless `ci.allow_none: true`. A repo whose CI silently stopped running looks identical to a repo with no CI, and the failsafe direction is to stop.

### Reading a failure

Per the repo's `ci.logs`:

- **`actions`**. Fetch the failed jobs' logs for the run and read the actual error. Same fix loop as local, just slower.
- **`check-output`**. Read the check run's `output.title`, `output.summary`, and `details_url`. Often enough to name the failing test; sometimes only enough to know it failed.
- **`none`.** Don't guess.
- **`auto`**. Actions logs when the check belongs to an Actions run, otherwise check output.

**When the output doesn't tell you why it failed, say so and link `details_url`.** Do not push a speculative fix. Three guesses cost more than one honest question, and a wrong guess that turns CI green is worse than a red build.

### Flakes

One re-run of failed jobs per head commit, and disclose it in the PR. Re-running until green is how a real failure gets laundered into a pass.

## Gates 4, 5, 6: review

**Gate 4.** Group reviews by author, take each author's most recent. A `CHANGES_REQUESTED` that the same reviewer later superseded with an approval or a comment no longer blocks.

**Gate 5.** Every review thread resolved. Only diff-anchored comments form resolvable threads, so this does nothing for a reviewer that posts only top-level comments. Resolve a thread only when you've actually addressed it.

**Gate 6.** Each entry in `review.required` needs proof it evaluated **this** commit. An entry is satisfied by any of:

- a review by one of its `logins` with `commit_id == head.sha`, or
- an inline review-thread comment by one of them at that sha, or
- a **👍 reaction on the PR by one of its `logins`**, created at or after the head commit's committer date. See [The decline reaction](#the-decline-reaction), or
- a check run named by its `check` at that sha, judged by the entry's `proof`:
  - **`output`** (default). `status == completed`, conclusion not `skipped` or `cancelled`, **and** a non-empty `output.title` or `output.summary`.
  - **`completed`.** `status == completed`, conclusion not `skipped` or `cancelled`.

Login matching is case-insensitive and ignores a trailing `[bot]`.

### The decline reaction

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

### `rereview: optional`

An entry carrying `rereview: optional` has a second way to be satisfied, for reviewers that review a PR once and then decide per push whether to look again (OpenAI's Codex **smart detect**).

| State at the head sha | Verdict |
|---|---|
| A `logins` review, inline comment, or 👍 at `head.sha` | **PASS**, by the rules above |
| None at head, **at least one sign of that reviewer anywhere on this PR**, and `rereview_grace` has elapsed since the head was pushed | **PASS**, as a decline |
| None at head, at least one earlier sign, grace not yet elapsed | **BLOCK.** Keep waiting |
| **No sign of that reviewer anywhere on this PR** | **BLOCK. Never times out** |

A **sign** is a review, an inline comment, or a 👍 by one of the entry's `logins`, at any commit on this PR. Any one of them proves the integration is alive and that this reviewer has this PR.

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

### Why gate 6 is written so carefully

It answers exactly one question: *did the reviewer look at this commit?* Not whether it approved, and not whether its findings were addressed.

| Question | Gate |
|---|---|
| Did the reviewer look at this commit? | 6 |
| Were its findings addressed? | 5 |
| Must the review check itself be green? | 3: put its name in `ci.required` |

Keeping those apart is what lets one rule work for reviewers that signal findings by failing *and* reviewers that never fail by design. Anthropic's managed Code Review always concludes `neutral` so it can never block a merge; requiring `success` here would mean its proof never arrives.

**And why `proof` is configurable rather than fixed.** A check run alone cannot tell you whether a review happened. Two runs of the same workflow, on the same PR, produced identical signals from opposite realities:

| Run | Duration | Check | Reality |
|---|---|---|---|
| First | 10s | `success`, empty output | Skipped on workflow validation. Reviewed **nothing** |
| Later | 8.5 min, 37 turns | `success`, empty output | Genuinely reviewed. Posted **nothing** |

`proof: output` rejects both. `proof: completed` accepts both. There is no third rule that reads only the check run and separates them, so the choice is which error to prefer, and it belongs to whoever knows their reviewer.

Default to `output`. **A false pass is silent and permanent. A gate reporting satisfied while measuring nothing looks exactly like a healthy pass.** A false block is loud, and someone notices within a phase. When you must relax it, prefer fixing the reviewer to say something on a clean pass.

When a gate blocks because a reviewer produced no artifact, say exactly that. "The reviewer ran but posted nothing" is a different problem from "the reviewer hasn't run", and the user can only act on the difference if you name it.

## Merging

Re-read the head SHA as your **last** read before merging, with no other calls in between. The merge API takes no expected-SHA, so this window can be narrowed but not closed. If the head moved, start the gate over.

## Reporting

State each gate's verdict plainly, in the same shape every time:

```
Phase 3 — acme/acme-web#42
  1 draft         PASS
  2 labels        PASS
  3 checks        FAIL: 1 of 4 checks failed (build)
  4 reviews       PASS
  5 threads       FAIL: 2 unresolved review thread(s)
  6 reviewer      PASS (Claude review @ a1b2c3d)
```

Name what's blocking, not just that something is. "Waiting on CI" is not a useful thing to tell someone whose build has been broken for an hour.

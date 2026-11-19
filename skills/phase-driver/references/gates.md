# The merge gate

Six gates. All must pass before a merge. Evaluate them against a specific commit (the PR's current head) and discard the result the moment the head moves.

Use the row's repo's resolved config (its entry deep-merged over `defaults`).

Each gate is a question any forge can answer. How GitHub answers it, field by field, is in [`forge-github.md`](forge-github.md#the-gates), under a heading per gate. How GitLab answers it is in [`forge-gitlab.md`](forge-gitlab.md#the-gates), under the same headings. Read the forge reference for the change request's repo.

| # | Gate | Passes when | Off switch | On GitHub | On GitLab |
|---|---|---|---|---|---|
| 1 | Not a draft | The change request is not a draft | none: a draft is an explicit "not ready" | [Gate 1](forge-github.md#gate-1-draft) | [Gate 1](forge-gitlab.md#gate-1-draft) |
| 2 | No blocking label | No label in `blocking_labels` (default `do-not-merge`, `wip`, `blocked`) | `blocking_labels: []` | [Gate 2](forge-github.md#gate-2-labels) | [Gate 2](forge-gitlab.md#gate-2-labels) |
| 3 | Checks green | Every counted check passed | `ci.allow_none: true` covers the zero-checks case | [Gate 3](forge-github.md#gate-3-checks) | [Gate 3](forge-gitlab.md#gate-3-checks) |
| 4 | No changes requested | For each reviewer, their *latest* review does not request changes | `review.changes_requested_blocks: false` | [Gate 4](forge-github.md#gate-4-changes-requested) | [Gate 4](forge-gitlab.md#gate-4-changes-requested) |
| 5 | Threads resolved | Every review thread is resolved | `review.threads_must_resolve: false` | [Gate 5](forge-github.md#gate-5-threads) | [Gate 5](forge-gitlab.md#gate-5-threads) |
| 6 | Reviewer saw this commit | Every entry in `review.required` is satisfied at the head SHA, or declined it under `rereview: optional` | `review.required: []` (the default) | [Gate 6](forge-github.md#gate-6-reviewer) | [Gate 6](forge-gitlab.md#gate-6-reviewer) |

## Gate 3: checks

Read every check the forge reports for the head commit. [Gate 3](forge-github.md#gate-3-checks) in the forge reference says where they come from on GitHub, and [Gate 3](forge-gitlab.md#gate-3-checks) on GitLab.

**Which checks count**, in precedence order:

1. `ci.required` is non-empty → only those names count. Everything else is ignored.
2. Otherwise every reported check counts,
3. minus anything in `ci.ignore_checks`,
4. minus any check named in `review.required[].check`. A reviewer's own check never gates the merge unless you explicitly put it in `ci.required`.

**Every check either passed, blocked, or is still running.** Which conclusions pass and which block is the forge's vocabulary, listed under [Gate 3](forge-github.md#gate-3-checks) for GitHub and [Gate 3](forge-gitlab.md#gate-3-checks) for GitLab. A check still running blocks until it finishes, wait, don't fail.

**Zero checks blocks** unless `ci.allow_none: true`. A repo whose CI silently stopped running looks identical to a repo with no CI, and the failsafe direction is to stop.

### Reading a failure

Per the repo's `ci.logs`. The values that fetch something are the forge's, and [Reading a failure](forge-github.md#reading-a-failure) says what each one reads on GitHub, and [Reading a failure](forge-gitlab.md#reading-a-failure) on GitLab. One value is the same everywhere:

- **`none`.** Don't guess.

**When the output doesn't tell you why it failed, say so and link the check's own page.** Do not push a speculative fix. Three guesses cost more than one honest question, and a wrong guess that turns CI green is worse than a red build.

### Flakes

One re-run of failed jobs per head commit, and disclose it in the PR. Re-running until green is how a real failure gets laundered into a pass.

## Gates 4, 5, 6: review

**Gate 4.** Group reviews by author, take each author's most recent. A request for changes that the same reviewer later superseded with an approval or a comment no longer blocks.

**Gate 5.** Every review thread resolved. Only diff-anchored comments form resolvable threads, so this does nothing for a reviewer that posts only top-level comments. Resolve a thread only when you've actually addressed it: fixed it, declined it as out of scope and said where it went, or, on a review bot's thread, answered it with checkable reasoning that it is wrong or not worth a round. A thread a person opened is resolved only for the first two. See *Answering a review* in the skill.

**Gate 6.** Each entry in `review.required` needs proof it evaluated **this** commit. An entry is satisfied by any of:

- a review by one of its `logins` of the head commit, or
- an inline review-thread comment by one of them at that sha, or
- a **👍 reaction on the PR by one of its `logins`**, created at or after the head commit's committer date. See [The decline reaction](forge-github.md#the-decline-reaction), or
- a **review-state record by one of its `logins`**, where the forge reference defines one, saying a review of exactly the head sha completed. On GitHub that is [Codex's review-state comment](forge-github.md#codexs-review-state-comment), or
- for a `marker` entry, **a top-level comment on the change request containing a `v=1` review marker** whose `reviewer` equals the entry's `marker` and whose `sha` equals the head sha, authored by one of the entry's `logins` when it lists any. See [The review marker](#the-review-marker), or
- a check named by its `check` at that sha, judged by the entry's `proof`:
  - **`output`** (default). Completed, with a conclusion other than skipped or cancelled, **and** with non-empty output.
  - **`completed`.** Completed, with a conclusion other than skipped or cancelled.

Login matching is case-insensitive, and ignores the suffix the forge adds to an app account's login. [Gate 6](forge-github.md#gate-6-reviewer) gives GitHub's, and [Gate 6](forge-gitlab.md#gate-6-reviewer) GitLab's.

**A `marker` entry is satisfied by its marker and nothing else.** The review, inline-comment, 👍 and review-state rules above do not apply to it, and its `logins` only say who may author the marker note. A reviewer that posts a finding and then fails before finishing has written no marker, and an inline comment or 👍 from its account must not stand in for one: the marker exists precisely because those signals cannot say a review completed.

### The review marker

A `{ marker: "<reviewer>" }` entry is satisfied by a reviewer that meets the [review contract](https://github.com/sixoverground/claude-phases/blob/main/docs/review-contract.md): after every completed review it posts a top-level note on the change request carrying, on a line of its own,

```
<!-- phases:review v=1 reviewer=<name> sha=<full 40-character sha> -->
```

The rule needs only what every forge has: the change request's top-level comments, their text, and their author. Where to find those comments is the forge's, under [Gate 6](forge-github.md#gate-6-reviewer) for GitHub and [Gate 6](forge-gitlab.md#gate-6-reviewer) for GitLab.

**It is proof for the sha it names, and only that one.** Match it exactly:

- `reviewer` equals the entry's `marker`, and `sha` equals the full head sha. A marker for an earlier head says nothing about this one.
- When the entry lists `logins`, the comment's author is one of them, matched as everywhere else in this gate. Without `logins`, any author counts, so on a repo where outsiders can comment the entry is forgeable by anyone; the planner warns about this.

**Four things that look like a marker and are not proof:**

| Found | Why it is not proof |
|---|---|
| A `v` other than `1` | An unknown version. The format may mean something else there, so it blocks, and the report says which version it found |
| An abbreviated sha, such as the first seven characters | The contract requires the full sha, and a prefix can match more than one commit |
| A marker inside an inline thread comment on the diff | The contract puts it in a top-level note. A thread comment is where model-written findings live, which is exactly where a forged marker would come from |
| A marker you wrote | **Never write a marker yourself**, or a reviewer stamp, in any comment, for any reason. The driver is the one thing a marker exists to inform, and a driver that can produce its own proof has no gate |

`proof` and `rereview` do not apply to a `marker` entry. A marker is posted by the reviewer's code only after a completed review, so there is no empty-check case for `proof` to tune. And a reviewer that may skip a commit simply posts no marker for it, which blocks, as an unreviewed commit should.

```
6 reviewer     PASS (codex marker @ a1b2c3d)
6 reviewer     BLOCK: no codex marker for a1b2c3d (latest is for 9f8e7d6)
```

### `rereview: optional`

An entry carrying `rereview: optional` can also pass as a decline, for reviewers that review once and then decide per push whether to look again. The rule, its four states, and why its last row never times out, are in [`rereview: optional`](forge-github.md#rereview-optional) in the forge reference.

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

Re-read the head SHA as your **last** read before merging, with no other calls in between. Where the forge's merge cannot be told which head to merge, as the forge reference's [Merge](forge-github.md#merge) says of GitHub, this window can be narrowed but not closed. If the head moved, start the gate over.

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

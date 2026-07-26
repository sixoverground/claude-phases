# Configuration reference

Every key lives in the plan file's front matter under `phases:`. The only assumptions this project makes are **GitHub** and **Claude Code** — CI provider, languages, review setup, and branch conventions are all configurable, including "none at all" for each.

Values in `defaults:` are inherited by every repo. Values under a specific repo deep-merge over them, so you override one key without restating the rest.

```yaml
phases:
  defaults:
    ci: { allow_none: false, logs: auto }
  repos:
    acme/docs:
      ci: { allow_none: true }     # logs: auto is still inherited
```

---

## Top level

| Key | Default | Meaning |
|---|---|---|
| `project` | *required* | Project name. Also the plan's filename |
| `home_repo` | *required* | `owner/name` where the plan file lives. The **only** repo the driver writes plan state to |
| `repos` | *required* | Map of `owner/name` → per-repo overrides. `{}` means "inherit everything" |
| `defaults` | `{}` | Values inherited by every repo |
| `max_concurrent` | `null` | Global cap on simultaneously open phase PRs. `null` means no cap beyond the built-in one-per-repo rule |

---

## Per-repo (and `defaults`)

### Branch and merge

| Key | Default | Meaning |
|---|---|---|
| `branch_prefix` | `claude/` | Prefix for phase branches. Also how the driver recognizes its own branches |
| `target_branch` | repo's default branch | What phases branch from and merge into |
| `merge.method` | `squash` | `squash`, `merge`, or `rebase` |
| `plan_writes` | `default-branch` | `default-branch`, or `plan-pr` when the default branch is protected. See below |
| `yolo` | `true` | `false` pins this repo to manual merges regardless of the global toggle. Config can only restrict, never force |

### Verification

| Key | Default | Meaning |
|---|---|---|
| `verify` | `auto` | Where tests run before the PR opens |
| `uat` | `true` | Whether PRs carry a manual UAT checklist. `false` for repos where hand-testing is meaningless |

| Value | Behavior |
|---|---|
| `local` | Run the repo's tests/build in the session container before pushing. Fastest loop — no CI round-trip. Needs the toolchain to be installable; a `SessionStart` hook is the reliable way to guarantee that |
| `ci` | Don't attempt a local build. Let CI verify |
| `auto` | Try local; fall back to CI if the toolchain isn't there, **and say which path ran in the PR body** |
| `none` | No verification. For docs-only repos |

What's realistic:

- **Web / backend** — `local`. Node, Python, Go, and Rust toolchains all install in the container.
- **Android** — `auto`. JVM unit tests are feasible; emulator-backed instrumented tests belong in CI.
- **iOS** — `ci`. Building needs macOS and Xcode; no Linux container has them.

### CI

The driver never asks which CI product you use. It asks three separable questions, and every provider answers them differently.

| Key | Default | Meaning |
|---|---|---|
| `ci.required` | `[]` | Check names that must pass. `[]` means *every* counted check must pass |
| `ci.ignore_checks` | `[]` | Check names excluded from counting. For advisory checks — coverage reporters, preview deploys |
| `ci.allow_none` | `false` | With `false`, zero checks **blocks** the merge (failsafe). Set `true` for repos with no CI |
| `ci.dispatch` | `auto` | How the driver triggers a build |
| `ci.logs` | `auto` | How the driver reads a failure |

**What "pass" means.** A check passes when its conclusion is `success`, `skipped`, or **`neutral`**. This matches GitHub's own branch-protection semantics — `neutral` is explicitly a non-failing result, and advisory tools use it precisely so they never block a merge. Everything else blocks: `failure`, `cancelled`, `timed_out`, `action_required`, `startup_failure`, `stale`. A check still running blocks until it finishes.

**Which checks count.** Three mechanisms, in precedence order:

1. `ci.required` is set → only those checks count; everything else is ignored.
2. `ci.required: []` (the default) → every reported check counts.
3. `ci.ignore_checks` → names excluded from counting in case 2.

A reviewer's check named in `review.required[].check` is **automatically excluded** from this gate unless you also name it in `ci.required`. Nobody should have to work out that their code reviewer is deadlocking their own merge gate.

**`ci.dispatch`**

| Value | Behavior |
|---|---|
| `auto` | Use `workflow_dispatch` if a workflow declares it; otherwise trigger by pushing |
| `workflow:<file>` | Dispatch that specific workflow against the phase branch |
| `push` | Only ever trigger CI by pushing a commit |
| `none` | Never dispatch. For CI that starts on its own conditions, like Xcode Cloud |

**`ci.logs`** — this one determines how autonomously a red build gets fixed.

| Value | Behavior |
|---|---|
| `actions` | Fetch real failure text from the GitHub Actions log API. The fix loop matches a local one apart from latency |
| `check-output` | Read the check run's title, summary, and `details_url`. Often enough to identify a failing test; sometimes only enough to know *that* it failed. When it's uninformative the driver reports and links out rather than guessing |
| `none` | Red is red. Report and ask |
| `auto` | Use Actions logs when the check belongs to an Actions run, otherwise fall back to `check-output` |

**Observation is universal.** Whatever the provider, results reach the driver as check runs and commit statuses on the head commit — Actions, Xcode Cloud, CircleCI, Buildkite, Bitrise, Jenkins via the status API. The merge gate reads those, so it needs no provider-specific logic.

### Review

| Key | Default | Meaning |
|---|---|---|
| `review.required` | `[]` | Reviewers that must have seen the current head. `[]` means no AI-reviewer gate |
| `review.changes_requested_blocks` | `true` | An outstanding `CHANGES_REQUESTED` blocks the merge |
| `review.threads_must_resolve` | `true` | Every review thread must be resolved |

`review.required` is a **list**, so a repo can require more than one reviewer:

```yaml
review:
  required:
    - logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"]
    - check: "Claude Code Review"
```

Each entry is satisfied when **any** of these is true for the current head commit:

- a review by one of its `logins` at that commit, or
- an inline review-thread comment by one of them at that commit, or
- a check run named by its `check` at that commit that **actually ran and reported something**: `status == completed`, a conclusion other than `skipped` or `cancelled`, **and** a non-empty `output.title` or `output.summary`. Any conclusion otherwise counts, including `failure` and `neutral`.

That last one matters for CI-based reviewers: a clean pass leaves no comment, so the check run is the only proof it looked. Login matching is case-insensitive and ignores a trailing `[bot]`.

**Why conclusion is deliberately ignored here.** This gate answers one narrow question — *did the reviewer evaluate this commit?* — and a completed check answers it regardless of verdict. A review that found three bugs still reviewed the head. Three distinct questions used to ride on this one signal, and they're now separated:

| Question | Answered by |
|---|---|
| Did the reviewer look at this commit? | This gate — a completed check at the head SHA |
| Were its findings addressed? | `threads_must_resolve` |
| Must the review check itself be green? | The checks gate — name it in `ci.required` |

Keeping them apart is what lets one gate work for reviewers that signal findings by *failing* and reviewers that never fail by design. Anthropic's managed Code Review is the latter: its check run always completes `neutral` so it can never block a merge through branch protection. Requiring `success` here would mean its proof never arrives, and the merge would wait forever on a reviewer that had already done its job.

**Why a green check alone isn't enough.** This is the one direction where being permissive is unsafe, and it bites in more ways than it first appears.

A review workflow that doesn't review still produces a completed check run. It happens when a guard condition is false, a required secret is missing, the PR is a draft — or, in a case observed on this very repository, when `claude-code-action` refuses to run because the workflow file differs from the copy on the default branch. In that last case the *action* skipped while the *job* concluded `success`, ten seconds in, having read nothing. A conclusion-based rule counts that as a review.

So proof requires an artifact, not an exit code. A check run must carry output — a title or summary the reviewer wrote — for it to count. A job that exits 0 without reporting anything is indistinguishable from a job that never looked, and should be treated as the latter.

The failure this prevents is the worst kind: the gate reports satisfied while measuring nothing, and it looks identical to a healthy pass. A reviewer that can't run should fail loudly instead — which is why the shipped workflow has no graceful-skip guard.

Only diff-anchored comments create resolvable threads, so a reviewer must post **inline** comments for `threads_must_resolve` to mean anything.

### Reviewer setups

All four are first-class, and they compose — require Copilot *and* a Claude check if you want both.

| Setup | Config | Notes |
|---|---|---|
| **Managed Claude Code Review** | `required: [{ check: "Claude Code Review" }]` | Enabled by an org Owner at [claude.ai/admin-settings/claude-code](https://claude.ai/admin-settings/claude-code), not by a file in this repo. Team/Enterprise, research preview. Set Review Behavior to **After every push** so re-reviews track the head and threads auto-resolve when you fix what was flagged |
| **Claude via GitHub Actions** | `required: [{ check: "<job name>" }]` | A workflow using `anthropics/claude-code-action@v1` with the `code-review` plugin on `[opened, synchronize]`. Any plan; runs in your own CI; needs an `ANTHROPIC_API_KEY` repo secret |
| **GitHub Copilot** | `required: [{ logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"] }]` | Enable the "Review new pushes" ruleset so anchors track the head |
| **Humans only, or nobody** | `required: []` | Gates for `CHANGES_REQUESTED` and thread resolution still apply to human reviews |

See [review-setup.md](review-setup.md) for the full walkthrough of each.

### Stuck detection

| Key | Default | Meaning |
|---|---|---|
| `stuck.max_cycles` | `5` | Consecutive wakes where a gate fails for the same reason, with an unmoved head, before the phase is marked `Blocked` |

Counted per row, so one wedged platform never stalls the others.

---

## YOLO

YOLO controls exactly one thing: **who presses merge.**

| | YOLO **on** | YOLO **off** |
|---|---|---|
| Implement, open PR, watch | driver | driver |
| Fix failing CI | driver | driver |
| Address review comments, resolve threads | driver | driver |
| Evaluate the gates | driver | driver |
| **Press merge** | **driver, once gates pass** | **you** — the driver pings with the PR link and a gate summary |
| Start the next phase after merge | driver | **driver** |

**The next phase always continues after a merge, in both modes.** Merge from the GitHub mobile app with YOLO off and the driver notices, records it, and starts whatever that unblocks. Turning YOLO off buys a review checkpoint, not a manual pipeline.

**YOLO also decides where UAT checklists go.** With it off, every PR carries its own phase's manual-test checklist, because you're there to read it. With it on, phases merge unattended and UAT is deferred to a cumulative checklist on the final PR. Toggling mid-plan is safe — `UAT-pending` in Driver State tracks what hasn't reached a human, so switching off mid-plan hands you the backlog along with the current phase. See [When UAT reaches a human](format.md#when-uat-reaches-a-human).

It lives in the plan's **Driver State** block, not front matter, because it's runtime state — say `yolo on` or `yolo off` and it takes effect on the next gate evaluation, including for PRs already open.

A repo can set `yolo: false` in front matter to stay manual no matter what the toggle says. The effective rule is `YOLO(state) AND repo.yolo(config)` — config can only ever be more conservative.

---

## Protected default branches

If the home repo's default branch rejects direct commits, set:

```yaml
plan_writes: plan-pr
```

Each status transition then becomes a one-file PR with auto-merge enabled, instead of a direct commit. Noisier, but still durable and still resume-safe. The driver detects the rejection on its first transition and tells you once.

---

## Worked examples

**A single repo with GitHub Actions and Copilot** — the common case:

```yaml
phases:
  project: my-app
  home_repo: me/my-app
  repos:
    me/my-app:
      review:
        required: [{ logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"] }]
```

**A repo with no CI and no bot reviewer:**

```yaml
phases:
  project: my-notes
  home_repo: me/my-notes
  repos:
    me/my-notes:
      verify: none
      ci: { allow_none: true }
```

Every gate still runs; they just have nothing to block on. `changes_requested_blocks` and `threads_must_resolve` still apply to human reviewers.

**Cross-platform, mixed everything** — see [`examples/cross-platform.md`](../examples/cross-platform.md).

---

## Configurations that can't work

The planner refuses to write a plan whose gates can never pass, because that's a wall you'd otherwise hit only after your first PR is already open:

- a name in `ci.required` that no workflow produces
- a login in `review.required` that has never reviewed in that repo
- `ci.allow_none: false` on a repo with no CI configured at all

Copy-paste starting points for common setups live in [`profiles/`](../profiles/).

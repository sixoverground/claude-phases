# Reviewer setup

A code reviewer is optional. Nothing here is required to run a plan — but if you want the merge gate to mean something beyond "CI is green", you want one.

Four setups are supported, they compose, and none of them is more "correct" than the others. Pick by what your plan and organization allow.

| Setup | Cost | Plan required | Configured where | Can the planner set it up? |
|---|---|---|---|---|
| [Claude via GitHub Actions](#claude-via-github-actions) | Your subscription, or metered API + Actions minutes | **Any**, incl. Pro and Max | A workflow file in your repo | **Yes** |
| [Managed Claude Code Review](#managed-claude-code-review) | ~$15–25 per review | Team or Enterprise | claude.ai admin settings | No — prints steps |
| [GitHub Copilot](#github-copilot) | Per your Copilot plan | Any with Copilot | GitHub repo settings | No — prints steps |
| [Humans only, or nobody](#humans-only-or-nobody) | Free | Any | Nothing to configure | N/A |

On Pro or Max, start with the Actions setup — it authenticates against your existing subscription and needs no admin access.

---

## Managed Claude Code Review

Anthropic's hosted reviewer. A fleet of agents analyzes the diff against your full codebase, verifies candidate findings against actual behavior to cut false positives, and posts results as inline comments tagged by severity.

**Setup** — an org Owner does this once, outside the repo:

1. Go to [claude.ai/admin-settings/claude-code](https://claude.ai/admin-settings/claude-code) and find the Code Review section.
2. Click **Setup** and install the Claude GitHub App on your organization.
3. Select the repositories to enable.
4. Set **Review Behavior** to **After every push**.

That last choice matters. The merge gate needs proof the reviewer evaluated the *current* head, and push-triggered reviews both re-review on every push and auto-resolve threads when you fix what was flagged. "Once after PR creation" leaves the gate unsatisfied as soon as the driver pushes a fix.

```yaml
review:
  required: [{ check: "Claude Code Review" }]
```

**Requirements and limits.** Team or Enterprise plan; Owner or Primary Owner role in the Claude organization plus permission to install GitHub Apps; not available with Zero Data Retention enabled. It's in research preview, so availability may vary.

**If you don't see the Code Review section**, it's one of: you're not on Team or Enterprise, you don't hold Owner or Primary Owner, your org has Zero Data Retention on, or the preview hasn't reached your org. None of those can be worked around from the repo — use the Actions setup below instead, which runs on any plan.

**Its check run always completes `neutral`**, by design, so it can never block a merge through branch protection. This library accounts for that: `neutral` passes the checks gate, and proof-of-review asks only whether the check *completed*, not what it concluded. Requiring `success` — which is what a naive implementation does — would deadlock every merge on a reviewer that had already done its job.

**Tune it** with a `REVIEW.md` at your repo root: severity calibration, a cap on nits, paths to skip, repo-specific checks. It's injected at highest priority into every review agent.

---

## Claude via GitHub Actions

Runs review in your own CI. Works on **any plan, including Pro and Max** — which makes this the practical default, since the managed service is Team/Enterprise only.

### Authenticate with your subscription (Pro and Max)

You do not need a pay-as-you-go API key. Generate an OAuth token from your existing subscription:

```bash
claude setup-token
```

Add the output as a repository secret named `CLAUDE_CODE_OAUTH_TOKEN` (Settings → Secrets and variables → Actions), then:

`.github/workflows/code-review.yml`:

```yaml
name: Code Review

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  contents: read
  pull-requests: write
  issues: write
  id-token: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      # Required. The action restores trusted config (CLAUDE.md, .claude/, ...)
      # from origin/main before running, which needs a git repo present.
      # Without it the job fails with "fatal: not a git repository".
      - uses: actions/checkout@v4

      - uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          plugin_marketplaces: "https://github.com/anthropics/claude-code.git"
          plugins: "code-review@claude-code-plugins"
          # --comment makes the review POST its findings. Without it the
          # review runs, finds real issues, and reports them only to the job
          # log — the PR gets nothing.
          prompt: "/code-review:code-review --comment ${{ github.repository }}/pull/${{ github.event.pull_request.number }}"
          # And this lets the posting actually succeed. Without it the gh
          # calls are denied by the tool-permission layer, the job still
          # concludes `success`, and the PR still gets nothing.
          claude_args: |
            --allowedTools "Bash(gh api:*),Bash(gh pr:*)"
```

Reviews then draw on your subscription's usage rather than metered API spend.

### Both flags are required, and neither fails loudly

This pair cost an afternoon to work out, so it is worth stating plainly:

| Missing | Symptom |
|---|---|
| `--comment` | Review runs fully, findings appear **only in the job log**, check is green |
| `--allowedTools` | Review runs fully, tries to post, every `gh` call is denied, check is **still green** |

In both cases the job concludes `success` and the PR looks reviewed. Nothing in GitHub's UI distinguishes that from a genuine clean pass — which is why the merge gate here refuses to treat a bare green check as proof of review.

Verify on a PR with a deliberate flaw. If no inline comment appears, read the job log rather than trusting the check.

### The workflow does nothing until it's on the default branch

`claude-code-action` refuses to run when the workflow file differs from the copy on the repository's default branch, logging:

```
Skipping action due to workflow validation: The workflow file must exist and have
identical content to the version on the repository's default branch.
```

This is a security control, and a sensible one — otherwise a PR author could edit the review workflow in their own PR to weaken or disable the review of that PR. The consequence is that **the PR which introduces the workflow is never reviewed by it**, and neither is any PR that modifies it. Reviews begin with the next PR after it merges.

The trap: the job still concludes **`success`** in that state, having reviewed nothing. Don't read a green check on the introducing PR as confirmation the reviewer works — it only confirms the workflow parses. Verify on the *next* PR, and see [configuration.md](configuration.md#review) for how the merge gate decides what counts as proof that a review happened.

### Other authentication options

| Method | Input | When |
|---|---|---|
| Subscription OAuth | `claude_code_oauth_token` | Pro and Max. The default choice |
| API key | `anthropic_api_key` | Metered API billing, or no interactive machine to run `claude setup-token` on |
| Workload identity federation | `anthropic_federation_rule_id` + org and service-account ids | Organizations avoiding static credentials. Note: inline comment classification is skipped under federation |
| Bedrock / Vertex / Foundry | `use_bedrock`, `use_vertex` | Enterprise cloud deployments |

**Whichever you choose, you must add the secret yourself.** Nothing can do it for you — not the planner, not any tool with repository write access. A review workflow with a missing secret fails on every PR, which is worse than having no reviewer at all, so add the secret before or alongside committing the workflow.

The OAuth token is tied to your account and does not last forever; if reviews start failing to authenticate, re-run `claude setup-token` and update the secret.

The `synchronize` trigger is what keeps review anchored to the head as the driver pushes fixes. Without it the gate stalls after the first push.

```yaml
review:
  required:
    - check: "Claude review"   # the job's `name:`, as it appears on the PR
      proof: completed
```

Confirm the check name on a real PR before trusting it — it's the job name, which you control, and getting it wrong means the gate waits forever for a check that never appears under that name.

**`proof: completed` is deliberate here.** On a clean pass this reviewer leaves nothing the gate can anchor to:

| Signal | On a clean pass |
|---|---|
| Inline comments | none — it had nothing to say |
| A review at the head SHA | none — reviews are only created when there are findings |
| Check run `output` | empty (`title`, `summary`, `text` all `""`) |
| A top-level PR comment | yes — but an issue comment, so no commit anchor |

With the default `proof: output` the gate would block every clean review permanently. The cost of `completed` is that a skipped or no-op job also counts as a review, so pair it with the workflow above having no graceful-skip guard — a reviewer that cannot run should be red, not absent.

---

## GitHub Copilot

**Setup**, in GitHub repo or org settings: enable Copilot code review, and turn on the **"Review new pushes"** ruleset so it re-reviews as the branch moves.

```yaml
review:
  required: [{ logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"] }]
```

Three logins because the reporting identity has varied; matching is case-insensitive and ignores a trailing `[bot]`. Copilot posts inline comments natively, so thread resolution works without extra configuration.

---

## Humans only, or nobody

```yaml
review:
  required: []
```

This is the default, and it is a supported configuration rather than a degraded one. The other gates still do real work: an outstanding `CHANGES_REQUESTED` from any human blocks, and every review thread must be resolved before a merge.

If you want a human approval to be strictly required before anything merges, the better tool is GitHub branch protection — or simply turn YOLO off, which stops the driver at a ready-to-merge ping and leaves the merge to you.

---

## Requiring more than one

Entries compose. Both must have seen the head:

```yaml
review:
  required:
    - logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"]
    - check: "Claude Code Review"
```

Expect this to be slower and noisier — two reviewers means two sets of inline comments to address and resolve before the gate opens. Worth it when you're comparing reviewers; rarely worth it as a steady state.

---

## Verifying your setup

Open a throwaway PR and check three things:

1. **The reviewer actually ran** — a check run or a review appears within a few minutes.
2. **The check name matches your config exactly**, including spaces and capitalization.
3. **Comments are inline**, attached to diff lines, not a single top-level comment. Only diff-anchored comments create resolvable threads, so a top-level-only reviewer makes `threads_must_resolve` meaningless.

Then push a second commit and confirm the reviewer re-runs. If it doesn't, the merge gate will stall the first time the driver pushes a fix — which looks like waiting for CI, not like a misconfiguration, so it's worth catching now.

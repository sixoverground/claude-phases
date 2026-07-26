# Reviewer setup

A code reviewer is optional. Nothing here is required to run a plan — but if you want the merge gate to mean something beyond "CI is green", you want one.

Four setups are supported, they compose, and none of them is more "correct" than the others. Pick by what your plan and organization allow.

| Setup | Cost | Plan required | Configured where | Can the planner set it up? |
|---|---|---|---|---|
| [Managed Claude Code Review](#managed-claude-code-review) | ~$15–25 per review | Team or Enterprise | claude.ai admin settings | No — prints steps |
| [Claude via GitHub Actions](#claude-via-github-actions) | API tokens + Actions minutes | Any | A workflow file in your repo | **Yes** |
| [GitHub Copilot](#github-copilot) | Per your Copilot plan | Any with Copilot | GitHub repo settings | No — prints steps |
| [Humans only, or nobody](#humans-only-or-nobody) | Free | Any | Nothing to configure | N/A |

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

Runs the same review logic in your own CI. Works on any plan.

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
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          plugin_marketplaces: "https://github.com/anthropics/claude-code.git"
          plugins: "code-review@claude-code-plugins"
          prompt: "/code-review:code-review ${{ github.repository }}/pull/${{ github.event.pull_request.number }}"
```

**You must add an `ANTHROPIC_API_KEY` repository secret** (Settings → Secrets and variables → Actions). Nothing can do this for you — not the planner, not any tool with repo write access.

The `synchronize` trigger is what keeps review anchored to the head as the driver pushes fixes. Without it the gate stalls after the first push.

```yaml
review:
  required: [{ check: "review" }]     # the job name, as it appears on the PR
```

Confirm the check name on a real PR before trusting it — it's the job name, which you control, and getting it wrong means the gate waits forever for a check that never appears under that name.

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

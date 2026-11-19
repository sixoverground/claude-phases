# Reviewer setup

An automated code reviewer is optional. A plan can run without one, but adding a reviewer gives the merge gate evidence beyond passing CI.

Six setups are supported, and you can combine them. Choose based on your Claude plan, organization permissions, and preferred review behavior.

| Setup | Cost | Plan required | Configured where | Can the planner set it up? |
|---|---|---|---|---|
| [Claude via GitHub Actions](#claude-via-github-actions) | Your subscription, or metered API + Actions minutes | **Any**, incl. Pro and Max | A workflow file in your repo | **Yes** |
| [Managed Claude Code Review](#managed-claude-code-review) | ~$15–25 per review | Team or Enterprise | claude.ai admin settings | No, prints steps |
| [GitHub Copilot](#github-copilot) | Per your Copilot plan | Any with Copilot | GitHub repo settings | No, prints steps |
| [OpenAI Codex](#openai-codex) | Per your ChatGPT plan | Any with Codex | ChatGPT / GitHub app settings | No, prints steps |
| [GitLab with a local Codex review](#gitlab-with-a-local-codex-review) | Per your ChatGPT plan, on a runner you own | Any with Codex | A CI job, a runner and a token | No, prints steps |
| [Humans only, or nobody](#humans-only-or-nobody) | Free | Any | Nothing to configure | N/A |

For most Pro or Max users, start with [Claude via GitHub Actions](#claude-via-github-actions). It uses your existing subscription and does not require organization administrator access.

Whichever reviewer you choose, finish with [Verifying your setup](#verifying-your-setup). A configured workflow and a green check do not necessarily prove that a review occurred.

---

## Managed Claude Code Review

Anthropic's hosted reviewer. A fleet of agents analyzes the diff against your full codebase, verifies candidate findings against actual behavior to cut false positives, and posts results as inline comments tagged by severity.

**Setup.** An org Owner does this once, outside the repo:

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

**If you don't see the Code Review section**, it's one of: you're not on Team or Enterprise, you don't hold Owner or Primary Owner, your org has Zero Data Retention on, or the preview hasn't reached your org. None of those can be worked around from the repo. Use the Actions setup below instead, which runs on any plan.

**Its check run always completes `neutral`**, by design, so it cannot block a merge through branch protection. This library treats `neutral` as passing and asks separately whether the review completed. Requiring `success` would deadlock every merge after the reviewer had already done its job.

**Tune it** with a `REVIEW.md` at your repo root: severity calibration, a cap on nits, paths to skip, repo-specific checks. It's injected at highest priority into every review agent.

---

## Claude via GitHub Actions

Runs review in your own CI. Works on **any plan, including Pro and Max**, which makes this the practical default, since the managed service is Team/Enterprise only.

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
          # log, and the PR gets nothing.
          prompt: "/code-review:code-review --comment ${{ github.repository }}/pull/${{ github.event.pull_request.number }}"
          # And this lets the posting actually succeed. Without it the gh
          # calls are denied by the tool-permission layer, the job still
          # concludes `success`, and the PR still gets nothing.
          claude_args: |
            --allowedTools "Bash(gh api:*),Bash(gh pr:*)"
```

Reviews then draw on your subscription's usage rather than metered API spend.

### Both flags are required, and neither fails loudly

Both flags are necessary, and both failure modes are easy to miss:

| Missing | Symptom |
|---|---|
| `--comment` | Review runs fully, findings appear **only in the job log**, check is green |
| `--allowedTools` | Review runs fully, tries to post, every `gh` call is denied, check is **still green** |

In both cases the job concludes `success` and the PR looks reviewed. Nothing in GitHub's UI distinguishes that from a genuine clean pass, which is why the merge gate here refuses to treat a bare green check as proof of review.

Verify on a PR with a deliberate flaw. If no inline comment appears, read the job log rather than trusting the check.

### The workflow does nothing until it's on the default branch

`claude-code-action` refuses to run when the workflow file differs from the copy on the repository's default branch, logging:

```
Skipping action due to workflow validation: The workflow file must exist and have
identical content to the version on the repository's default branch.
```

This is a security control, and a sensible one. Otherwise a PR author could edit the review workflow in their own PR to weaken or disable the review of that PR. The consequence is that **the PR which introduces the workflow is never reviewed by it**, and neither is any PR that modifies it. Reviews begin with the next PR after it merges.

The trap: the job still concludes **`success`** in that state, having reviewed nothing. Don't read a green check on the introducing PR as confirmation the reviewer works. It only confirms the workflow parses. Verify on the *next* PR, and see [the configuration reference](../skills/phase-planner/references/configuration.md#review) for how the merge gate decides what counts as proof that a review happened.

### Other authentication options

| Method | Input | When |
|---|---|---|
| Subscription OAuth | `claude_code_oauth_token` | Pro and Max. The default choice |
| API key | `anthropic_api_key` | Metered API billing, or no interactive machine to run `claude setup-token` on |
| Workload identity federation | `anthropic_federation_rule_id` + org and service-account ids | Organizations avoiding static credentials. Note: inline comment classification is skipped under federation |
| Bedrock / Vertex / Foundry | `use_bedrock`, `use_vertex` | Enterprise cloud deployments |

**Whichever you choose, you must add the secret yourself.** Nothing can do it for you. Not the planner, not any tool with repository write access. A review workflow with a missing secret fails on every PR, which is worse than having no reviewer at all, so add the secret before or alongside committing the workflow.

The OAuth token is tied to your account and does not last forever; if reviews start failing to authenticate, re-run `claude setup-token` and update the secret.

The `synchronize` trigger is what keeps review anchored to the head as the driver pushes fixes. Without it the gate stalls after the first push.

```yaml
review:
  required:
    - check: "Claude review"   # the job's `name:`, as it appears on the PR
      proof: completed
```

Confirm the check name on a real PR before trusting it. It's the job name, which you control, and getting it wrong means the gate waits forever for a check that never appears under that name.

**`proof: completed` is deliberate here.** On a clean pass this reviewer leaves nothing the gate can anchor to:

| Signal | On a clean pass |
|---|---|
| Inline comments | none: it had nothing to say |
| A review at the head SHA | none: reviews are only created when there are findings |
| Check run `output` | empty (`title`, `summary`, `text` all `""`) |
| A top-level PR comment | yes, but an issue comment, so there is no commit anchor |

With the default `proof: output` the gate would block every clean review permanently. The cost of `completed` is that a skipped or no-op job also counts as a review, so pair it with the workflow above having no graceful-skip guard. A reviewer that cannot run should be red, not absent.

---

## GitHub Copilot

**Setup**, in GitHub repo or org settings: enable Copilot code review, and turn on the **"Review new pushes"** ruleset so it re-reviews as the branch moves.

```yaml
review:
  required: [{ logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"] }]
```

Three logins because the reporting identity has varied; matching is case-insensitive and ignores a trailing `[bot]`. Copilot posts inline comments natively, so thread resolution works without extra configuration.

---

## OpenAI Codex

**Setup**, in ChatGPT's Codex settings: connect the GitHub organization and enable code review for the repositories you want. Codex reviews as a GitHub App and posts inline comments, so thread resolution works without extra configuration.

```yaml
review:
  required:
    - logins: ["chatgpt-codex-connector"]
      rereview: optional
```

**Read the login off a real review before trusting it.** Open the first PR Codex reviews and check the author, rather than copying the value above on faith. App logins change, and a wrong one blocks every phase.

### Smart detect is why `rereview` exists

Codex's review trigger has a **smart detect** mode, often the default, where it reviews a PR once and then decides per push whether another look is warranted. That is good behaviour from a reviewer and bad news for a head-anchored gate: the driver pushes a CI fix, Codex sensibly stays quiet, and gate 6 waits forever for proof that was never coming.

Two ways out, in order of preference:

1. **Set Codex to review every push**, and leave `rereview` at its default. The gate then holds real proof for every commit it merges. Always prefer this when the setting is available to you.
2. **Set `rereview: optional`.** The entry is then also satisfied by a review of an earlier commit on the same PR, once `rereview_grace` (default `15m`) has passed since the head was pushed.

Option 2 allows the driver to merge a commit Codex did not read. To limit that risk, **a PR with no sign of Codex at all never times out**. The gate treats total silence as a broken integration, not as a decision to skip review.

### Codex only reviews the connected user's PRs

The integration attaches to the account that connected it. A pull request opened by anyone else, including a bot or app identity the driver might be authenticating as, gets no review, no check, and no reaction. Nothing reports an error, because from Codex's side nothing was ever asked.

That makes the opener identity part of your merge gate. If phase PRs arrive under a bot login, gate 6 waits forever on a review that was never requested, and YOLO stops with nothing red to look at.

The way it actually happens: a cloud session opens the PR with `gh pr create` rather than the GitHub MCP tools. `gh` there is authenticated as the integration, not as you, so the PR is opened by that app. The driver is told to use the MCP tools for exactly this reason. If you find a phase PR authored by something other than your account, that is the thing to check.

It is the commit *author* that does not matter here: a `Co-Authored-By` trailer has no bearing on whether the reviewer runs.

### The thumbs up is a verdict

Smart detect can also decide that an entire PR needs no review. When it does, it leaves a 👍 on the PR, the timeline reads `chatgpt-codex-connector[bot] reacted with thumbs up emoji`, and it posts nothing else.

The driver counts that reaction. Left after the current head was pushed, it satisfies the gate outright: Codex evaluated this commit and said so. Left earlier, it still counts as a sign that Codex has the PR, which is the precondition `rereview: optional` needs before a decline can be inferred from silence.

Without that, a small PR could be reviewed correctly by Codex and still wedge the driver forever, because "reviewed it and found nothing to say" and "never connected" produce the same empty review list. The reaction is the only thing that separates them, and it was found the way most of this file was: a phase stuck behind a reviewer that had already answered.

So if Codex leaves neither a review nor a reaction on your first phase PR, that is the integration failing, and `rereview: optional` will correctly refuse to paper over it. Fix the connection rather than lowering the gate further.

---

## GitLab with a local Codex review

GitLab has no hosted Codex reviewer, so on a GitLab project the review runs as a CI job on a runner you own, and reports through the [review contract](review-contract.md): inline threads for its findings, then a marker note naming the commit it reviewed. The driver gates on that marker with a `marker` entry. The tool that does this for Codex is [`codex-mr-review`](https://github.com/sixoverground/codex-mr-review). This section describes it at **v0.1.0**; its [README](https://github.com/sixoverground/codex-mr-review/blob/v0.1.0/README.md) is the authority for anything here that changes between versions, such as variables and flags.

### Install the tool on the runner

The review needs a machine with the Codex CLI logged in, which usually means a Mac with a [shell-executor runner](https://docs.gitlab.com/runner/install/osx/). Use a dedicated, non-admin macOS user for the runner, because Codex's read-only sandbox can still read anything that user can. As that user, with Node 20 or later and git:

```sh
npm install -g github:sixoverground/codex-mr-review#v0.1.0
codex-mr-review --version
codex login
bash -lc 'command -v codex codex-mr-review'
```

The last line checks that both are on the `PATH` of a login shell, which is what the shell executor runs. Register the runner with the `shell` executor and a tag, and leave **Protected** off, as [hygiene](../skills/phase-planner/references/hygiene.md#gitlab) explains for any runner a phase MR's pipeline needs. Keep the runner user's `~/.codex/AGENTS.md` empty: the tool ignores Codex's `config.toml` but Codex still reads that file, and the tool warns when it has content.

### Add the job

In the project's `.gitlab-ci.yml`:

```yaml
include:
  - remote: https://raw.githubusercontent.com/sixoverground/codex-mr-review/v0.1.0/templates/codex-review.gitlab-ci.yml

codex-review:
  tags: [your-runner-tag]
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

**Keep the `rules:` in your own file**, even though the template has the same rule. GitLab creates merge request pipelines only when the project's own `.gitlab-ci.yml` has a job rule or `workflow: rules` that matches them; a rule that arrives through `include:` does not count ([GitLab's documentation](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/#configure-merge-request-pipelines)). Without it, a project with no other merge request rule never runs the review, and gate 6 waits for a marker that never comes. A project that already has `workflow: rules` creating merge request pipelines can leave it out.

The template's job runs on every merge request pipeline in the `test` stage (set `stage:` if the project has none), reviews from the MR's diff base, and in a merged results pipeline reviews the source branch head, so its marker names the commit the driver gates on. It reviews at reasoning effort `high` by default. Change the model, effort or reviewer name through the variables listed in the tool's README.

Two settings would quietly break the gate, and the planner's hygiene checklist names both:

- **The job must not be `allow_failure: true`.** A review that fails posts no marker, and gate 6 blocks, which is right. But a job allowed to fail also shows gate 3 a pass, so the only sign of a broken reviewer is a phase waiting on gate 6 for a reason the checks do not show.
- **Its token variable must not be protected.** Phase branches are not protected, and GitLab withholds a protected variable from their pipelines, so the job fails on every phase MR saying the token is missing.

### The token, and why it is a second identity

Under **Settings > CI/CD > Variables**, add `CODEX_MR_REVIEW_TOKEN`: a project access token or a dedicated bot user's token, with the `api` scope and at least the **Developer** role. Mark it **masked**, and not **protected**, as above.

**Use a different identity from the driver's.** The driver acts as you, through `glab`. If the reviewer posted as you too, two things would stop working:

- `logins` would mean nothing. It is there so that only the reviewer's account can write a marker that counts, and an account the driver also posts as could be any author.
- The [watcher](../skills/phase-driver/references/watching.md#gitlab) ignores notes from the account the driver acts as, so it would never wake for the reviewer's findings or marker. The phase would move only at the fallback check-in.

Two identities are the supported arrangement.

### The config

Read the reviewer token's username off its first marker note rather than guessing it: a project access token's bot user has a generated username, such as `project_123_bot_<hash>`.

```yaml
review:
  required:
    - marker: "codex"
      logins: ["<the reviewer token's username>"]
```

`codex` is the template's default reviewer name, `CODEX_MR_REVIEW_REVIEWER`. The [`review-codex-local.yml`](../profiles/review-codex-local.yml) profile has this with its comments. `rereview` and `proof` do not apply to a `marker` entry: a review that runs posts a marker, and one that does not leaves the gate blocked.

### How the driver treats its findings

By the same rules as a Codex review on GitHub, in [Answering a review](../skills/phase-driver/SKILL.md#answering-a-review). Nothing in them changes for this reviewer.

**Asking it to look again.** Post a note on the MR whose whole text is `@codex review`, from your own account, and a driver that is running answers it by starting a new merge request pipeline, which runs the review job on the current head. Nothing answers it when no driver is running: the note is plain text to GitLab, and the tool runs only in a pipeline. Retry the job from the MR's pipeline page instead.

### On GitHub

A reviewer that meets the contract can gate a GitHub repo through the same `marker` entry, since gate 6 reads markers on either forge. `codex-mr-review` does not post to GitHub. On GitHub, use [OpenAI Codex](#openai-codex) above, or a reviewer of your own that emits the contract.

### Another reviewer through the same job

The template's hidden job, `.codex-review`, carries the setup any reviewer needs: merge request pipelines only, full history, one review per MR at a time, and cancelled by a newer push. Extend it with your own script to run another reviewer, a Claude review for example, as long as that reviewer [emits the contract](review-contract.md): findings as inline resolvable threads, then, only after the review succeeded, a top-level note with `<!-- phases:review v=1 reviewer=<name> sha=<full sha> -->` naming its own reviewer name and the commit the pipeline ran on.

```yaml
other-review:
  extends: .codex-review
  tags: [your-runner-tag]
  resource_group: other-review-$CI_MERGE_REQUEST_PROJECT_ID-$CI_MERGE_REQUEST_IID
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - my-reviewer --base "$CI_MERGE_REQUEST_DIFF_BASE_SHA" --reviewer my-reviewer
```

Give it its own reviewer name, its own `resource_group` and its own `marker` entry, and keep its `rules:` in your file for the reason above. The tool's README lists the rules it follows that yours should too: the sha comes from the pipeline and never from model output, model text is scrubbed of the marker prefix before posting, and a failed review posts no marker.

### What to check on the first merge request

Follow [Verifying your setup](#verifying-your-setup) below, with the GitLab steps.

---

## Humans only, or nobody

```yaml
review:
  required: []
```

This is the default, and it is a supported configuration rather than a degraded one. The other gates still do real work: an outstanding `CHANGES_REQUESTED` from any human blocks, and every review thread must be resolved before a merge.

If you want a human approval to be strictly required before anything merges, the better tool is GitHub branch protection, or simply turn YOLO off, which stops the driver at a ready-to-merge ping and leaves the merge to you.

---

## Requiring more than one

Entries compose. Both must have seen the head:

```yaml
review:
  required:
    - logins: ["copilot-pull-request-reviewer", "github-copilot", "copilot"]
    - check: "Claude Code Review"
```

Expect this to be slower and noisier. Two reviewers means two sets of inline comments to address and resolve before the gate opens. Worth it when you're comparing reviewers; rarely worth it as a steady state.

---

## Verifying your setup

Open a throwaway PR and check three things:

1. **The reviewer actually ran.** A check run or a review appears within a few minutes.
2. **The check name matches your config exactly**, including spaces and capitalization.
3. **Comments are inline**, attached to diff lines, not a single top-level comment. Only diff-anchored comments create resolvable threads, so a top-level-only reviewer makes `threads_must_resolve` meaningless.

Then push a second commit and confirm the reviewer re-runs. If it doesn't, the merge gate will stall the first time the driver pushes a fix, which looks like waiting for CI, not like a misconfiguration, so it's worth catching now.

If it doesn't re-run **by design**, because the reviewer decides per push whether another look is warranted, that is a `rereview: optional` case rather than a broken setup. See [Smart detect is why `rereview` exists](#smart-detect-is-why-rereview-exists).

### On GitLab

Open a throwaway merge request with a deliberate flaw, and check four things:

1. **The review job ran** in the MR's pipeline and passed. If the MR has no pipeline at all, the project's own file has no merge request rule: see **Add the job** above. If it is `pending`, no online runner has its tags. If it failed saying the token is missing, the variable is protected.
2. **Its findings are threads on diff lines**, under the reviewer token's account, not yours.
3. **The summary note ends with a marker** naming the reviewer and the MR's head sha in full. Compare it with the head shown on the MR's **Commits** tab. Read the note's author here: that username goes in `logins`.
4. **A second push produces a second marker**, naming the new head. A job that ran once and not again leaves the gate blocked the first time the driver pushes a fix.

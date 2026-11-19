# Configuration profiles

These files are copy-and-paste starting points for common CI and review setups. Place one CI profile and one review profile in a plan's YAML front matter, either under `defaults:` or under a repository in `repos:`.

Treat the values as examples, especially check names. Confirm them against a real pull request before relying on the merge gate.

Pick one CI profile and one review profile per repo. They compose. On a forge other than GitHub, add that forge's profile too.

| Forge | When |
|---|---|
| none | GitHub on github.com, the default. Nothing to set |
| [`forge-gitlab.yml`](forge-gitlab.yml) | GitLab, on gitlab.com or a self-managed instance |

| CI | When |
|---|---|
| [`ci-github-actions.yml`](ci-github-actions.yml) | Workflows in `.github/workflows/` |
| [`ci-xcode-cloud.yml`](ci-xcode-cloud.yml) | Xcode Cloud, or anything that starts on its own PR conditions |
| [`ci-external.yml`](ci-external.yml) | CircleCI, Buildkite, Jenkins, Bitrise: reports to GitHub, no Actions log API |
| [`ci-none.yml`](ci-none.yml) | No CI at all |
| [`ci-gitlab-runner-macos.yml`](ci-gitlab-runner-macos.yml) | GitLab CI on a self-hosted macOS runner. Use with `forge-gitlab.yml` |

| Review | When |
|---|---|
| [`review-claude-actions.yml`](review-claude-actions.yml) | Claude review in your own Actions workflow. Any plan |
| [`review-claude-managed.yml`](review-claude-managed.yml) | Anthropic's managed Code Review. Team/Enterprise |
| [`review-copilot.yml`](review-copilot.yml) | GitHub Copilot review |
| [`review-codex-local.yml`](review-codex-local.yml) | GitLab: Codex reviewing in your own CI, gated by its marker. Use with `forge-gitlab.yml` |
| [`review-humans-only.yml`](review-humans-only.yml) | People review; no bot gate |
| [`review-none.yml`](review-none.yml) | Nothing reviews |

See [the configuration reference](../skills/phase-planner/references/configuration.md) for every key, and [docs/review-setup.md](../docs/review-setup.md) for how to actually turn each reviewer on.

# Contributing

Thanks for contributing. Start with the two constraints below: prose changes can change runtime behavior, and several files jointly define the plan format.

## The skills are prose, so edits are behaviour changes

`skills/phase-driver/SKILL.md` and `skills/phase-planner/SKILL.md` are instructions read by a model, not code read by an interpreter. Rewording a sentence can change what the driver does. Tightening a paragraph for style can quietly drop a rule.

When editing a skill:

* Say what behaviour you intend to change, even when the diff looks editorial.
* Prefer adding a named rule over rephrasing an existing one. The driver follows specifics far better than it follows tone.

## Keep the contract files in sync

`skills/phase-planner/references/format.md` specifies the plan file. `skills/phase-driver/SKILL.md` reads and writes it. `skills/phase-planner/references/plan-template.md` is what the planner starts from. A change to any one of them is usually a change to all three, and the driver's crash recovery is what breaks when they drift.

The same applies to `skills/phase-planner/references/configuration.md` and the `profiles/`: a new key needs a default, an off switch, and a profile that shows it in use.

The forge references are a contract of the same kind. `skills/phase-driver/references/forge-github.md` and `forge-gitlab.md` answer the same questions under the same headings, and `SKILL.md`, `gates.md`, `recovery.md` and `watching.md` say what to do in terms either answers. A rule added to one forge reference needs its counterpart in the other, or a sentence there saying why it does not apply. On the planner's side, `detection.md` and `detection-gitlab.md` pair the same way. `docs/review-contract.md` is the contract with reviewers built outside this repo, such as `codex-mr-review`: a change to the marker or the stamps changes what those tools must post, so it moves the contract's version and says what an older reviewer still does.

The spec lives inside the skill rather than in `docs/` so that `phase-planner` is self-contained: it's uploaded to claude.ai as a zip of its own directory, and anything outside that directory isn't there to read. Keep it that way. A reference in `skills/` may link out to the repo, but only with an absolute URL and only for further reading, never for something the skill needs to do its job.

## Test against a real repository

There is no unit test suite, and a skill that reads correctly can still behave badly. Before opening a PR that changes skill behavior:

1. Point the skills at a scratch repository with CI on it. A two-phase plan is enough.
2. Run a phase to a merge, with YOLO off.
3. Kill the session mid-phase and start a new one. Recovery from a cold start is the property most changes accidentally break.

On GitLab, use a scratch project on gitlab.com or your own instance, with a runner and a review job, as [`examples/gitlab-local.md`](examples/gitlab-local.md) did.

Say in the PR what you actually ran. "Reviewed by reading" is a fine answer when that is the truth; claiming a test that did not happen is worse than no test.

## Validate the plugin manifest

```bash
claude plugin validate . --strict
```

CI does not run this yet. Run it before you push if you touched anything under `.claude-plugin/`.

## Releasing

A release is the version in `.claude-plugin/plugin.json` reaching `main`. A pull request into a feature branch does not bump the version: the `Version bumped` check runs only on pull requests into `main`, and skips everywhere else. Work on a feature branch is bumped once, when that branch is prepared to reach `main`. `.github/workflows/release.yml` creates the tag, the GitHub release and the skill zips, from a push that changes the manifest or from the merged pull request, so a `[skip ci]` quoted in a squash message cannot skip it. Afterwards, `scripts/check-release.sh` says whether the version on `main` has its tag, its release and every zip, and prints the command that repairs it when it does not.

## Scope

Good contributions: a CI or review provider that the current model handles badly, a recovery case the driver gets wrong, a gate that deadlocks on a setup nobody anticipated, and a GitLab instance or setup the GitLab references get wrong.

**Adding a forge.** GitHub and GitLab are the two the skills support. A third, such as Gitea or Bitbucket, is one new reference per skill and no change to the rules:

1. `skills/phase-driver/references/forge-<forge>.md`, with every heading `forge-github.md` has, in the same order: Find, Open, Opener identity, Watch, The gates, Write the plan, Merge, Delete the branch, Milestone and integration change requests, Re-sync a branch, Issue fallback. Add what the forge needs on top, as `forge-gitlab.md` adds its setup, its working copy, and how to tell an unreachable forge from a refusal. Under a heading that does not apply, say so and why, as `forge-gitlab.md` does for the decline reaction.
2. `skills/phase-planner/references/detection-<forge>.md`, with the same headings as `detection.md`, plus refusals for whatever on that forge makes a gate wait forever.
3. The watcher template for it in `watching.md`, printing the same wake lines.
4. `forge` and its values in `configuration.md`, and a profile.

`SKILL.md` names no forge's API, and a new forge should need no change there beyond what the core already says about resolving `forge`. Open an issue first, and plan to drive one real plan on it before calling it supported.

## Style

Plain sentences. Say the thing, then stop. Avoid em-dashes where a comma or a full stop will do, and avoid the "not X, but Y" construction unless the contrast is the point.

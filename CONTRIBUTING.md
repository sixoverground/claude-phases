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

The spec lives inside the skill rather than in `docs/` so that `phase-planner` is self-contained: it's uploaded to claude.ai as a zip of its own directory, and anything outside that directory isn't there to read. Keep it that way. A reference in `skills/` may link out to the repo, but only with an absolute URL and only for further reading, never for something the skill needs to do its job.

## Test against a real repository

There is no unit test suite, and a skill that reads correctly can still behave badly. Before opening a PR that changes skill behavior:

1. Point the skills at a scratch repository with CI on it. A two-phase plan is enough.
2. Run a phase to a merge, with YOLO off.
3. Kill the session mid-phase and start a new one. Recovery from a cold start is the property most changes accidentally break.

Say in the PR what you actually ran. "Reviewed by reading" is a fine answer when that is the truth; claiming a test that did not happen is worse than no test.

## Validate the plugin manifest

```bash
claude plugin validate . --strict
```

CI does not run this yet. Run it before you push if you touched anything under `.claude-plugin/`.

## Scope

Good contributions: a CI or review provider that the current model handles badly, a recovery case the driver gets wrong, a gate that deadlocks on a setup nobody anticipated.

Out of scope for now: support for forges other than GitHub. The gate logic is written against check runs and review threads, so a port is plausible, but it is a larger change than it looks and worth discussing in an issue first.

## Style

Plain sentences. Say the thing, then stop. Avoid em-dashes where a comma or a full stop will do, and avoid the "not X, but Y" construction unless the contrast is the point.

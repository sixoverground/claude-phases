# Changelog

Notable changes to claude-phases. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [SemVer](https://semver.org/spec/v2.0.0.html).

Because the skills are prose read by a model, a "patch" here can still change behaviour. Read the entry, not the number.

## [0.1.0]

First release. Everything below was built with the project's own phased plan, and the version number starts here because nothing was published before it.

### The loop

* `phase-planner` breaks work into one-PR phases and detects each repo's CI and review setup.
* `phase-driver` picks the next phase, implements it, opens a PR, watches CI and review, and merges when the gates pass.
* The plan file at `docs/plans/<project>.md` is the durable state, so a session that remembers nothing can reconstruct where the work stands.
* Plan format and configuration spec in `docs/format.md` and `docs/configuration.md`.

### Merge gate

* Six gates, each with an explicit off switch: draft, blocking labels, checks, changes requested, review threads, and proof that the reviewer evaluated the head commit.
* CI modelled as observe / dispatch / read-logs rather than a list of vendors.
* Review profiles for managed Code Review, a Claude Actions workflow, Copilot, humans only, and none.

### Running unattended

* YOLO mode, branch deletion on merge, and an integration PR at the end of a plan that the driver never merges itself.
* UAT deferred to one cumulative test script when phases merge unattended.
* `plan_branch`, so the plan can live on a feature branch rather than the default branch.

### Packaging and project files

* `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, so the repo installs with `/plugin marketplace add` instead of copying directories by hand.
* `CONTRIBUTING.md`, `SECURITY.md`, and issue templates.

### From the first run outside this repo

Three portability problems, found driving a two-repo feature to production and now written into the planner and driver references:

* Review workflows that check out a shallow clone cannot diff against a non-default base, and quietly review file contents instead of the change.
* Preview environments pinned to a branch the driver deletes keep serving a stale build with nothing to indicate it.
* Remote-tracking refs report stale SHAs after a container restart, so remote state has to be read with `git ls-remote`.

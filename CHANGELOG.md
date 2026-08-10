# Changelog

Notable changes to claude-phases. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [SemVer](https://semver.org/spec/v2.0.0.html).

Because the skills are prose read by a model, a "patch" here can still change behaviour. Read the entry, not the number.

## [Unreleased]

### Fixed

* `phase-planner`'s description no longer contains `<project>`. Skill installation rejects a description containing anything that parses as an XML tag, and one bad description fails the whole upload, so neither skill could be installed at the account level.

### Self-contained skills

An installed skill is a zip of its own directory, so anything outside that directory isn't there to read. `phase-planner` was pointing at `docs/format.md` and `docs/configuration.md` for the spec it writes to, which resolved in this repo and resolved to nothing on an account that had only the skill.

* The plan format spec, the configuration reference, and the empty plan template now live in `skills/phase-planner/references/`. They moved rather than being copied; `docs/` and the README link to them where they are. `phase-driver` already referenced nothing outside itself.
* Links from a skill out to the repo are absolute URLs now, and only for further reading.
* `scripts/check-skills.sh` fails on a link that climbs out of a skill or points at nothing. It runs on every PR and again before any zip is built.

### Packaging

* `scripts/package-skills.sh` builds one zip per skill, rooted at the skill directory, which is the shape the claude.ai skills uploader expects.
* A `Package skills` workflow attaches those zips to every published release, so installing at the account level is a download rather than a clone.

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

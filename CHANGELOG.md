# Changelog

Notable changes to claude-phases. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [SemVer](https://semver.org/spec/v2.0.0.html).

Because the skills are prose read by a model, a "patch" here can still change behaviour. Read the entry, not the number.

## [0.5.1]

### No em-dashes

House style. Every em-dash in prose is gone, recast as a comma, a colon, or a separate sentence rather than swapped for an en-dash, which would be the same habit in disguise. Both skills, the docs, the profiles, and this file.

The ones that remain are not prose: phase headings (`### Phase 2 — Sign-in screen`), Driver State `Active` entries, and the gate report that mirrors them. Those are separators in the format the driver reads and writes, and plans already in flight contain them, so changing them is a format change rather than a copy edit.

No rule changed. The version moves because the skills are what a model reads and their text is not inert.

## [0.5.0]

### Who opens the PR is part of the merge gate

Found on a real run. The session opened a phase PR with `gh pr create` instead of the GitHub MCP tools. In a cloud session `gh` is authenticated as the integration rather than as the user, so the PR was opened by that app, and Codex, which reviews the PRs of the account that connected it and nobody else's, was never asked. No review, no check, no error. Gate 6 waited on proof that had never been requested and YOLO stopped with nothing red to look at.

* `phase-driver` opens PRs with the GitHub MCP tools, never `gh pr create`. Both succeed and print a URL; only one of them gets reviewed.
* It reads back the PR's `user.login` afterwards and compares it to the account its own GitHub tools authenticate as, which is the identity the MCP tools open PRs with. Nothing has to be configured for that, and no plan field records an expected opener.
* The check applies to account-scoped reviewers. A workflow-triggered reviewer runs whoever opened the PR, and a `check:` entry has no connected user, so reporting those as broken would recommend closing a healthy PR.
* Gate 6 checks the opener before calling a signless PR a broken integration. The two look identical and have very different fixes.
* `phase-planner` checks who opened the PRs a reviewer has reviewed, and says in the handoff when a reviewer only watches one account.
* This is about the opener alone. Commit authorship and `Co-Authored-By` trailers have no bearing on whether a reviewer runs, and adding one would not have prevented this.

### Review rounds that don't converge

Observed on a real phase: four review rounds, then twenty-eight more after the user approved continuing. Two causes, both in how the driver answered a review.

* **A review comment is evidence, not an order.** The driver judged every comment as work to do, including findings outside the phase's scope, which is the same widening §3 already forbids when it notices a problem itself. Out-of-scope findings are now declined with reasoning and recorded where they survive, rather than implemented.
* **Carried findings**, a new optional section of the plan file, is where an out-of-scope finding goes when it makes sense for the plan but not for the phase that raised it. A defect that stands on its own still goes to an issue. The driver appends and **never adds a phase**: writing scope, acceptance criteria and dependencies is planning, and a driver that does it is re-planning a project mid-flight on a reviewer's suggestion. `phase-planner` reads the section when revising a plan, and the driver reads out any open entries when the plan finishes, so nothing completes with a list nobody looked at.
* **It fixed the flagged line instead of the finding.** A reviewer comments where it happened to look; the same mistake is usually in several places in the same diff. Fixing only what was pointed at guarantees the next round finds the siblings. The driver now reads the surrounding code, fixes the general case once, and says so in the reply.
* **One push per round, not one push per comment.** Every push is another review round.
* An accepted finding is replied to and its thread resolved after the round's push. Gate 5 wants every thread resolved, so a fix pushed without resolving blocks the phase on a thread that no longer says anything true.
* Scope-declining resolves the thread; disagreeing on the merits does not. Holding gate 5 open for work that was never in the phase would stall it, while a thread claiming the code is broken should block until a person agrees it isn't.

### Fixed

* **Only 👍 is a verdict.** 0.4.0 said a reaction from a configured reviewer proves it evaluated the head, which is true of 👍 and false of the others. Codex answers `@codex review this pr` with 👀 within seconds to say it has picked the job up, observed here ten seconds after the request with no review for minutes after. A rule matching on any reaction would merge on "I have started reading", which is worse than the silence it replaced because it arrives fast and looks like an answer. Gate 6 now matches on the reaction's content.
* **v0.4.0 shipped with no skill zips.** GitHub raises no workflow-triggering event for a release created with the repository's `GITHUB_TOKEN`, so once `release.sh` took over publishing, the `release: published` run that attached the assets simply stopped happening. Every release through v0.3.0 was published by hand and got its zips; v0.4.0 was the first cut by the script and got none, silently.

  `release.sh` now attaches them in the same job that creates the release, and attaches them to an existing release when re-run, so a release missing its assets is repaired by dispatching the workflow rather than by burning a version. `package-skills.yml` keeps the PR check and the dispatch build, and no longer claims to handle releases.

  The release job checks out `main` explicitly rather than the ref it ran on. A dispatch can name any branch, and an unpinned checkout would read that branch's `plugin.json` and build its zips while `gh release create --target main` tagged main's code, producing a release whose tag and assets came from different places.

## [0.4.0]

### A reviewer's thumbs up counts as a review

Found driving a real project with YOLO on. Codex on smart detect can decide a PR needs no review at all, and when it does it leaves a 👍 on the PR and writes nothing else. 0.3.0 read that PR as having no review, which under `rereview: optional` is the one state that never times out, so the phase sat blocked behind a reviewer that had already answered.

* A 👍 by one of an entry's `review.required` `logins`, left at or after the head commit was pushed, satisfies gate 6 on its own. It is the reviewer's verdict on that commit, which is the only thing the gate asks about.
* An older 👍 counts as a **sign** the reviewer has the PR, alongside a review or an inline comment. `rereview: optional` needs one of those before it will read silence as a decline, and a PR carrying none of them still never times out.
* The gate report distinguishes a pass carried by a fresh reaction from one inferred from silence, since they are different claims.
* Reactions must be read **attributed**, via `gh api repos/{owner}/{repo}/issues/{number}/reactions`. The reaction counts in an issue payload are unattributed, and treating one as the reviewer's verdict would turn any teammate's thumbs up into a merge.
* `phase-planner` looks for a 👍-only PR when detecting smart detect. It confirms the mode more directly than an absent second review does.

## [0.3.0]

### Reviewers that decide per push

Some reviewers review a PR once and then judge, per push, whether another look is warranted. OpenAI's Codex calls this **smart detect**. Gate 6 anchors proof to the head commit, so the driver would push a CI fix, the reviewer would sensibly stay quiet, and the gate would wait forever for proof that was never coming.

* `rereview: optional` on a `review.required` entry accepts a review of an earlier commit **on the same PR** once `rereview_grace` (default `15m`) has passed since the head was pushed. The default stays `required`, which is stricter and is still the right setting for a reviewer that reviews every push.
* **A PR with no review at all never times out.** Smart detect reviews every PR once, so zero reviews means a broken integration rather than a decline. Without that precondition the option would decay into "wait fifteen minutes, then merge unreviewed", which is the silent false pass the rest of gate 6 exists to prevent.
* The grace runs from the head commit's committer date, stamped at push, not from when the driver started waiting. Otherwise a driver waking an hour later times out on its first look.
* A pass earned by a decline says so, in the gate report and on the PR. A decline recorded nowhere is indistinguishable from a review that happened.
* Codex is documented as a reviewer setup, and `phase-planner` detects the case and asks whether the reviewer can be set to review every push before reaching for the weaker gate.

### Fixed

* `.claude-plugin/plugin.json` reports the version it actually is. It read `0.1.0` at v0.2.0, v0.2.1 and v0.2.2, and since the install path is derived from that field, all three releases installed into a directory named `0.1.0` and the plugin manager could not tell them apart. Installations silently stayed several releases behind with nothing reporting a problem.

> The three 0.2.x tags shipped without changelog entries or a version bump. Their notes are the ones below, previously sitting under `[Unreleased]`, and they are subsumed here rather than being backdated into releases that never carried them.

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

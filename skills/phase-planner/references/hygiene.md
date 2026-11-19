# Repo hygiene checklist

Settings that make the difference between a driver that runs unattended and one that stalls. Go through these when writing a plan; each is cheap, and each prevents a failure that's hard to diagnose later.

Flag what's missing. Fix what you can. A workflow edit is a PR. Settings outside the repo need the user.

## Prevents a stalled gate

**Re-review on push.** Proof-of-review is anchored to the head commit. A reviewer that only fires on PR open goes stale the moment the driver pushes a fix, and the gate waits forever on a review that will never come.

- Copilot: enable the "Review new pushes" ruleset
- Managed Claude Code Review: set Review Behavior to **After every push**
- A review workflow: include `synchronize` in its `pull_request` types

**Inline review comments.** Only diff-anchored comments create resolvable threads. A reviewer posting a single top-level summary makes the thread gate vacuous. It will always pass, having measured nothing.

**A reviewer that says something on a clean pass.** If it goes completely silent when it finds nothing, proof-of-review can't distinguish "reviewed and found nothing" from "never ran", and you're forced into `proof: completed`, which accepts a skipped job as a review.

**A reviewer that can diff against the target branch.** Review workflows usually check out a shallow clone, which has no merge base with anything but the default branch. When `target_branch` is a feature branch, `git diff origin/<target>...HEAD` then fails, and most review workflows fall back to reviewing file *contents* at HEAD instead of the change. The gate still passes. The review is just no longer about the diff, and nothing says so.

Watch for it on the first phase PR: a review that describes files rather than changes, or that re-raises things the base branch already contained. The fix is in the workflow, not here. Fetch the target branch with enough depth to have a merge base (`fetch-depth: 0`, or an explicit `git fetch origin <target>`).

## Prevents wasted CI and accidental deploys

**`paths-ignore: ['docs/plans/**']`** on push-triggered workflows. The driver writes three plan commits per phase to the plan branch. Without this they burn CI minutes, and on a repo that deploys from that branch they trigger deploys. The driver also appends `[skip ci]` to plan commits, but `paths-ignore` is belt and braces.

Less of a concern when the plan branch isn't the default branch, since push triggers are often pinned to the default, but preview deploys usually aren't, so check rather than assume.

**`workflow_dispatch`** on the CI workflow, if you want the driver to trigger builds without pushing an empty commit. Optional: without it, the driver triggers CI by pushing, which everyone does anyway.

**A preview environment pinned to a branch the driver deletes.** Vercel, Netlify, Amplify and friends can pin an environment to a named branch. Point one at a phase branch and it dies at the first merge, because the driver deletes phase branches as they land. Point one at the `target_branch` and it survives the plan, then dies when the feature merges and GitHub auto-deletes that branch.

This matters more than a broken preview usually would, because the environment is normally where the user runs UAT. During one plan the staging domain silently kept serving a build from a branch that no longer existed, and an evening went into diagnosing a feature that was working correctly and simply wasn't deployed.

Pin previews to the default branch, or accept that the pin needs moving when the feature lands and say so in the plan. Ask which, rather than assuming there is no preview.

## Prevents clutter and confusion

**Auto-delete merged branches** (Settings → General). The driver deletes each phase branch as it merges, but only when it is the one merging. With YOLO off it never merges, so it never deletes, and a twelve-phase plan a human merged from the UI leaves twelve stale branches unless GitHub is cleaning up.

Turn it on regardless of how you plan to run. It also covers the case the driver cannot: some sandboxed environments permit pushes and PR operations while refusing ref deletion outright, at both the git and API layers. There the driver's delete fails every time and this setting is the only thing that cleans up, because GitHub performs it server-side on merge with nothing routed through the session.

**Branch protection.** If the plan branch rejects direct pushes, the driver can't write plan status normally. Either allow the driver's identity to push, or set `plan_writes: plan-pr` so each status change becomes a small auto-merging PR. Detect this before the first phase rather than discovering it mid-run. A feature branch used as `plan_branch` is usually unprotected, which sidesteps this even when the default branch is locked down.

**Don't delete the plan branch while a plan is running.** With `plan_branch` on a feature branch, merging that feature and letting GitHub auto-delete the branch takes the plan with it, and the driver stops rather than guessing. Finish the plan first, or move the plan file to the default branch before the feature merges. A plan with milestone rows avoids this by living on the default branch from the start.

## Milestones

Only for a plan with milestone rows.

**Auto-delete and a milestone's branch.** With *Automatically delete head branches* on, merging a milestone PR deletes the feature branch, since it is that PR's head. That is expected. The driver re-creates it from the default branch before anything else starts in that repo. Leave the setting on; nothing needs changing. Without it, the driver fast-forwards or moves the branch instead.

**A protected feature branch.** The driver commits a milestone's preparation, and any fix to the milestone PR, straight to the feature branch. If that branch rejects direct pushes, each of those becomes a small PR into it under the ordinary gate, which costs a review round apiece. Allow the driver's identity to push to the feature branch, or accept the extra rounds and say so in the plan.

**Version checks scoped to the default branch.** A check that fails any PR without a version bump fires on phase PRs into the feature branch too, and forces a bump per phase. Scope it to PRs whose base is the default branch, with a job-level `if` so it shows as skipped elsewhere. That is a workflow edit and a phase of its own, the first one.

## Makes local verification possible

**A `SessionStart` hook** that installs dependencies, for any repo set to `verify: local` in a cloud session. That is a cloud concern: a fresh container has nothing installed. A session on your own machine uses the toolchain already there. `local` has no fallback: if the toolchain isn't there, verification fails and the phase blocks. Use `verify: auto` if you'd rather it drop to CI instead.

**When the driver and a CI runner share a Mac**, for an Xcode project on `verify: local`, keep their builds apart. Contention between them is intermittent, so a setup that worked once is not proof:

- **Its own DerivedData.** Pass the driver's build `-derivedDataPath` pointing at a directory of its own, so it never waits on, or corrupts, the runner's build directory.
- **A simulator the runner does not use.** Build for a generic simulator destination (`-destination 'generic/platform=iOS Simulator'`), which needs no booted simulator, or name a simulator the runner never boots.
- **One concurrent job on the runner** (`concurrent = 1` in a GitLab runner's `config.toml`), so the runner itself never runs two builds against one simulator.

## Worth mentioning, not blocking

**A `CLAUDE.md`** describing conventions the driver should follow. It reads it like any session, and phases written to match the codebase's existing style need less review.

**A PR template.** The driver fills the body itself, but a template tells it what the repo expects.

## GitLab

Only for a repo whose forge is `gitlab`. The items above are written for GitHub; these are what a GitLab project needs in their place.

**The review job and `build-test` run in merge request pipelines, by themselves.** The driver's gate 3 reads the merge request pipeline first, and a marker names the head it reviewed, so the jobs that gate a phase must run in a merge request pipeline into `target_branch` on every push. A job whose `rules` only match branch pipelines (`$CI_COMMIT_BRANCH`) or only the default branch never runs there, and the gate waits for it. Give each a rule on `$CI_PIPELINE_SOURCE == "merge_request_event"`, or put `workflow: rules` that create merge request pipelines in the project's own CI file, not only in an include. A job with no conditions and no such `workflow` defaults to `except: merge_requests`. Neither job should be `when: manual`, and anything they `needs` must run there too. `build-test` here stands for whatever the project's build and test job is called.

**The review job must not be `allow_failure: true`.** A marker reviewer that fails posts no marker, so gate 6 blocks, which is right. A job allowed to fail also shows gate 3 a pass, so the only sign of a broken reviewer is a phase waiting on gate 6 with every check green. Let it fail red. This holds for any job that runs a `marker` reviewer.

**The review job's token variable must not be protected.** GitLab gives a protected CI/CD variable only to pipelines on protected branches, and phase branches are not protected, so the job fails on every phase MR saying its token is missing. Mark it masked and not protected. And make it a different account from the one the driver acts as, or `logins` stops meaning anything and the watcher, which ignores the driver's own notes, never wakes for the reviewer.

**Plan commits and `[skip ci]`.** The driver ends every plan commit with `[skip ci]`, which GitLab honours for push pipelines. A `rules: changes` exclusion on push-triggered jobs, so they do not run when only `docs/plans/**` changed, is belt and braces, as `paths-ignore` is on GitHub. It matters most where the plan branch deploys.

**"Delete source branch" as a project default** (Settings → Merge requests, *Enable "Delete source branch" option by default*). The driver opens each phase MR with the option on and leaves it off for milestone and integration MRs, so GitLab deletes a phase branch on merge whoever merges it. The project default covers MRs the driver did not open, and is the GitLab form of *Automatically delete head branches*.

**A protected plan branch, and who may push to it.** The driver writes every status transition to the plan branch. A protected branch where only Maintainers may push refuses a Developer-role token, and so does the plan-PR fallback if only Maintainers may merge. Either allow the driver's role to push to the plan branch (*Allowed to push and merge* under Settings → Repository → Protected branches), give the token the Maintainer role, or put the plan on an unprotected feature branch. Check the branch you will actually use; detection reads it.

**The runner and the driver sharing one Mac.** A self-hosted runner on the same Mac as a local driver is a common setup and works, with four things to get right. Trigger jobs are not among its work: they run on GitLab itself.

- **Register it as not protected.** A runner set to run only on protected branches (`access_level: ref_protected`) cannot run a phase MR's pipeline, because phase branches are not protected, and the jobs wait as `pending`. Leave *Protected* off on the runner, or protect the phase branches and the target branch and allow merge request pipelines to use protected runners.
- **Separate working copies.** The runner builds in its own directory, the driver works in a clone of its own, and the person's checkout is a third. Never point the driver at the runner's build directory or the other way round.
- **The Mac stays awake.** A sleeping Mac stops the runner and the driver together, and jobs queue as `pending` until it wakes. Turn off sleep while a plan runs, or accept that it pauses.
- **Capacity.** A runner with `concurrent = 1` runs one job at a time, so a review job and `build-test` on the same pipeline run in turn, and two repos' pipelines queue behind each other. That is slower, not broken. Raise `concurrent` in the runner's `config.toml` if the Mac can take it.

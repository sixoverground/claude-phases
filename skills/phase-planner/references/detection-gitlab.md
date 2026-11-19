# Detecting how a GitLab project works

The same procedure as [`detection.md`](detection.md), for a repo whose forge is `gitlab`, on gitlab.com or a self-managed instance. The headings are the same, so a finding sits in the same place on either forge. Where GitHub reads workflows, check runs and reviews, this file reads the CI file, the jobs that ran in merge request pipelines, runners and marker notes. A few facts have no GitHub counterpart and get sections of their own at the end.

Read the repo, don't interrogate the user, exactly as there. Show the evidence, then let them correct it.

**How to read it.** Every call names the host and the project, so the current directory never decides which instance is asked:

```sh
enc() { jq -rn --arg s "$1" '$s|@uri'; }
P=$(enc acme/platform/web)                      # the project path, URL-encoded
glab api --hostname <host> projects/$P          # <host> is the repo's host, gitlab.com when unset
```

Below, `<P>` is the encoded project path and `<target>` the encoded `target_branch`. Branch names and file paths with `/` in them are encoded the same way. Checked against `glab` 1.131.0 and the GitLab REST API documentation, November 2026: the [Projects](https://docs.gitlab.com/api/projects/), [Branches](https://docs.gitlab.com/api/branches/), [Repository files](https://docs.gitlab.com/api/repository_files/), [CI Lint](https://docs.gitlab.com/api/lint/), [Merge requests](https://docs.gitlab.com/api/merge_requests/), [Pipelines](https://docs.gitlab.com/api/pipelines/), [Jobs](https://docs.gitlab.com/api/jobs/), [Runners](https://docs.gitlab.com/api/runners/) and [Notes](https://docs.gitlab.com/api/notes/) APIs. A self-managed instance can lag gitlab.com, so a field that reads `null` or a call that 404s may be the server's age, not the project's setup: say which you think it is.

**A finding you could not observe directly is marked as inferred**, in the findings table and in what you say, so nobody mistakes it for something read off the project. The runners fallback below is the usual case.

## Read current code, not PR history

As in [`detection.md`](detection.md#read-current-code-not-pr-history), with merge requests in place of PRs: a merged MR describes what was added, not what survived. Use MR history to find where to look, then open the files on the branch you're targeting. In a local clone, read them there; otherwise through the Files API:

```sh
glab api --hostname <host> "projects/<P>/repository/files/<path>/raw?ref=<target>"
```

## Default branch → `target_branch`

```sh
glab api --hostname <host> projects/<P>
glab api --hostname <host> projects/<P>/repository/branches/<target>
```

| Observed | Set |
|---|---|
| The project's `default_branch` | `target_branch` defaults to it. Never assume `main` |
| Phases should land as a unit on a feature branch, and the branches read returns it | `target_branch: <that branch>`, and `plan_branch` to match unless the plan has milestone rows, as in [`detection.md`](detection.md#default-branch--target_branch) |
| The branches read answers 404 | Refuse: `target_branch` names a branch that doesn't exist |

## Trigger filters → whether required checks can fire at all

On GitLab a job's start conditions are in the CI file: its `rules`, or the older `only` and `except`, and the file's top-level `workflow: rules`, which decide whether a pipeline is created at all. **Every job you're about to put in `ci.required`, and the job that runs a `marker` reviewer, must be able to run in a merge request pipeline into `target_branch`.** A job seen on MRs into the default branch may have a rule that never fires for a feature branch.

Read the file as GitLab will run it, includes resolved, from the target branch. The project may keep it somewhere other than `.gitlab-ci.yml`: the project's `ci_config_path` says where, and empty means the default.

```sh
glab api --hostname <host> "projects/<P>/ci/lint?content_ref=<target>&include_jobs=true"
```

Read `valid` and `errors`, `merged_yaml` (the whole configuration with every `include` expanded, which is where `rules` and `workflow` are), `includes` (what was pulled in, and from where), and `jobs`, each with `name`, `stage`, `tag_list`, `only`, `except`, `when` and `allow_failure`. Without `dry_run` this is a static read of the configuration. Do not read its `jobs` as the jobs a merge request pipeline would create: a dry run simulates a pipeline for a branch or tag (`dry_run_ref`), and the documentation does not say it can simulate a merge request pipeline, so the rules are read by hand, below.

### Resolve each job before reading it

**`merged_yaml` expands includes and does not resolve inheritance.** GitLab's own example response keeps a hidden `.api_test` template and the `extends: [".api_test"]` that points at it, so a job's own mapping there is not the job GitLab runs. Every key this file reads from a job, `rules`, `only`, `except`, `when`, `allow_failure`, `tags` and `trigger`, is read from the **resolved** job, built this way:

1. **Hidden jobs are templates.** A key whose name starts with `.` never runs. It is never a job for `ci.required`, never the reviewer's job, and never a job whose tags need a runner. It matters only as a parent.
2. **Resolve `extends`, parents first.** `extends` is one name or a list. Resolve each parent the same way before using it, through as many levels as the chain has (GitLab allows up to eleven). Then merge in order: the first parent, each later parent over it, and the job's own keys over all of them. Hashes merge key by key, deeply; **anything that is not a hash replaces**, so a later `rules`, `tags`, `script` or array-form `only` replaces the earlier one entirely rather than adding to it. A key set to `null` removes what it inherited.
3. **Resolve `!reference` tags**, where `merged_yaml` still carries one, such as `rules: [!reference [.base, rules]]`. Replace it with the value at that path in the resolved configuration. The CI Lint documentation does not say whether `merged_yaml` keeps them, so look rather than assume.
4. **Fill from `default`.** Keys under the top-level `default:`, such as `tags`, fill a key the resolved job does not set, unless the job's `inherit: default:` is `false` or leaves that key out. `rules` cannot be set in `default`.
5. **Cross-check with `jobs`.** Where `ci/lint`'s `jobs` entry for the job gives `tag_list`, `only`, `except`, `when` or `allow_failure`, it should agree with what you resolved. Where it does not, say which key and both values, and ask rather than pick one.

**Where inheritance cannot be resolved, you could not tell.** A parent that is not in `merged_yaml` (`ci/lint` then usually reports it under `errors`), an include from a project this token cannot read, a chain deeper than you can follow, or a `!reference` to a path that is not there: say so, name the job and the parent, and ask, exactly as for a variable you cannot read.

### Apply the trigger filters

For each resolved job that matters, read its conditions against a merge request pipeline into `target_branch`, where `CI_PIPELINE_SOURCE` is `merge_request_event`, `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` is `target_branch`, and `CI_COMMIT_BRANCH` is not set:

| Observed | It fires on an MR into `target_branch` |
|---|---|
| No `rules`, `only` or `except` | Only if the project runs merge request pipelines at all: a job with no conditions runs in branch pipelines, and in merge request pipelines only where `workflow: rules` creates them. Read `workflow` |
| A rule on `$CI_PIPELINE_SOURCE == "merge_request_event"` with no other condition | Yes |
| A rule on `$CI_MERGE_REQUEST_TARGET_BRANCH_NAME` equal to another branch, or to `$CI_DEFAULT_BRANCH` while `target_branch` is not the default branch | **No** |
| A rule on `$CI_COMMIT_BRANCH`, alone | **No**. That variable is unset in merge request pipelines, so the rule only ever fires in branch pipelines |
| `only: [merge_requests]` | Yes |
| `only` naming branches, or `except: [merge_requests]` | **No** for a merge request pipeline |
| `rules: changes` | Only when the MR touches those paths, so not on every phase. Treat the job as intermittent |
| `workflow: rules` that create no merge request pipeline | **No job fires in one**. Every required job is refused, and the fix is in `workflow` |
| A condition on a variable you cannot read, such as a project or group CI/CD variable, a variable set by an `include` from another project, or an expression you cannot evaluate with confidence | **Cannot tell.** Say so, name the job and the rule, and ask |

When a job's rules cannot fire, refuse it as `SKILL.md` §3 says, naming the job and quoting the rule, and the template it came from when it was inherited. Saying which rule is most of the fix, and an inherited rule is fixed in its template or overridden in the job.

## Workflows → `ci.dispatch`

GitLab has no counterpart to `workflow_dispatch` that the driver uses, so the value is fixed:

| Observed | Set |
|---|---|
| A GitLab repo, with any CI file or none | `ci.dispatch: push`. The default, `auto`, is GitHub-only. The driver triggers a pipeline by pushing |
| No CI file at all: the Files API 404s on the configured path | `ci.dispatch: push` still. There is nothing to trigger, and `ci.allow_none` below says what that means |

Note whether jobs that run on pushes to the plan branch exclude `docs/plans/**`. The driver's plan commits carry `[skip ci]`, which GitLab honours for push pipelines; a `rules: changes` exclusion is belt and braces. See the GitLab section of [`hygiene.md`](hygiene.md#gitlab).

## Check runs on recent PRs → `ci.required`, `ci.allow_none`

**This is the load-bearing one on GitLab too.** What the CI file declares and what actually runs in a merge request pipeline differ: `rules` skip jobs, `parallel` and `parallel: matrix` expand one job into several names, child pipelines run behind one trigger job, and an external tool posts commit statuses with no job at all. So read the jobs that actually ran.

Find recent merge requests into `target_branch`, newest first:

```sh
glab api --hostname <host> "projects/<P>/merge_requests?state=merged&target_branch=<target>&order_by=updated_at&per_page=10"
```

If none exist, as for a new feature branch, read MRs into the default branch instead, and say that what you saw is from the default branch, so the trigger filters above decide whether it carries over.

For each MR, its pipelines, and the jobs of the newest **merge request pipeline** (`source` is `merge_request_event`, or `ref` is under `refs/merge-requests/<iid>/`), which is the pipeline the driver's gate 3 reads first. Fall back to the newest branch pipeline only where an MR had no merge request pipeline, and say so:

```sh
glab api --hostname <host> "projects/<P>/merge_requests/<iid>/pipelines?per_page=100"
glab api --hostname <host> --paginate "projects/<P>/pipelines/<id>/jobs?per_page=100"
glab api --hostname <host> --paginate "projects/<P>/pipelines/<id>/trigger_jobs?per_page=100"
glab api --hostname <host> --paginate "projects/<P>/repository/commits/<sha>/statuses?per_page=100"
```

From the jobs and trigger jobs, read `name`, `status`, `allow_failure`, `tag_list` and `runner`. `trigger_jobs` is GitLab 19.2's name; an older server answers at `pipelines/<id>/bridges`. From the statuses on each MR's head sha, keep the external ones, those whose `id` is no job or trigger job above and whose `target_url` is not one of this project's job pages, and list their `name`s in the findings, as `external` beside the jobs. The driver's gate 3 counts them like jobs, so a name in `ci.required` may be one of them.

| Observed | Set |
|---|---|
| A consistent set of jobs | Leave `required: []` (all count), or name them if some are advisory. Names are **job names**, as they appear in the jobs list, one per `parallel` instance |
| Jobs that appear only sometimes (`rules: changes`, `when: manual`) | Name the stable ones in `required`. A job that runs only sometimes stalls the gate when it's required |
| Jobs with `allow_failure: true`, a coverage or preview job, a manual deploy | They pass when they fail, so they need nothing. Name only the real ones in `required`, or put noise in `ignore_checks` |
| A blocking manual job (`when: manual` with `allow_failure: false`) | Say so: it blocks the gate until a person plays it, on every phase. Ask whether it belongs in the MR pipeline |
| A trigger job for a child pipeline | It counts as one check with its own status. Name the trigger job, never a job inside the child. Say whether it uses `strategy: depend`: without it, the trigger passes as soon as the child starts |
| External statuses, with no job behind them | Like external CI on GitHub: they count when they appear. A name in `required` may be one, but only one seen on recent MR heads into `target_branch`: its start conditions are outside the CI file and cannot be read, so one seen only on MRs into the default branch is not required when targeting a feature branch |
| No jobs, and no CI file | `allow_none: true`, and say so out loud: nothing will be verifying merges |
| No jobs, but a CI file exists | **Do not set `allow_none: true`.** CI is configured and not running on merge requests: misrouted rules, a stopped runner, or no MR has run yet. Flag it and ask |
| Any GitLab repo | `ci.logs: gitlab-jobs`, or leave the default `auto`, which resolves to it on GitLab. `actions` and `check-output` are GitHub's and do not apply |

Refuse a name in `ci.required` that matches no CI job and no external status seen on recent MRs into `target_branch`, as `SKILL.md` §3 says. A name that is a job still has to pass the trigger filters and have a runner.

## Who actually reviews → `review.required`

**On GitLab, `review.required` takes `marker` entries only.** The driver's gate 6 there reads review markers and nothing else, so an entry that names only `logins`, or a `check`, or uses `rereview`, blocks every phase on GitLab. Configure a reviewer as `{ marker: "<reviewer>", logins: [<account it posts as>] }`, or leave `required: []`.

Read the notes on the same recent MRs, and look for the marker line, `<!-- phases:review v=1 reviewer=<name> sha=<sha> -->`, in notes that are not `system` and whose `type` is not `DiffNote`:

```sh
glab api --hostname <host> --paginate "projects/<P>/merge_requests/<iid>/notes?per_page=100"
```

Read `body`, `author.username`, `system` and `type`. Then look in the CI file's `merged_yaml` and `includes` for the job that posts it: a real job, not a hidden template, read as resolved by [Resolve each job before reading it](#resolve-each-job-before-reading-it). An included template such as `codex-mr-review`'s usually defines the job through `extends`, so its rules and tags are the inherited ones.

| Observed | Set |
|---|---|
| Marker notes for one reviewer name, by one account | `required: [{ marker: "<name>", logins: ["<that account>"] }]`. Read the account off the notes; list only it |
| A reviewer job in the CI file (for example `codex-review`, from the `codex-mr-review` CI template, which posts `reviewer=codex`) but no marker on any MR yet | The `marker` entry, with a line in the findings saying no MR has shown a marker yet and the first phase MR will confirm it. Leave `logins` for the account it will post as, and ask which that is |
| Marker notes, and the reviewer job's rules cannot fire on an MR into `target_branch` | Refuse, by the trigger filters above. The markers came from MRs into another branch |
| Neither a marker nor a job that could post one | No `marker` entry. Configuring one is refused in `SKILL.md` §3 |
| People review, approve or request changes | `required: []`, and say that gates 4 and 5 still apply to them. Gate 4 depends on the instance: requesting changes is a Premium and Ultimate feature from GitLab 17.2 |
| Nobody reviews | `required: []`, and say plainly that nothing will be checking the driver's work |

**Check whether the reviewer's findings are threads.** A thread on GitLab is resolvable whether it sits on a diff line or on the overview, so the thread gate works for a reviewer that opens threads anywhere. A reviewer that posts only plain comments (`individual_note: true` in the discussions) gives it nothing to check: warn, as on GitHub.

**Check that the review job runs on every push.** A marker names one head, so the review job has to run in every merge request pipeline, not only the first. A `rules: changes` on it, or a rule tied to the MR being opened, is the GitLab form of a reviewer that only reviews on open.

### Reviewers that decide per push → `rereview`

**Does not apply on GitLab.** `rereview: optional` decides from reviews and reactions, which gate 6 does not read there. A reviewer that skips a push posts no marker for it, and the gate blocks, which is the intended behaviour. Do not set `rereview` for a GitLab repo, and if a plan already does, warn.

### `proof`

**Does not apply on GitLab**, because `proof` judges a `check` entry and GitLab takes `marker` entries only. A review job is counted by gate 3 like any other job, so a reviewer that cannot run turns the checks red.

## The repo's own review rules → `stuck`

The same as [`detection.md`](detection.md#the-repos-own-review-rules--stuck): read `CLAUDE.md`, `AGENTS.md` and the contributing guide for a fix-round cap or an escalation rule, and fit `stuck` to it by the same table. On GitLab also read `.gitlab/merge_request_templates/`, where a project sometimes writes its review expectations. Read them from the local clone, or with the Files API above.

## Release conventions → `milestone.prepare`

The same as [`detection.md`](detection.md#release-conventions--milestoneprepare), with one GitLab source more: jobs in the CI file that run only on the default branch or on tags, a `release:` keyword, or a job that checks a version, each read as resolved by [Resolve each job before reading it](#resolve-each-job-before-reading-it). Quote the job and its rule for every step you put in `prepare`, as you would a check on GitHub.

## Toolchain → `verify`

The same table as [`detection.md`](detection.md#toolchain--verify). One GitLab case more: where the CI runs on a runner on the same Mac as the driver, the toolchain the runner uses is usually installed there too, so `local` is often right. Confirm it rather than assume it, and see the GitLab section of [`hygiene.md`](hygiene.md#gitlab) for the runner and the driver sharing one machine.

## When there's nothing to observe

A project with no merge request history gives most of this nothing. Don't invent a config: **ask one question** that covers what you could not read, through `AskUserQuestion`, and say what you could tell from the CI file alone.

The safe starting point:

```yaml
forge: gitlab
review: { required: [] }     # no marker observed
verify: auto                 # try local, fall back
ci:
  dispatch: push
  logs: gitlab-jobs
```

- **No CI file** → `ci: { allow_none: true }`, and say nothing will verify merges.
- **A CI file, but no MR pipeline has run** → leave `allow_none` at `false`. Say you couldn't confirm jobs run on merge requests, and let the first phase MR settle it.

Then say plainly how much the merge gate is actually checking.

## Runners and tags → whether required jobs can run

A job with `tags` runs only on a runner that has every one of them, and a job stays `pending` for as long as no such runner is online. A required job nobody can run is a gate that waits forever, so check it for every job in `ci.required` and the reviewer job.

**A protected runner does not serve a phase MR.** A runner whose `access_level` is `ref_protected` runs jobs for protected refs only, and a merge request pipeline may use it only when both the source and the target branch are protected, the source is in the same project, the person triggering it can push or merge to the target, and the project allows merge request pipelines to reach protected runners. Phase branches under `branch_prefix` are normally not protected, so in practice a protected-only runner does not count. Count it only when the person confirms a protected-branch rule covers `branch_prefix` and the target, since this token usually cannot read those rules.

**A runner serves a required job** when it is online, not paused, has every tag the job needs, and is not protected-only by the rule above.

Read the tags from the resolved job, by [Resolve each job before reading it](#resolve-each-job-before-reading-it). Then the runners, where the token may:

```sh
glab api --hostname <host> "projects/<P>/runners?status=online&per_page=100"
glab api --hostname <host> runners/<id>
```

From the list, `id`, `status`, `paused`, `runner_type` and `description`; from each runner, `tag_list` and `access_level` (`not_protected` or `ref_protected`), which the list does not return. Listing a project's runners needs the Maintainer role, and reading a project or group runner's details needs Maintainer too.

**A Developer token is refused (HTTP 403).** Then infer it from recent jobs: find jobs on the recent MR pipelines above that carry the same tags, and read the `runner` recorded on each (`id`, `description`, `runner_type`, `online`, `status`). A runner that ran a job with these tags recently, and that the job record shows as `online`, probably serves them now. The job record does not carry `access_level`, so the strongest evidence is a job it ran **in a merge request pipeline from an unprotected source branch**: a protected-only runner could not have run that one. Say so in exactly these words, filling in the brackets:

> Runner for `[tags]`: inferred, not observed. This token cannot list the project's runners, so this comes from the runner recorded on recent `[job name]` jobs: `[runner description]` (`#[runner id]`), shown as `[online or offline]`. Its access level could not be read, `[and it ran a job in a merge request pipeline from the unprotected branch <branch>, so it is not protected-only | and none of those jobs came from an unprotected branch's merge request pipeline, so it may be protected-only and unable to run phase MRs]`. A paused runner, or one whose tags changed since, would look the same. The first phase MR will confirm it; if its jobs stay `pending`, the runner is the cause.

In the findings table the runner line ends `(inferred from recent jobs)`.

| Observed | Do |
|---|---|
| An online, unpaused runner with every tag the job needs, `access_level: not_protected` | Nothing. Name it in the findings |
| An untagged job, on a project with `shared_runners_enabled` or an online runner that runs untagged jobs | Nothing |
| Inferred from recent jobs, shown online | Name it as inferred, in the wording above, with whichever access-level clause is true. Do not refuse; where it may be protected-only, ask |
| No runner, observed or inferred, serves the job's tags: every matching one is offline, paused, or `ref_protected` | Refuse, as `SKILL.md` §3 says, naming the job, its tags and the runners you saw, and why each does not count. Where the only matching runners are protected-only, say that a phase MR cannot use them and that the fix is a runner registered as not protected, or protected phase branches |
| No runner information at all: runners refused and no recent job with those tags | Say you could not tell, and ask whether a runner serves those tags |

## Permissions → `plan_writes`, and whether YOLO can merge

Two things the driver needs and a Developer-role token often lacks on a protected branch: pushing to the plan branch, and merging into `target_branch`.

```sh
glab api --hostname <host> projects/<P>/repository/branches/<plan branch>
glab api --hostname <host> projects/<P>/repository/branches/<target>
glab api --hostname <host> projects/<P>
```

From each branch, `can_push` (whether this token can push to it), `protected`, `developers_can_push` and `developers_can_merge`. From the project, `permissions.project_access.access_level` and `permissions.group_access.access_level`: take the higher, where 30 is Developer and 40 Maintainer.

| Observed | Set |
|---|---|
| The plan branch: `can_push: true` | `plan_writes: direct` |
| The plan branch: `can_push: false` | Say so now and follow `SKILL.md` §5's fallback for a protected plan branch. `plan_writes: plan-pr` then needs this token to merge into the plan branch, read by the next rows |
| `target_branch` not protected, and the token is Developer or above | YOLO can merge. Nothing to say |
| `target_branch` protected, `developers_can_merge: true`, and the token is Developer or above | YOLO can merge |
| `target_branch` protected, `developers_can_merge: false`, and the token is below Maintainer | **Warn**, as `SKILL.md` §3 says: YOLO cannot merge here, so every phase waits for a person to press merge |
| `target_branch` protected, and access is granted to specific users or groups you cannot read | Say you could not tell. The first YOLO merge settles it |

Reading the protected branch's own rules (`protected_branches/<name>`) commonly needs Maintainer as well, which is why the branch's own fields are read instead.

## Issues → where the cumulative UAT goes

From the project read, `issues_enabled`.

| Observed | Do |
|---|---|
| `true` | Nothing. A plan that ends without an integration MR files its UAT script as a `UAT: <project>` issue |
| `false` | Say so where it matters: with `integration_pr: false`, or a plan whose phases target the default branch, the cumulative UAT goes to a comment on the last merged MR, which nobody is asked to read |

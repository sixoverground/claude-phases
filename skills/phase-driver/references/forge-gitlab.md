# The forge: GitLab

What is true of GitLab and of no other forge. `SKILL.md` holds the rules, in terms any forge has: a change request, its branch, its comments, its merge. This file says how each of those is done on GitLab, on gitlab.com or a self-managed instance, and why the GitLab way matters where it does.

On GitLab a change request is a **merge request**, and this file calls it an MR.

Read this file at Reconcile, and again after any compaction, as the core says of every forge reference.

**GitLab support is experimental.** One plan has been driven end to end by a driver following this file, on gitlab.com, and [`examples/gitlab-local.md`](https://github.com/sixoverground/claude-phases/blob/main/examples/gitlab-local.md) is that plan with an account of every wake: the plan read and written through the Files API, three MRs opened, gated and merged, a review finding answered, a milestone opened for a person to merge, a session killed and recovered, and a network outage waited out. It has not met a self-managed instance, a Developer-role token, a protected target branch, or a milestone branch that needed re-syncing. Treat a command that fails here as this file being wrong, say so, and do not work around it by guessing.

**What it was checked against.** Every command here was checked against `glab` 1.131.0 (`glab version`) and the GitLab REST API documentation as published in November 2026. The commands for setup, Find, Open, the six gates, a job retry, a merge request pipeline, threads, the plan read and write, and Merge were then run against gitlab.com 19.7.0-pre, Free plan, in that trial; the re-sync pushes, the plan-PR fallback and the issue fallback were not. `glab` flags change between versions, and a self-managed instance can lag gitlab.com by several releases, so a field documented today may be missing on an older server. Where one is, the call fails or the field reads `null`: say which, and treat it as this file being wrong for that server, never as a reason to guess. Re-check these pages when either moves:

- [`glab` command reference](https://docs.gitlab.com/cli/)
- [Repository files API](https://docs.gitlab.com/api/repository_files/)
- [Merge requests API](https://docs.gitlab.com/api/merge_requests/)
- [Pipelines API](https://docs.gitlab.com/api/pipelines/) and [Jobs API](https://docs.gitlab.com/api/jobs/), for gate 3
- [Commits API](https://docs.gitlab.com/api/commits/), for commit statuses and a commit's parents
- [Discussions API](https://docs.gitlab.com/api/discussions/), for gate 5
- [Merge request reviews](https://docs.gitlab.com/user/project/merge_requests/reviews/), for which tiers and versions can request changes
- [Users API](https://docs.gitlab.com/api/users/), [Namespaces API](https://docs.gitlab.com/api/namespaces/) and [Metadata API](https://docs.gitlab.com/api/metadata/)
- [Branches API](https://docs.gitlab.com/api/branches/)
- [Projects API](https://docs.gitlab.com/api/projects/)
- [Notes API](https://docs.gitlab.com/api/notes/) and [Issues API](https://docs.gitlab.com/api/issues/)
- [Personal access tokens API](https://docs.gitlab.com/api/personal_access_tokens/)
- [REST API basics](https://docs.gitlab.com/api/rest/), for path encoding
- [Skipping a pipeline](https://docs.gitlab.com/ci/pipelines/#skip-a-pipeline)

## Setup the session needs

**`glab`, authenticated for the repo's `host`, with a token that has the `api` scope.** `host` is the repo's resolved `host` key, `gitlab.com` when unset. Check it once per session, before Reconcile writes anything:

```sh
glab auth status --hostname <host>
glab api --hostname <host> personal_access_tokens/self
```

The first must exit 0. From the second, read `scopes`, which must contain `api`, and `active`, which must be `true`. The second works for a personal access token. A token from `glab auth login`'s browser flow is an OAuth token, and that endpoint may refuse it; then the first command succeeding is all you can check, so say that the scope was not verified. A token without `api` can read some things and write none of them, which looks like a permissions problem halfway through a transition rather than at the start, which is why it is checked first.

**Name the host and the project on every call.** `glab` otherwise picks the host from the current directory's git remote, or falls back to gitlab.com, and a driver in the wrong directory then talks to the wrong instance. So:

- every `glab api` call passes `--hostname <host>`
- every `glab mr` and `glab issue` call passes `-R https://<host>/<project path>`

**The project path goes into API paths URL-encoded.** A repo is named `group/project`, subgroups included, as in `acme/platform/web`. In an API path that becomes `acme%2Fplatform%2Fweb`. File paths and branch names that contain `/` are encoded the same way, in the path and in query values. Encode with `jq`, which the watcher already needs:

```sh
enc() { jq -rn --arg s "$1" '$s|@uri'; }
P=$(enc acme/platform/web)        # acme%2Fplatform%2Fweb
```

Below, `<P>` is the encoded project path, `<path>` the encoded plan file path, and `<b>` an encoded branch name. An unencoded `/` does not reach the right endpoint and comes back as a 404, which reads as access denied, so a 404 on a path you built yourself is checked for encoding before it is reported.

**Read the project once per session**, for facts several sections below rely on:

```sh
glab api --hostname <host> projects/<P>
```

| Field | Used by |
|---|---|
| `id` | [Find](#find), to tell this project's MRs from a fork's |
| `default_branch` | Milestones, re-sync and the integration MR |
| `issues_enabled` | [Issue fallback](#issue-fallback) |
| `merge_method` (`merge`, `rebase_merge` or `ff`) | [Merge](#merge) |
| `squash_option` | [Merge](#merge) |
| `only_allow_merge_if_pipeline_succeeds`, `allow_merge_on_skipped_pipeline` | [`plan_writes: plan-pr` on GitLab](#plan_writes-plan-pr-on-gitlab) |

## Find

Reconcile asks the forge what is actually true for each row. On GitLab, list the row's repo's MRs by that row's branch, in every state:

```sh
glab api --hostname <host> --paginate "projects/<P>/merge_requests?source_branch=<b>&state=all&per_page=100"
```

`state=all` is what makes a merged or closed MR answer the question as much as an open one does. It is also the server's default, and it is passed anyway so the query does not depend on that.

Keep only entries whose `source_project_id` equals the project's `id`. A fork can open an MR into this project from a branch with the same name, and it is not this row's.

From each entry, read:

| Field | Meaning |
|---|---|
| `iid` | The MR's number within the project, used by every later call |
| `state` | `opened`, `merged` or `closed`. `locked` is a brief state during a merge: read again |
| `title` | Matched for a milestone row, below |
| `source_branch`, `target_branch` | Head and base |
| `sha` | The head commit |
| `references.full` | The `Link`, such as `acme/platform/web!42` |
| `merge_commit_sha`, `squash_commit_sha` | Set once merged; the re-sync and Settled need the commit the merge made |

**The `Link` is `references.full`**, `group/project!<iid>`, subgroups included, as `format.md` specifies. Record it as given rather than building it, so a project path with a subgroup is never shortened.

A milestone row's MR has the target branch as source and the default branch as target, so list by both, then pick the one whose title names the row's id, per SKILL.md's **Which PR is a milestone's**:

```sh
glab api --hostname <host> --paginate "projects/<P>/merge_requests?source_branch=<target_branch>&target_branch=<default_branch>&state=all&per_page=100"
```

One MR, when a later step needs more than the list gives:

```sh
glab api --hostname <host> projects/<P>/merge_requests/<iid>
```

This adds `user.can_merge`, whether the token may merge it, and `detailed_merge_status`, GitLab's own reason an MR cannot merge yet (`need_rebase`, `conflict`, `ci_still_running` and so on).

## Open

Push the branch with git, then open the MR with `glab mr create`:

```sh
glab mr create -R https://<host>/<project path> \
  --source-branch <branch> --target-branch <target_branch> \
  --title '<title>' --description-file <body file> \
  --remove-source-branch=<true|false> --squash-before-merge=<true|false> \
  --yes
```

- **Title and body** are the ones the core specifies for that kind of change request. Write the body to a file and pass it with `--description-file`, so a long body with backticks and newlines reaches the server unchanged.
- **`--remove-source-branch=true`** for a phase MR, and `=false` where the repo sets `merge.delete_branch: false`. Always pass one or the other. Left out, the project's default applies, and the driver no longer knows what happens to the branch at merge. Why this replaces the driver's own delete is in [Delete the branch](#delete-the-branch).
- **`--squash-before-merge=true`** when `merge.method` is `squash`, and `=false` otherwise. Pass it either way, for the same reason.
- **`--yes`** makes sure nothing waits on a prompt. With a title and a description given, `glab` 1.131.0 asks nothing anyway.
- Do not pass `--fill`, which pushes and fills the title from commits, `--push`, or `--auto-merge`.
- **Run it from the repo's own clone.** `-R` names the project, but `glab mr create` still reads the current directory's git remotes, and from a directory whose remotes are all on another host it refuses: `none of the git remotes configured for this repository point to a known GitLab host`, leaving a recovery file under `glab-cli/recover/` and no MR. Seen in the trial with `glab` 1.131.0, opening the milestone MR from the plan's home repo on GitHub. `glab mr merge` and `glab api` did not care.

The output of `glab mr create` is not a field anything reads. **After it returns, run [Find](#find) for the branch**, and take the MR's `iid` and `references.full` from there. That is the same read Reconcile uses, so the `Link` the core records next is the one a later session will find again.

If an open MR already exists for that source branch, the server refuses the create. That is the recovery table's "died after opening the MR, before recording it". Adopt the existing one, by Find, rather than opening a second.

## Opener identity

**Does not apply on GitLab, because reviewers here are triggered by the MR's pipeline, which runs whoever opened the MR.** Skip the read-back after opening. Open with `glab`, authenticated as above, and do not compare the MR's `author` with anything.

### Who opens the PR decides whether it gets reviewed

On GitHub it does, because a reviewer integration there can be scoped to one connected account, and that is what this section exists for in the GitHub reference. No such integration is mapped for GitLab in this copy. If one appears that is scoped to an account, it brings an opener rule with it, and this section is where that rule goes.

## Watch

**No session in this copy can subscribe to GitLab MR activity**, so a session working a GitLab MR arms `watching.md`'s watcher, with its [GitLab template](watching.md#gitlab). The watcher prints the fallback check-in itself: 45 to 60 minutes out, as the core says.

**Almost everything a GitLab reviewer does reaches the watcher.** A reviewer here answers with a job, a note or a thread, and the watcher sees all three. The exception is a request for changes or an approval, which changes a reviewer's state without a note the watcher reads. When that is what you are waiting on, arm the check-in 10 to 15 minutes out rather than 45 to 60.

### Asking a reviewer for a newer review

The core's rule that resolving a thread does not clear gate 4 asks the reviewer for a newer review "where the integration has a way". On GitLab a reviewer runs as a CI job, so there are two ways, both acting on the current head only:

- **Retry the review job** in the head's pipeline, found by [Gate 3](#gate-3-checks):

  ```sh
  glab api --hostname <host> -X POST projects/<P>/jobs/<job id>/retry
  ```

  The response is the new job: read its `id` and `status` (`pending`). Retry a job from the head's pipeline and no other: a job from an older pipeline checks out that pipeline's commit and would review the old head again.
- **Create a merge request pipeline**, where no single job is the reviewer or the head has no pipeline yet:

  ```sh
  glab api --hostname <host> -X POST projects/<P>/merge_requests/<iid>/pipelines
  ```

  Read `id`, `sha` and `status`. This runs every job the project's MR pipeline rules select, not only the reviewer, so it costs a full pipeline. It creates a detached or merged results pipeline, never a branch pipeline, so a project whose CI config has no MR pipeline rules gets nothing from it. Prefer the retry.

GitLab's "re-request review" button notifies a person and starts nothing, so it is not one of the ways.

#### `@codex review` from a person

**A note from a person that says `@codex review` is a request to run the review job again**, the GitLab form of the same request on GitHub, where Codex itself answers it. On GitLab nothing reads the note but you: the reviewer runs only in a pipeline. So answer it by creating a merge request pipeline, the second way above, on the current head, and reply on the MR with the pipeline's id. Create one even where a retry would do, so the request always gets the same answer.

A request is **a person's note**, by [Whose note it is](gates.md#whose-note-it-is), not a system note, whose whole text is `@codex review`. That includes an unstamped note from the account you act as, which on one account is the person. It replaces an earlier rule, "by anyone but the reviewer's `logins`", which on one account would have ruled out the person, since their account is then the reviewer's too. Never write that text in a note of your own on GitLab, even quoted and even stamped, or the next wake answers you. Answer each request once: a pipeline created for the note at the current head is the answer, so do not create another for the same note on a later wake. A request on an MR whose current head already has a marker from the reviewer still gets the pipeline: the person asked for a review, and a second marker for one head costs nothing but the run.

**It needs a running driver.** With no session watching the MR, nothing answers the note. Say so in the reply when you find one that waited, and point the person at the job's **Retry** button on the MR's pipeline page for next time.

## The gates

`gates.md` asks each of the six gates as a question any forge can answer. This is how GitLab answers it.

**Read the MR once per evaluation**, with the single-MR read from [Find](#find), and evaluate every gate against that one reading:

```sh
glab api --hostname <host> projects/<P>/merge_requests/<iid>
```

The head sha is the MR's `sha`. Every gate below is about that sha, and a gate result is discarded the moment it changes, as the core says.

**`review.required` entries work on GitLab as `marker` entries only.** See [Gate 6](#gate-6-reviewer).

### Gate 1: draft

The MR passes when `draft == false`.

### Gate 2: labels

The MR's own `labels`, an array of label names, compared with `blocking_labels`. A scoped label such as `workflow::blocked` is compared by its whole name.

### Gate 3: checks

Three sources, all for the head sha: the jobs of the head's pipeline, its trigger jobs, and external commit statuses. `ci.required`, where set, names jobs (and trigger jobs and external statuses) by `name`. A job from `parallel` or `parallel: matrix` has a name per instance, such as `test 1/3` or `test: [3.2, pg]`, and `ci.required` names each one it needs.

**Find the head's pipeline.** List the MR's pipelines:

```sh
glab api --hostname <host> --paginate "projects/<P>/merge_requests/<iid>/pipelines?per_page=100"
```

From each, read `id`, `sha`, `ref` and `status`. A pipeline **belongs to this head** when either:

- its `sha` equals the head sha. That is a branch pipeline or a detached MR pipeline, which run on the source branch's commit; or
- its `ref` is `refs/merge-requests/<iid>/merge` or `refs/merge-requests/<iid>/train`, and the commit it ran on has the head sha among its parents. That is a merged results or merge train pipeline. It runs on a merge commit GitLab made from the head and the target branch, so its `sha` is never the head sha. Read the parents with:

  ```sh
  glab api --hostname <host> projects/<P>/repository/commits/<pipeline sha>
  ```

  and check that `parent_ids` contains the head sha.

Any other pipeline is not this head's, however recent. **Among the pipelines that belong to this head, merge request pipelines come first**, as GitLab's own merge check has it: "merge request pipelines take precedence over other pipeline types" ([auto-merge docs](https://docs.gitlab.com/user/project/merge_requests/auto_merge/#require-a-successful-pipeline-for-merge)). A merge request pipeline is one whose `source` is `merge_request_event`, or whose `ref` is under `refs/merge-requests/<iid>/` (`head`, `merge` or `train`). So:

1. If any merge request pipeline belongs to this head, the head's pipeline is the newest of those, the highest `id` among them.
2. Only if none does, it is the newest branch pipeline that belongs to this head.

Never let a newer branch pipeline stand in for an older merge request pipeline on the same head: a green branch pipeline would hide a red merge request pipeline, which is a false pass.

The MR's `head_pipeline` is not this answer, only a hint. GitLab describes it as the pipeline for the source branch's head, and just after a push it can still name the previous head's pipeline, so gate 3 always chooses by the two steps above. The watcher reads `head_pipeline` only to notice that something changed, which is all a wake needs; the gate decides.

**Read its jobs and its trigger jobs:**

```sh
glab api --hostname <host> --paginate "projects/<P>/pipelines/<id>/jobs?per_page=100"
glab api --hostname <host> --paginate "projects/<P>/pipelines/<id>/trigger_jobs?per_page=100"
```

From each, read `id`, `name`, `status`, `allow_failure`, `web_url` and, for a failure, `failure_reason`. The jobs list leaves out retried attempts unless asked (`include_retried=true`), so each name appears once, as its latest attempt. `trigger_jobs` is the GitLab 19.2 name; an older server answers the same request at `pipelines/<id>/bridges`, which 19.2 deprecated.

**A trigger job counts as one check, with its own status, and the child pipeline it starts is not read.** GitLab's own pipeline status counts it the same way. A trigger with `strategy: depend` mirrors the child pipeline's result, which is how a project says the child gates the merge; without it, the trigger job succeeds once the child is created, and the child's result gates nothing here either. So `ci.required` can name a trigger job, and cannot name a job inside a child pipeline. A failed trigger job's cause is read from the child, under [Reading a failure](#reading-a-failure).

**Read external commit statuses** on the head sha:

```sh
glab api --hostname <host> --paginate "projects/<P>/repository/commits/<head sha>/statuses?per_page=100"
```

Read `id`, `name`, `status`, `allow_failure`, `description` and `target_url`. This endpoint also returns the jobs of every pipeline that ran on that sha, so keep only entries that are not jobs: drop any whose `id` is a job or trigger job id read above, and any whose `target_url` is a job page of this project (`https://<host>/<project path>/-/jobs/<id>`). What remains was posted by something outside the project's CI.

**Every counted job, trigger job and status either passes, blocks or waits:**

| `status` | Verdict |
|---|---|
| `success` | Pass |
| `skipped` | Pass. Its rules did not select it, or an earlier failure stopped it, and that failure is read in its own row |
| `failed`, with `allow_failure: true` | Pass, as GitHub's `neutral` does. GitLab shows it as a warning and does not fail the pipeline for it |
| `failed` | Block |
| `canceled` | Block |
| `manual`, with `allow_failure: true` | Pass. An optional manual job: nobody has to run it, and GitLab's pipeline does not wait for it |
| `manual`, with `allow_failure: false` | Block. A blocking manual job holds the pipeline until a person plays it, and playing it is the person's decision, never the driver's |
| `created`, `waiting_for_resource`, `preparing`, `waiting_for_callback`, `pending`, `running`, `scheduled`, `canceling` | Wait. Still running or about to; `scheduled` is a delayed job, and `canceling` becomes `canceled` |
| Anything not in this table | Block, and name the status. A status this file does not know is not a pass |

Those are the thirteen job statuses the jobs API documents. External statuses are posted with six of them (`pending`, `running`, `success`, `failed`, `canceled`, `skipped`), and read by the same rows.

**What counts as zero checks**, which blocks unless `ci.allow_none: true`:

- no pipeline belongs to this head, and no external status is on the head sha; or
- the head's pipeline has no jobs, as a pipeline skipped by `[skip ci]` has.

A pipeline that **failed with no jobs** is not zero checks: that is a CI configuration GitLab could not run. Read it with `glab api --hostname <host> projects/<P>/pipelines/<id>` and report its `yaml_errors`; it blocks. Right after a push the head's pipeline can take a few seconds to appear, so read again once before calling a head checkless.

**A name in `ci.required` that matches nothing** blocks, and the report names it. A typo there otherwise counts nothing and reports nothing.

`review.required[].check` does not apply on GitLab (see [Gate 6](#gate-6-reviewer)), so the fourth step of `gates.md`'s **Which checks count** subtracts nothing here. A review job counts like any other job, so a reviewer that cannot run turns this gate red. Put its name in `ci.ignore_checks` only if a reviewer that fails should not stop the merge.

#### Reading a failure

Per the repo's `ci.logs`:

- **`gitlab-jobs`**, and **`auto`**, which resolves to it on GitLab. Fetch the failed job's full trace, and read it from the end, where the error is:

  ```sh
  glab api --hostname <host> projects/<P>/jobs/<job id>/trace > job.log
  tail -n 200 job.log
  ```

  The trace is plain text, not JSON. Widen the tail when the error starts higher up. `glab ci trace <job id> -R https://<host>/<project path>` prints the same log, but streams it while the job runs and prompts when no job is given, so the API form is the one to use. A `failure_reason` other than `script_failure`, such as `runner_system_failure` or `stuck_or_timeout_failure`, says the runner failed rather than the code: say that, since the trace may not show anything the change caused.
- **A failed trigger job.** Read the child: its `downstream_pipeline.id`, then that pipeline's jobs and the failed one's trace, as above. A multi-project trigger's child lives in another project; where the token cannot read it, link its `downstream_pipeline.web_url`.
- **A failed external status** has no log here. Read its `description`, and link its `target_url`.
- **`actions` and `check-output`** are GitHub's values. On a GitLab repo, say once that they do not apply and read with `gitlab-jobs`.

A job's own page, the one to link when its trace does not say why it failed, is its `web_url`.

**One retry per head for a suspected flake**, as `gates.md` allows, with the same call as [Asking a reviewer for a newer review](#asking-a-reviewer-for-a-newer-review):

```sh
glab api --hostname <host> -X POST projects/<P>/jobs/<job id>/retry
```

Say on the MR, in a note, which job you retried and why. Read whether a retry already happened from the forge, never from memory: list the head pipeline's jobs with `include_retried=true`, and a name that appears more than once has had its retry.

### Gate 4: changes requested

A reviewer requests changes on GitLab by submitting a review with **Request changes**, and the request stays until that reviewer approves, or removes it, or someone overrides it. So GitLab keeps one state per reviewer, and that state is already the latest: the core's "a later review by the same author supersedes it" is built in.

**Two reads, either of which is proof that changes are requested:**

```sh
glab api --hostname <host> projects/<P>/merge_requests/<iid>/reviewers
```

Each entry has a `user` and a `state`. A `state` of `requested_changes` is a request for changes by that `user.username`. And the MR's own `detailed_merge_status` reads `requested_changes` when "the merge request has reviewers who have requested changes". Read both: `detailed_merge_status` names only one reason an MR cannot merge, so a running pipeline or an unresolved thread can hide a request for changes from it.

**Absence is not proof, because not every instance can request changes.** It arrived in GitLab 16.11 behind a feature flag and was on by default from 17.2, and it is a Premium and Ultimate feature: on Free, a review submitted with "Request changes" becomes a comment. An instance that cannot record a request for changes reports none, and that looks exactly like "no changes requested". So decide once per session whether this instance can tell you:

- **The version.** `glab api --hostname <host> version`, field `version`. Below 17.2 it cannot tell you, unless a request for changes has been seen on it.
- **The tier, on gitlab.com.** `glab api --hostname gitlab.com namespaces/<top-level group, encoded>`, field `plan`. `free` cannot tell you.
- **The tier, on a self-managed instance**, cannot be read without administrator access. Treat it as unknown.

| Found | Verdict |
|---|---|
| A reviewer in `requested_changes`, or `detailed_merge_status: requested_changes` | **Block**, naming the reviewers. Positive evidence counts on any instance |
| Neither, on an instance known to support it: 17.2 or later, on a paid plan | **Pass** |
| Neither, on an instance that cannot tell you, or where you could not establish that it can | **Off**: this gate does not block, and the report line says why |
| `review.changes_requested_blocks: false` | **Off**, by configuration |

The report line for the third row says that the instance cannot report requested changes, so nobody reads it as a pass:

```
4 reviews      OFF: this instance cannot report requested changes (GitLab 17.8, tier not readable on a self-managed instance)
4 reviews      OFF: this instance cannot report requested changes (gitlab.com, free plan)
4 reviews      FAIL: changes requested by @alice
```

Clearing a request for changes is the reviewer's to do. The core's rule for a bot's latest review blocking still applies: ask it for a newer review by [Asking a reviewer for a newer review](#asking-a-reviewer-for-a-newer-review), and where that cannot clear it, mark the row `Blocked` with that reason.

### Gate 5: threads

List the MR's discussions:

```sh
glab api --hostname <host> --paginate "projects/<P>/merge_requests/<iid>/discussions?per_page=100"
```

Each has an `id`, `individual_note`, and `notes`, and each note has `id`, `type`, `author` (`id`, `username`), `body`, `system`, `resolvable` and `resolved`.

A discussion is a thread for this gate when any of its notes has `resolvable: true`, and it is resolved when every one of those has `resolved: true`. **On GitLab a general thread is resolvable too.** A finding posted as a thread on the MR's overview, with no diff position (`type: DiscussionNote`), gates exactly as a thread on a diff line (`type: DiffNote`) does. Only a plain comment, `individual_note: true`, is not resolvable, so a reviewer that posts only plain comments gives this gate nothing to check, as `gates.md` says of top-level comments.

**Reply in the thread, then resolve it.** The reply's body, like every note you post, ends with the driver's stamp, as [Stamp what you write](../SKILL.md#stamp-what-you-write) says:

```sh
jq -n --rawfile body reply.md '{body: $body}' > reply.json
glab api --hostname <host> -X POST projects/<P>/merge_requests/<iid>/discussions/<discussion id>/notes --input reply.json
glab api --hostname <host> -X PUT projects/<P>/merge_requests/<iid>/discussions/<discussion id> -F resolved=true
```

`-F` sends `true` as a boolean. The response to the last call is the discussion, with its notes now `resolved: true`. Resolving needs the Developer role or above, or to be the MR's author.

A project with **All threads must be resolved** turned on refuses the merge itself while a thread is open (`detailed_merge_status: discussions_not_resolved`), so `review.threads_must_resolve: false` does not get an MR past that setting.

#### Whose thread it is

The core decides whose a note is by [Whose note it is](gates.md#whose-note-it-is), and a thread is its first note's. On GitLab the fields are:

- **The first note** of a discussion: `notes[0]`. Its `body` holds any stamp or marker, and `author.username` and `author.id` its author.
- **The account the driver acts as**: the username `glab` is logged in as for the host, `glab api --hostname <host> user`, field `username`. Compare usernames case-insensitively.
- **A bot account**: `glab api --hostname <host> users/<author id>`, field `bot` is `true`. Project and group access tokens, and service accounts, post as bot users. A `bot` field you could not read is not `true`.
- **An author in `logins`**: `author.username` in the `logins` of a `review.required` entry, matched case-insensitively. Such an author makes the note a reviewer's by account **only when it is not the account the driver acts as**. On one account it is, and then only a reviewer stamp or a marker in the body makes the note a reviewer's.

So the core's three classes come out as:

| `notes[0]` | Whose |
|---|---|
| By the driver's account, body carries `<!-- phases:driver v=1 -->` and no reviewer stamp | The driver's |
| By an account with `bot: true`, or in a `logins` that is not the driver's own, with no driver stamp | A reviewer's |
| Body carries a reviewer stamp or marker naming a configured `marker` entry, by one of its `logins` where it lists any, with no driver stamp | A reviewer's |
| Anything else, including an unstamped note from the driver's account | A person's |

A note the driver wrote before it stamped its notes reads as a person's, which errs toward a wake and an open thread, as the core says.

### Gate 6: reviewer

**Only `marker` entries work on GitLab.** An entry's other ways to be satisfied are GitHub's: a review or inline comment by its `logins`, a `check` judged by `proof`, a 👍 reaction, a review-state record, and `rereview: optional`. None of them is mapped here. A plan that configures any of them for a GitLab repo is told so at Reconcile, once, naming the entries and the repo, with the advice to use a `marker` entry. Until it changes, such an entry is unsatisfied and gate 6 blocks on it.

**Read the marker from the MR's notes:**

```sh
glab api --hostname <host> --paginate "projects/<P>/merge_requests/<iid>/notes?per_page=100"
```

Read `id`, `body`, `author.username`, `system` and `type`. A marker counts only in a note with `system: false` whose `type` is not `DiffNote`: a plain comment (`type: null`) or a general thread's note (`DiscussionNote`), both of which sit on the MR's overview, where the contract puts it. A marker in a `DiffNote` is in a thread on the diff, the case `gates.md`'s table rejects.

Then match it exactly as `gates.md`'s **The review marker** says: the line is `<!-- phases:review v=1 reviewer=<name> sha=<sha> -->`, `reviewer` equals the entry's `marker`, `sha` equals the head sha in full, and, when the entry lists `logins`, `author.username` is one of them. Login matching is case-insensitive, and GitLab adds no suffix to a bot's username, so a project access token's bot user is matched by its username as shown.

**In a merged results pipeline the marker still names the head.** The reviewer job runs on a merge commit there, and a reviewer that meets the contract takes the sha from the source branch (`CI_MERGE_REQUEST_SOURCE_BRANCH_SHA`), as the review contract asks. A marker that names a merged results pipeline's own commit names a sha that is never the head: it is not proof. Say so in the report, since the fix is in the reviewer, not in the MR.

```
6 reviewer     PASS (codex marker @ a1b2c3d)
6 reviewer     BLOCK: no codex marker for a1b2c3d (latest is for 9f8e7d6)
6 reviewer     BLOCK: entry `logins: [codex-bot]` has no marker, and only marker entries work on GitLab
```

**The reviewed heads for `stuck.max_review_rounds`** are the distinct full shas named by markers that satisfy a configured `marker` entry by the rules above, apart from being the current head: right reviewer, right author where `logins` is set, a top-level note, `v=1`, a full sha. Two markers for one sha are one round. Read them from the notes on every wake, as the core says.

#### The decline reaction

**Does not apply on GitLab, because a reaction is not proof here.** GitHub's reviewer on smart detect answers some PRs with only a 👍. GitLab has reactions (award emoji), but no reviewer this copy supports answers with one, and gate 6 reads markers alone. A 👍 on an MR proves nothing to the driver.

#### `rereview: optional`

**Does not apply on GitLab, because it rests on signs that are not read here.** Its decline rule needs a review, inline comment, 👍 or review-state record from the reviewer, and on GitLab a `marker` entry is satisfied by its marker and nothing else, as `gates.md` says of every marker entry. A reviewer that may skip a commit posts no marker for it, which blocks.

#### Codex's review-state comment

**Does not apply on GitLab, because that comment is something GitHub's Codex integration writes.** On GitLab, a Codex review runs as a CI job and reports through the marker.

## Write the plan

Read the plan file from `home_repo` on the plan branch, through the Repository Files API:

```sh
glab api --hostname <host> "projects/<P>/repository/files/<path>?ref=<plan branch, encoded>"
```

From the response, read `content`, which is base64 when `encoding` is `base64`, and **`last_commit_id`**, the sha of the last commit that changed this file. That is the write token.

```sh
... | jq -r .content | base64 --decode > plan.md
```

Write it back with the same token:

```sh
jq -n --arg branch '<plan branch>' --arg msg 'chore(plan): <project> phase <N> -> <Status> [skip ci]' \
      --arg last '<last_commit_id>' --rawfile content plan.md \
      '{branch: $branch, commit_message: $msg, encoding: "text", content: $content, last_commit_id: $last}' > body.json
glab api --hostname <host> -X PUT projects/<P>/repository/files/<path> --input body.json
```

`branch` here is the plain branch name, not encoded: it travels in the body. A success is HTTP 200 with `file_path` and `branch`. It does not return the new `last_commit_id`, and nothing should need it: the core re-reads the token at the start of every transition.

**The write token is `last_commit_id`, and it must always be passed.** The parameter is optional in the API, and a write without it is accepted whatever happened to the file in between, which turns the lock into nothing. With it, a write after someone else changed the file is refused with HTTP 400 and this message:

```
glab: You are attempting to update a file that has changed since you started editing it. (HTTP 400)
```

That, and only that message, is the stale-write conflict the core's lock rules handle in **Writing to the plan**. Any other refusal of a plan write is not a conflict, so never retry it as one: a 403 or a 400 saying the branch is protected or you may not push means the token cannot write the plan branch, below. Read every token fresh, as the GitHub reference says of its sha: when the plan branch is also a `target_branch`, merging a phase MR moves it.

**`[skip ci]` in the commit message skips the branch pipeline** that a push to the plan branch would otherwise start. GitLab honours it in any capitalisation, and it holds for a commit made through this API: in the trial, every plan write through the Files API left a pipeline on the plan branch with status `skipped` and no jobs, as a `git push` with the same message did. So a skipped plan commit still appears in the pipeline list; nothing ran. If plan commits ever start jobs, say so once.

### `plan_writes: plan-pr` on GitLab

When the plan branch refuses direct writes, each transition becomes a one-file MR against the plan branch, **merged at once by the driver**. That is what the core's "with auto-merge" means on GitLab: auto-merge would leave the MR waiting on a pipeline nobody is watching, so it is turned off and the driver merges in the same transition.

1. **Write the file to a new branch in one call.** The same `PUT` as above, with `branch` set to a new branch under the repo's `branch_prefix`, such as `claude/plan-<project>-<N>-<status>`, and `start_branch` set to the plan branch, added to `body.json`. GitLab creates the branch from the plan branch and commits to it in one request, and `last_commit_id` is still checked against the file as it was on the plan branch.
2. **Open the MR** by [Open](#open), from that branch into the plan branch, titled with the same `chore(plan): ... [skip ci]` message, with `--remove-source-branch=true` and `--squash-before-merge=false`. On GitLab 19.5 and later, with the `ci_skip_pipeline_from_mr_title` feature flag on, the `[skip ci]` in the title skips the MR's own pipelines; in the commit message it would not. **Do not count on it**: an older self-managed server, or one with the flag off, starts the pipeline anyway, so step 3 checks.
3. **If the MR has a pipeline, let it finish before merging.** Read the MR (`glab api --hostname <host> projects/<P>/merge_requests/<iid>`) and look at `head_pipeline`. When it is `null`, the title skip worked or no pipeline is configured: go on. When it is set and its `status` is still running or pending, the server did not skip it, and a merge now would be refused wherever the project requires a successful pipeline. Wait for it as for any check, by the core's §4: the transition is not finished, so nothing the write describes may start meanwhile. When it fails, that is the hard stop below. When it succeeds, go on. Say once that this server does not skip pipelines from an MR title, so the person knows why plan writes are slow here.
4. **Re-read the plan file's `last_commit_id` on the plan branch.** If it is not the token from step 1, someone wrote in between: close the MR (`glab api --hostname <host> -X PUT projects/<P>/merge_requests/<iid> -f state_event=close`), delete its branch, and treat it as the stale-write conflict. An MR's merge does not check a file's token, so this read is the lock, and like GitHub's merge it narrows the window rather than closing it.
5. **Merge it** by [Merge](#merge), with `--message` set to the same `chore(plan): ... [skip ci]` line, so the merge commit on the plan branch skips its pipeline too.

**Where the token may not merge into the plan branch, stop.** Read `user.can_merge` on the MR before merging. When it is `false`, or the merge is refused for permission, or the MR's pipeline was **actually skipped** while the project allows merges only after a pipeline succeeds (`only_allow_merge_if_pipeline_succeeds`) and does not count a skipped one (`allow_merge_on_skipped_pipeline: false`), or its pipeline failed (step 3), no status can be recorded at all. A pipeline that ran and passed satisfies the first setting; `allow_merge_on_skipped_pipeline` concerns skipped pipelines only, so it never stops a merge whose pipeline succeeded. That is a hard stop, not a `Blocked` row: a `Blocked` would itself be a plan write. Close the plan MR, say which branch refused and why, and that the driver needs either push or merge access to it, or the plan moved to a branch it can write. By golden rule 10's last sentence, the action the write described has not started.

**A protected branch that is both the plan branch and a `target_branch`** stops two things at once. A Developer-role token commonly can neither push to a protected branch nor merge into it, so it cannot write the plan, and it cannot merge phase MRs into it either. The plan-write stop above catches this at the first transition, before any phase starts. Say both in the report, so the fix asked for covers both.

## Merge

Merge with the head sha just read, and auto-merge explicitly off:

```sh
glab mr merge <iid> -R https://<host>/<project path> --sha <head sha> --auto-merge=false --yes [--squash]
```

- **`--sha`** is the head sha from your last read, the MR's `sha` from [Find](#find). The core's rule to re-read the head as your last read before merging still applies, and the sha it read is the one passed.
- **`--auto-merge=false`.** `glab` 1.131.0 defaults `--auto-merge` to true, and when a pipeline is running that turns the call into "merge when checks pass" instead of a merge. That would merge later, at a head nobody gated. Always pass it.
- **`--squash`** when `merge.method` is `squash`. For `merge` and `rebase` pass nothing: on GitLab the shape of the merge is the project's `merge_method`, not a per-merge choice. `merge` makes a merge commit; `rebase_merge` and `ff` keep history linear, which is the nearest GitLab has to `rebase`. A project whose `squash_option` forces or forbids squashing overrides `--squash` either way; when `merge.method` and the project disagree, say so once.
- **Never pass `--rebase`.** `glab` refuses it alongside `--sha`, and it moves the head, which is not a merge of the head you gated.
- Pass no `--remove-source-branch`: the MR already carries the choice, from [Open](#open).

**The head check is atomic on the server.** GitLab merges only if the source branch's head still equals `--sha`. A head that moved after your read refuses the merge, which closes the window the GitHub reference says GitHub leaves open. The refusal is HTTP 409 with the message `SHA does not match HEAD of source branch`. `glab` passes that through in its error output and exits non-zero; the exact wording around the message was not confirmed against a server. Treat it as the core's "the head moved": discard the gate result and start over from the new head.

Other refusals, and what they mean here:

| Refusal | Meaning |
|---|---|
| HTTP 401 | The token may not merge this MR. Read `user.can_merge`; for a protected target branch, see the end of [`plan_writes: plan-pr` on GitLab](#plan_writes-plan-pr-on-gitlab) |
| HTTP 405 | The MR cannot be merged in its present state. Read `detailed_merge_status` for why |
| HTTP 406 or 422 | The merge itself failed, or GitLab has not finished checking mergeability. `glab` retries a 406 itself, up to three times |
| `detailed_merge_status: need_rebase` | The project's `merge_method` is `ff` or `rebase_merge` and the branch is behind. Update it as SKILL.md's merge-conflict case says. That is a new head, so the gates start over |

A merge whose response says the MR is now `merged` is the merge. Confirm it by [Find](#find) before writing `Merged`, as the recovery rules say.

## Delete the branch

**The server deletes it, and the driver deletes nothing itself.** A phase MR is opened with `--remove-source-branch=true` unless `merge.delete_branch: false`, and GitLab then deletes the source branch at merge, whoever merges: the driver, or a person in the UI, for whom the box is ticked already and who can untick it. That is the gap the GitHub reference describes, closed by the server rather than by the driver.

The core's guard on which branches may be deleted still holds, and is enforced at [Open](#open): only a phase MR, whose branch matches `branch_prefix`, or a plan-write MR, is ever opened with the flag. A milestone or integration MR never is, so the plan branch and a `target_branch` are never deleted by a merge.

**A branch still there after a merge** means the project or a protection rule kept it. GitLab does not delete a protected branch. Say so once, and recommend the project's *Delete source branch* default under Settings → Merge requests, or the protection rule's exception, as the GitHub reference recommends its own setting. The phase is merged either way.

## Milestone and integration change requests

Both are MRs from the repo's `target_branch` to its `default_branch`. Find one by [Find](#find)'s source and target query. Open one by [Open](#open), with **`--remove-source-branch=false`**, passed explicitly rather than left out, because leaving it out applies the project's default, which often deletes the source branch at merge. For a milestone that would delete the branch the re-sync then re-creates, which the core handles. For the integration MR it could delete the plan branch, where the plan lives on the feature branch it ships. A person who wants the branch gone ticks the box themselves when they merge.

Pass `--squash-before-merge` from `merge.method` as for a phase. The person who merges can change it.

**Warn about skip instructions before it is merged**, as the GitHub reference does. When you report one ready, read the messages of its commits, `glab api --hostname <host> --paginate "projects/<P>/merge_requests/<iid>/commits?per_page=100"`, field `message`, for `[skip ci]` or `[ci skip]`, matched case-insensitively, which GitLab honours for push pipelines. A squash commit's message can quote them, and then the pipeline on the target branch does not run. Name the commits in the ready message. It changes nothing and blocks nothing.

**The integration MR opens unless the repo's resolved `integration_pr` is `false`**, by §8. With it `false`, open nothing from that repo's `target_branch`, and the cumulative UAT goes to [Issue fallback](#issue-fallback).

Never merge either. That is the core's rule, and nothing on GitLab changes it.

## Re-sync a branch

The core says which case applies and that every move is conditional on the head just checked. Git's own leases do that on any forge, so on GitLab the pushes are the same as on GitHub:

| Case | Push |
|---|---|
| Re-create | `git push --force-with-lease=refs/heads/<target_branch>: origin <default sha>:refs/heads/<target_branch>` (an empty lease means "must not exist") |
| Fast-forward | `git push origin <default sha>:refs/heads/<target_branch>` (a plain push refuses anything but a fast-forward) |
| Squash or rebase | `git push --force-with-lease=refs/heads/<target_branch>:<merged head sha> origin <default sha>:refs/heads/<target_branch>` |

Read both heads with `git ls-remote`, as the core says. The "merged head" is the milestone MR's `sha` at merge, and the commit the merge made is its `merge_commit_sha`, or its `squash_commit_sha` when it was squashed and the project made no merge commit.

**The branches API can re-create a branch, and cannot move one.** The re-create case may instead go through:

```sh
glab api --hostname <host> -X POST projects/<P>/repository/branches -f branch=<target_branch> -f ref=<default sha>
```

which creates the branch only if no branch of that name exists, the same condition as the empty lease. Read `commit.id` from the response and check it is `<default sha>`. The API documents no refusal for an existing name, so if it answers anything but `201 Created`, re-read both heads and apply the core's rules again. Prefer it only where git cannot push to the host from this session.

**There is no API to move an existing branch to a new sha.** Deleting and re-creating it is not a move: it is unconditional, so it could drop a commit pushed between the read and the delete, which is the outcome the core's last case exists to prevent. GitLab also refuses to delete a protected branch at all. So the fast-forward and squash cases are always the git pushes above.

**A protected `target_branch` refuses the squash case's forced push** unless the protection allows force pushes, and may refuse even the fast-forward for a Developer-role token. That is the core's refused update: report it once, with the matching command from the table, filled in, and start nothing in that repo until the branch is where it should be. Allowing force pushes, or unprotecting the branch for a moment, is the person's decision, never the driver's.

## Issue fallback

Where the core sends something to "an issue on the forge", on GitLab that is a GitLab issue in that repo's project: a standalone defect, the arbiter's `issue` verdict, and the UAT fallback at the end of a plan, which is an issue titled `UAT: <project>` with the outstanding items.

**Issues are available only where the project has them on.** Read `issues_enabled` from the project, by [Setup](#setup-the-session-needs). Where it is `true`:

```sh
jq -n --arg title 'UAT: <project>' --rawfile description <script file> '{title: $title, description: $description}' > issue.json
glab api --hostname <host> -X POST projects/<P>/issues --input issue.json
```

A long body goes in a JSON file through `--input`, as the plan write does, so it reaches the server unchanged. Record the issue by its `references.full`, `group/project#<iid>`.

**Where it is `false`**, the project has no issues, and the core's no-issues fallback applies: for the UAT script, a comment on the last merged MR, with `UAT-pending` left as it is and the summary saying so. A comment is a note, and ends with the driver's stamp like every note you post:

```sh
jq -n --rawfile body <script file> '{body: $body}' > note.json
glab api --hostname <host> -X POST projects/<P>/merge_requests/<iid>/notes --input note.json
```

Check the field rather than trying the create: an issue create on a project with issues off is refused with HTTP 403, which would read as access denied when the forge has only said it has no issues.

For a standalone defect or an `issue` verdict in a project without issues, say where it would have gone and put it in the phase report instead.

## Unreachable or denied

Golden rule 10 turns on which of these a failure was, so classify every failed `glab` call by its output, not by its exit code, which is non-zero for both.

**Unreachable: the forge did not answer.** `glab` prints the transport error from its HTTP client, naming the URL:

| Seen | Output, from `glab` 1.131.0 |
|---|---|
| DNS failure | `Get "https://<host>/api/v4/...": dial tcp: lookup <host>: no such host.` |
| Timeout | `... dial tcp <address>:443: i/o timeout.` |
| Refused connection | `... dial tcp <address>:443: connect: connection refused.` |
| Gateway error | An HTTP 502, 503 or 504, often with no GitLab message: `glab: HTTP 502` |

**A self-managed host behind a VPN usually fails as the first or second row.** With the VPN down, the company's DNS that resolves the host is out of reach, or the name resolves and the address does not answer. Neither says anything about the phase, and a Mac waking from sleep with the VPN not yet up looks exactly like this.

**Denied: the forge answered and said no.** `glab api` prints the server's message and status as `glab: <message> (HTTP <code>)`, for example `glab: 404 Not Found (HTTP 404)` or `glab: 403 Forbidden (HTTP 403)`. A 401, 403 or 404 from GitLab itself is denied, as SKILL.md §3 says. Two checks first:

- **A 404 on a path you built** may be an encoding mistake, by [Setup](#setup-the-session-needs). Check the encoding before marking anything `Blocked`.
- **A 4xx with no GitLab message**, printed as a bare `glab: HTTP 403`, may come from a proxy or single sign-on gateway in front of the host rather than from GitLab. Say so to the user once and treat it as unreachable: GitLab itself has not answered.

**Neither, and handled where it arises:** the 400 stale-write conflict in [Write the plan](#write-the-plan), the 409 moved head in [Merge](#merge), and HTTP 429, which is rate limiting. Treat a 429 as a wait, like unreachable, and count nothing toward `stuck.max_cycles`.

The `glab mr` commands report server errors through a different client from `glab api`, so their wording differs from the table above. The status code and the server's message are in it either way; classify by those. The exact form was not confirmed against a server.

## Working copy

A driver on GitLab is often local, on the person's own machine. **It works in a clone of its own**, never in the directory a person or a CI runner is using:

```sh
git clone https://<host>/<project path>.git <a directory of the driver's own>
```

The driver checks out branches, resets, rebases and force-pushes with leases. Done in a person's checkout, that moves their working tree under them and can lose uncommitted work; done in a runner's build directory, it changes what the runner builds. A clone of its own costs one clone per repo per session.

Run `glab` from that clone. The explicit `--hostname` and `-R` above mean the current directory never decides which instance or project a call reaches, but `glab mr create` refuses outright from a directory with no remote on the host, as [Open](#open) says, so a driver whose home repo is on another forge runs it from here.

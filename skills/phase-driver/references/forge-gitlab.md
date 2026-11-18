# The forge: GitLab

What is true of GitLab and of no other forge. `SKILL.md` holds the rules, in terms any forge has: a change request, its branch, its comments, its merge. This file says how each of those is done on GitLab, on gitlab.com or a self-managed instance, and why the GitLab way matters where it does.

On GitLab a change request is a **merge request**, and this file calls it an MR.

Read this file at Reconcile, and again after any compaction, as the core says of every forge reference.

**This copy maps everything except the gates.** It can find, open and merge MRs, write the plan and move branches. It cannot yet decide whether an MR may merge: see [The gates](#the-gates), which says what the driver does instead.

**What it was checked against.** Every command here was checked against `glab` 1.131.0 (`glab version`) and the GitLab REST API documentation as published in November 2026. No command in this copy has yet been run against a GitLab server. `glab` flags change between versions, and a self-managed instance can lag gitlab.com by several releases, so a field documented today may be missing on an older server. Where one is, the call fails or the field reads `null`: say which, and treat it as this file being wrong for that server, never as a reason to guess. Re-check these pages when either moves:

- [`glab` command reference](https://docs.gitlab.com/cli/)
- [Repository files API](https://docs.gitlab.com/api/repository_files/)
- [Merge requests API](https://docs.gitlab.com/api/merge_requests/)
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
glab api --hostname <host> "projects/<P>/merge_requests?source_branch=<b>&state=all"
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
glab api --hostname <host> "projects/<P>/merge_requests?source_branch=<target_branch>&target_branch=<default_branch>&state=all"
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

The output of `glab mr create` is not a field anything reads. **After it returns, run [Find](#find) for the branch**, and take the MR's `iid` and `references.full` from there. That is the same read Reconcile uses, so the `Link` the core records next is the one a later session will find again.

If an open MR already exists for that source branch, the server refuses the create. That is the recovery table's "died after opening the MR, before recording it". Adopt the existing one, by Find, rather than opening a second.

## Opener identity

**Does not apply on GitLab, because reviewers here are triggered by the MR's pipeline, which runs whoever opened the MR.** Skip the read-back after opening. Open with `glab`, authenticated as above, and do not compare the MR's `author` with anything.

### Who opens the PR decides whether it gets reviewed

On GitHub it does, because a reviewer integration there can be scoped to one connected account, and that is what this section exists for in the GitHub reference. No such integration is mapped for GitLab in this copy. If one appears that is scoped to an account, it brings an opener rule with it, and this section is where that rule goes.

## Watch

**No session in this copy can subscribe to GitLab MR activity.** So a session working a GitLab MR is woken by `watching.md`'s watcher, and the watcher's GitLab template arrives in phase 5b. Until then, rely on the fallback check-in alone: schedule it 45 to 60 minutes out, as the core says, and 10 to 15 minutes out when the thing you are waiting on finishes without anyone pushing or commenting. Do not improvise a polling loop: `watching.md` says why.

### Asking a reviewer for a newer review

Where the integration has a trigger comment, post it as a note on the MR:

```sh
glab api --hostname <host> -X POST projects/<P>/merge_requests/<iid>/notes -f body='<trigger comment>'
```

GitLab's own "re-request review" is not mapped in this copy. Which reviewers have a trigger, and how gate 4 reads their answer, comes with the gates in phase 5b.

## The gates

**The GitLab gate mappings are not in this copy yet.** `gates.md` asks each gate as a question any forge can answer, and its links go to the GitHub answers. None of those answers is right for an MR. Reading a failed job's trace, for `ci.logs: gitlab-jobs`, comes with them.

So on a GitLab change request the driver **does not evaluate the gates and does not merge**, whatever YOLO says. When a GitLab MR has no outstanding work, or would otherwise be gated:

- report that this copy of the driver cannot gate GitLab change requests yet, naming the MR's `Link`, and that a newer release may
- stop working that row: no merge, no gate report, no `ready to merge`
- do not mark it `Blocked`. Nothing is wrong with the phase, and a person can still merge it in the UI. When they do, the driver notices on its next wake, by Find, and §7 runs as for any merge.

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

**`[skip ci]` in the commit message skips the branch pipeline** that a push to the plan branch would otherwise start. GitLab honours it in any capitalisation. Its documentation does not say in so many words that a commit made through this API is treated as a push for this purpose, so if plan commits start pipelines, say so once.

### `plan_writes: plan-pr` on GitLab

When the plan branch refuses direct writes, each transition becomes a one-file MR against the plan branch, **merged at once by the driver**. That is what the core's "with auto-merge" means on GitLab: auto-merge would leave the MR waiting on a pipeline nobody is watching, so it is turned off and the driver merges in the same transition.

1. **Write the file to a new branch in one call.** The same `PUT` as above, with `branch` set to a new branch under the repo's `branch_prefix`, such as `claude/plan-<project>-<N>-<status>`, and `start_branch` set to the plan branch, added to `body.json`. GitLab creates the branch from the plan branch and commits to it in one request, and `last_commit_id` is still checked against the file as it was on the plan branch.
2. **Open the MR** by [Open](#open), from that branch into the plan branch, titled with the same `chore(plan): ... [skip ci]` message, with `--remove-source-branch=true` and `--squash-before-merge=false`. The `[skip ci]` in the title is what skips the MR's own pipelines. In the commit message it would not.
3. **Re-read the plan file's `last_commit_id` on the plan branch.** If it is not the token from step 1, someone wrote in between: close the MR (`glab api --hostname <host> -X PUT projects/<P>/merge_requests/<iid> -f state_event=close`), delete its branch, and treat it as the stale-write conflict. An MR's merge does not check a file's token, so this read is the lock, and like GitHub's merge it narrows the window rather than closing it.
4. **Merge it** by [Merge](#merge), with `--message` set to the same `chore(plan): ... [skip ci]` line, so the merge commit on the plan branch skips its pipeline too.

**Where the token may not merge into the plan branch, stop.** Read `user.can_merge` on the MR before merging. When it is `false`, or the merge is refused for permission, or the project allows merges only after a pipeline succeeds (`only_allow_merge_if_pipeline_succeeds`) and does not count a skipped one (`allow_merge_on_skipped_pipeline: false`), no status can be recorded at all. That is a hard stop, not a `Blocked` row: a `Blocked` would itself be a plan write. Close the plan MR, say which branch refused and why, and that the driver needs either push or merge access to it, or the plan moved to a branch it can write. By golden rule 10's last sentence, the action the write described has not started.

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

**Where it is `false`**, the project has no issues, and the core's no-issues fallback applies: for the UAT script, a comment on the last merged MR, with `UAT-pending` left as it is and the summary saying so. A comment is a note:

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

Run `glab` from that clone or from anywhere else: the explicit `--hostname` and `-R` above mean the current directory never decides which instance or project a call reaches.

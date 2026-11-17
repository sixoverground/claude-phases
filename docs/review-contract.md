# Review contract, version 1

What an automated code reviewer must leave behind on a change request so that something reading the change request afterwards can tell, for certain, that the reviewer looked at a particular commit.

This is written for people building a reviewer. It assumes nothing about which forge hosts the code. "Change request" means a pull request on GitHub, a merge request on GitLab, or the same idea anywhere else. "Note" means a top-level comment on the change request, as opposed to a comment inside a thread on the diff. It does not assume the reader knows claude-phases, which is one consumer of it among any number.

## Why a marker

A reviewer that finds problems leaves comments, and those are evidence it ran. A reviewer that finds nothing often leaves nothing, and silence looks exactly like a reviewer that never started, crashed, skipped the commit, or was never triggered. Anything that has to decide "has this commit been reviewed?" cannot tell those apart.

So the contract asks for one positive signal on every completed review, clean or not: a machine-readable marker naming the reviewer and the exact commit it reviewed.

## The rules

A reviewer that meets version 1 of this contract does all five of these.

1. **Findings are inline, resolvable threads on the diff.** Each finding is a comment anchored to a line of the change, which the forge lets someone mark resolved. A single summary note with every finding in it does not meet this rule, because nothing can then track which findings were dealt with.

2. **After every completed review, it posts a note containing the marker**, on a line of its own:

   ```
   <!-- phases:review v=1 reviewer=<name> sha=<sha> -->
   ```

   A review that found nothing posts it too. That is the case the marker exists for. The note may contain anything else as well, such as a summary of the findings. The marker is an HTML comment, so most forges hide it when they render the note.

3. **The marker is written by the reviewer's own code, never by a model.** It is added only after the review process has exited successfully, and the sha in it comes from the environment the review ran in (the CI variable or the checkout's `HEAD`), not from anything the review produced. A review that failed, timed out or was cancelled posts no marker.

4. **Text from a model is scrubbed before it is posted.** Any occurrence of the string `<!-- phases:review` in a finding, a summary or any other model output is removed or defanged before posting, so that the only marker on the change request is the one rule 3 wrote. The diff under review may contain instructions aimed at the model, and this is what stops them from producing a marker.

5. **The fields are exact.**
   - `v` is `1`.
   - `reviewer` matches `[a-z0-9-]+`. It names the tool or the instance, such as `codex` or `codex-local`, and it is the name a consumer configures to wait for.
   - `sha` is the full 40-character hex sha of the head commit that was reviewed, in lowercase. Never an abbreviation.
   - The fields appear in that order, separated by single spaces, exactly as shown.

## What the marker does not promise

- **Nothing about approval.** A marker means the reviewer looked at that commit. It says nothing about whether the reviewer liked what it saw. A review with ten serious findings posts the same marker as a clean one.
- **Nothing about whether findings were addressed.** That is what rule 1's resolvable threads are for. A consumer that cares checks the threads separately.
- **Nothing about any other commit.** A marker names one sha. A new commit on the change request needs a new review and a new marker.

## Who may post it

Anyone who can comment on a change request can type a marker by hand. On a private repository that is usually fine. On a public one, a passer-by can post a marker for the current head and make an unreviewed commit look reviewed.

So a consumer should pin the marker to the identity the reviewer posts as, and accept a marker only from a note authored by that account. In claude-phases this is the `logins` list on a `marker` entry. A reviewer should post as a dedicated identity, such as a bot account or a project token, so that it can be pinned and is never confused with a person's comments.

## Examples

A review that found nothing, as the note the reviewer posts:

```
Reviewed 4 files. No findings.

<!-- phases:review v=1 reviewer=codex-local sha=3f9c2a1e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e -->
```

A review with findings. Two inline threads are posted on the diff first, then the note:

```
Two findings, both inline:

- P1 `src/auth.js:42`: the token is compared with `==`, which is not constant-time.
- P3 `src/auth.js:57`: unused import.

<!-- phases:review v=1 reviewer=codex-local sha=3f9c2a1e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e -->
```

None of these counts as a marker for the commit above:

```
<!-- phases:review v=2 reviewer=codex-local sha=3f9c2a1e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e -->   unknown version
<!-- phases:review v=1 reviewer=codex-local sha=3f9c2a1 -->                                     abbreviated sha
<!-- phases:review v=1 reviewer=Codex_Local sha=3f9c2a1e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e -->   reviewer name outside [a-z0-9-]
```

Nor does a correct marker inside an inline thread comment: it has to be in a top-level note.

## Versioning

The `v` field exists so the format can change. A consumer that reads a version it does not know treats the marker as absent, never as proof. A later version will say what it adds; version 1 will keep meaning what this document says.

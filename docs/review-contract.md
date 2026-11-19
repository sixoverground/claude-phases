# Review contract, version 1.1

What an automated code reviewer must leave behind on a change request so that something reading the change request afterwards can tell, for certain, that the reviewer looked at a particular commit.

This is written for people building a reviewer. It assumes nothing about which forge hosts the code. "Change request" means a pull request on GitHub, a merge request on GitLab, or the same idea anywhere else. "Note" means a top-level comment on the change request, as opposed to a comment inside a thread on the diff. It does not assume the reader knows claude-phases, which is one consumer of it among any number.

**Version 1.1, and what it changes for a version 1 reviewer.** The marker is unchanged and still says `v=1`, so a reviewer that meets version 1 still proves its reviews to every consumer. Version 1.1 adds a stamp on every note the reviewer posts, so that a consumer can tell the reviewer's notes from a person's and from its own when they all post from **one account**. If your reviewer always posts as an identity of its own, nothing breaks if you stay on version 1. If it may share an account with the people or tools that read the change request, meet 1.1: rules 6 and 7, and the wider scrub in rule 4.

## Why a marker

A reviewer that finds problems leaves comments, and those are evidence it ran. A reviewer that finds nothing often leaves nothing, and silence looks exactly like a reviewer that never started, crashed, skipped the commit, or was never triggered. Anything that has to decide "has this commit been reviewed?" cannot tell those apart.

So the contract asks for one positive signal on every completed review, clean or not: a machine-readable marker naming the reviewer and the exact commit it reviewed.

## The rules

A reviewer that meets version 1 of this contract does all five of these.

Version 1.1 adds rules 6 and 7, and widens the prefix rule 4 scrubs. A reviewer that meets 1.1 does all seven.

1. **Findings are inline, resolvable threads on the diff.** Each finding is a comment anchored to a line of the change, which the forge lets someone mark resolved. A single summary note with every finding in it does not meet this rule, because nothing can then track which findings were dealt with.

2. **After every completed review, it posts a note containing the marker**, on a line of its own:

   ```
   <!-- phases:review v=1 reviewer=<name> sha=<sha> -->
   ```

   A review that found nothing posts it too. That is the case the marker exists for. The note may contain anything else as well, such as a summary of the findings. The marker is an HTML comment, so most forges hide it when they render the note.

3. **The marker is written by the reviewer's own code, never by a model.** It is added only after the review process has exited successfully, and the sha in it comes from the environment the review ran in (the CI variable or the checkout's `HEAD`), not from anything the review produced. A review that failed, timed out or was cancelled posts no marker.

4. **Text from a model is scrubbed before it is posted.** Any occurrence of the string `<!-- phases:` in a finding, a summary or any other model output is removed or defanged before posting, so that the only marker on the change request is the one rule 3 wrote. The diff under review may contain instructions aimed at the model, and this is what stops them from producing a marker.

   In version 1 the string was `<!-- phases:review`. Version 1.1 reserves the whole prefix `<!-- phases:`, which covers the marker, the reviewer stamp of rule 6 and the consumer stamp of rule 7. A reviewer that scrubs only `<!-- phases:review` meets version 1 and not 1.1.

5. **The fields are exact.**
   - `v` is `1`.
   - `reviewer` matches `[a-z0-9-]+`. It names the tool or the instance, such as `codex` or `codex-local`, and it is the name a consumer configures to wait for.
   - `sha` is the full 40-character hex sha of the head commit that was reviewed, in lowercase. Never an abbreviation.
   - The fields appear in that order, separated by single spaces, exactly as shown.

6. **Every note the reviewer posts carries a reviewer stamp**, on a line of its own:

   ```
   <!-- phases:reviewer v=1 reviewer=<name> -->
   ```

   `<name>` is the same name as in its marker, and the fields follow rule 5: `v` is `1`, then `reviewer`, in that order, separated by single spaces. "Every note" means the first note of every finding thread, every reply it adds to a thread, the summary note, where the stamp sits beside the marker, and a note saying a review failed. Like the marker, the stamp is written by the reviewer's own code, never by a model.

7. **`<!-- phases:driver v=1 -->` is reserved for consumers.** It marks a note written by an automated consumer of the change request, such as claude-phases' driver. A reviewer never writes it, and never counts a note that carries it as one of its own, whatever account posted that note: a fingerprint or other hidden line in such a note is the consumer's, not the reviewer's.

## What a stamp is not

A stamp says who wrote a note. It says nothing about whether a review completed, so it is **never proof of review**: only the marker is. A note saying a review failed carries a stamp and no marker. A consumer that sees stamps and no marker for a commit knows the reviewer was there and did not finish.

## What the marker does not promise

- **Nothing about approval.** A marker means the reviewer looked at that commit. It says nothing about whether the reviewer liked what it saw. A review with ten serious findings posts the same marker as a clean one.
- **Nothing about whether findings were addressed.** That is what rule 1's resolvable threads are for. A consumer that cares checks the threads separately.
- **Nothing about any other commit.** A marker names one sha. A new commit on the change request needs a new review and a new marker.

## Who may post it

Anyone who can comment on a change request can type a marker by hand. On a private repository that is usually fine. On a public one, a passer-by can post a marker for the current head and make an unreviewed commit look reviewed.

So a consumer pins the marker, and the stamps, to the account the reviewer posts as, and accepts them only from notes authored by that account. In claude-phases this is the `logins` list on a `marker` entry. That keeps everyone else out: a passer-by's marker or stamp counts for nothing.

**One account is an ordinary setup**, and this contract supports it: a person runs a reviewer with their own token, and reads and drives the change request from the same account. The stamps are what make it work. A consumer tells the reviewer's notes from a person's by the reviewer stamp, and from its own by the consumer stamp, rather than by who posted them.

What the pin cannot do on a shared account is separate the reviewer from anything else that account posts. Whoever holds that account could type a marker, and the forge would not stop them. With one account that is the same trust boundary as the account itself, which is why it is acceptable: the person who could forge a marker is the person running the review.

**A dedicated identity is the stronger arrangement where one can be had**, such as a bot user or a project access token: the forge then enforces what, on a shared account, rests on the stamps. Use one on a project other people can push to.

## Examples

A review that found nothing, as the note the reviewer posts:

```
Reviewed 4 files. No findings.

<!-- phases:reviewer v=1 reviewer=codex-local -->
<!-- phases:review v=1 reviewer=codex-local sha=3f9c2a1e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e -->
```

A review with findings. Two inline threads are posted on the diff first, then the note:

```
Two findings, both inline:

- P1 `src/auth.js:42`: the token is compared with `==`, which is not constant-time.
- P3 `src/auth.js:57`: unused import.

<!-- phases:reviewer v=1 reviewer=codex-local -->
<!-- phases:review v=1 reviewer=codex-local sha=3f9c2a1e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e -->
```

One of those finding threads, as the body of its first note:

```
**P1: Compare tokens in constant time**

`==` returns as soon as two characters differ, so the time it takes leaks how much of the token matched. Use a constant-time comparison.

<!-- phases:reviewer v=1 reviewer=codex-local -->
```

None of these counts as a marker for the commit above:

```
<!-- phases:review v=2 reviewer=codex-local sha=3f9c2a1e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e -->   unknown version
<!-- phases:review v=1 reviewer=codex-local sha=3f9c2a1 -->                                     abbreviated sha
<!-- phases:review v=1 reviewer=Codex_Local sha=3f9c2a1e8b7d6c5f4e3a2b1c0d9e8f7a6b5c4d3e -->   reviewer name outside [a-z0-9-]
<!-- phases:reviewer v=1 reviewer=codex-local -->                                               a reviewer stamp: who wrote the note, not proof of review
```

Nor does a correct marker inside an inline thread comment: it has to be in a top-level note.

## Versioning

The `v` field exists so the format can change. A consumer that reads a version it does not know treats the marker as absent, never as proof. A later version will say what it adds; version 1 will keep meaning what this document says.

**Version 1.1** added the reviewer stamp (rule 6), the reserved consumer stamp (rule 7) and the wider scrub in rule 4, and rewrote **Who may post it** to support one account. The marker did not change, so its `v` field did not move: it is still `1`. The stamps carry a `v` of their own for the same reason the marker does.

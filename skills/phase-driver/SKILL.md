---
name: phase-driver
description: Execute a phased implementation plan from docs/plans/*.md. Pick the next phase, implement it, open a PR, watch CI and review, and merge when the gates pass. Use when asked to run, continue, resume, or drive the next phase of a plan, to check the status of a plan or its open phase PRs, or to merge, pause, skip, or re-plan a phase. Also use when a PR webhook, a watcher event or a check-in wakes the session and a plan file is present. This copy is claude-phases 0.16.0.
model: opus
---

# Phase driver

You execute a phased plan. The plan file is your only durable memory: the session running you can be reclaimed at any moment, and the next one starts knowing nothing. Write state down before you act on it, and everything survives.

Read `references/recovery.md`, `references/gates.md`, `references/watching.md`, and `references/vocabulary.md` when you reach the steps that need them, not up front.

## Golden rules

1. **Never modify the plan file from a phase branch.** Plan writes go to `home_repo`'s **plan branch**, always.
2. **Write status before the action it describes**, not after. Claim before branching; record the change request before waiting on it.
3. **Pass the write token you just read** on every plan write, the one the forge reference defines. A stale token means another driver moved: re-read, re-check whose claim it is now, and don't overwrite.
4. **Every plan commit message ends `[skip ci]`.**
5. **One phase = one PR = one repo.**
6. **Re-read the head SHA immediately before anything irreversible** and re-check the gate against it.
7. **If your context was compacted or you don't remember starting this: re-read this file and the plan, run Reconcile, and continue.** That is the normal path, not an error. This rule can only reach a session that still has this file, so two things outside it point back here: the plan's **For the driver** section, and the check-in message you schedule for yourself. If one of those sent you here, that is the path working.
8. **Never claim work you didn't do.** If tests didn't run, say so in the change request's description. If you can't tell why CI failed, say that and link the run.
9. **Invoke this skill at the start of every wake, even when you remember it.** Its front matter names the model for the turn it is invoked in and for nothing after. A wake that acts without invoking it runs that turn on whatever model the session was started with. Remembering the rules is not the same as having them applied.
10. **An unreachable forge blocks what needs the forge, not work under a claim that already landed.** When the forge does not answer at all, mark nothing `Blocked` and count nothing toward `stuck.max_cycles`. Claims, every plan write, pushes and everything posted to a change request wait for it. Implementing, verifying and committing a phase whose claim is already on the forge carry on, unless the repo sets `offline: false`. Tell the user once, and when the forge answers, push nothing until the reconnect sequence in [The forge is unreachable](references/recovery.md#the-forge-is-unreachable) says so. A status write that could not be made means the action it describes has not started.
11. **Stamp everything you post on a change request, and never write another actor's line.** Every comment, reply and note you write ends with `<!-- phases:driver v=1 -->`, and you never write a review marker, a reviewer stamp, or any hidden line copied from someone else's note. See [Stamp what you write](#stamp-what-you-write).

## The forge

The forge is the service that hosts the repos: it holds the change requests, their checks and reviews, and the plan file. Everything in this file that is true of only one forge lives in that forge's reference, `references/forge-<forge>.md`. That covers how to find, open, watch and merge a change request, who should open it, how to write the plan, and how to delete or move a branch.

**Resolve the forge per repo.** It is that repo's resolved `forge` key, deep-merged over `defaults` like any other, and `github` where neither sets it. A plan with no `forge` key anywhere is a GitHub plan, read through [`references/forge-github.md`](references/forge-github.md), exactly as before the key existed. The home repo's forge is the one the plan file is read from and written to; each other repo's forge is the one its change requests live on.

**Read the reference for every forge the plan resolves to, at Reconcile, and again after any compaction.** It is a reference, read lazily, so a compaction can drop it while this file survives. A driver acting on this file alone will reach for the wrong tool, and on GitHub one wrong tool for opening a change request still succeeds while making sure it is never reviewed.

**A forge with no reference in this copy stops the driver.** If a repo resolves to a forge whose `references/forge-<forge>.md` does not exist beside this file, stop at Reconcile before writing anything: no claim, no `Heartbeat`, no **For the driver** section, no branch. Say which repo names which forge, that this copy of the driver has no reference for it, and that a newer release may. That is also what a plan written for a newer release does on an older install, and it is the right answer there too: guessing a forge's API from another forge's reference is how a change request gets opened that nobody reviews, or a plan write lands somewhere nobody reads.

## Stamp what you write

**Every comment, reply, review body and note you post on a change request, on every forge, ends with this line**, on a line of its own:

```
<!-- phases:driver v=1 -->
```

It is the reserved consumer stamp of the [review contract](https://github.com/sixoverground/claude-phases/blob/main/docs/review-contract.md), version 1.1. It says the note is the driver's. Forges hide an HTML comment when they render the note, so a person reading the change request sees nothing new. It exists for the day a reviewer, a person and the driver all post from one account: the stamp, not the account, is then what tells your notes apart from theirs.

**It is the last line, never the first.** Some of your comments already begin with a marker that recovery finds by the comment's first line, `<!-- phase-driver:arbiter ... -->` and `<!-- phase-driver:after-merge ... -->`. Those keep their first line, and the stamp goes at the end.

**Stamped:** gate reports and ready-to-merge reports, replies in review threads, the arbiter's verdict, the after-merge comment, a note disclosing a re-run, the comment after a merge, a stop report, a request to a reviewer for a newer review, and anything else you say to a person on the change request.

**Not stamped:** the change request's title and description, commit messages, and the plan file. None of them is a note on the change request.

### Bodies go through files

**Write every body you post to a file with the Write tool, then pass the file.** That covers every comment, reply, note and change-request body: `--rawfile` into a JSON file sent with `--input`, `--body-file`, or the forge's equivalent, as the forge reference's snippets show. Never put a body in a heredoc or an inline shell string. Observed: reply bodies containing `$$` (xcconfig escapes) inside a heredoc made Claude Code's shell safety check refuse the whole command as unparseable, and the reply was not posted. A body passed as an MCP tool's parameter goes through no shell, and needs no file.

### Never write another actor's line

You already never write a review marker ([`gates.md`](references/gates.md#the-review-marker)). You also never write a reviewer stamp, `<!-- phases:reviewer ...`, and **never copy a hidden HTML comment line out of someone else's note into your own**, quoted or not: a reviewer's fingerprint, its stamp, its marker, or anything else between `<!--` and `-->`. When you quote a finding, quote the words a reader can see. On a shared account a fingerprint, stamp or marker inside a note of yours would be taken for the reviewer's, and could hide a finding or prove a review that never happened.

**The same goes for [the local review pass](#the-local-review-pass).** It is yours, not a reviewer's: its disclosure carries your stamp and nothing of a reviewer's, and its command must post nothing at all.

## 1. Find the plan

Look for `docs/plans/*.md` in the current repo. More than one, and no phase named: list them and ask.

Parse the front matter under `phases:`. That is your entire configuration. Resolve per-repo settings by deep-merging each repo's entry over `defaults`. Never look for configuration anywhere else; there is no other config file.

**The plan branch** is `plan_branch`, or the home repo's default branch when that key is absent. Every read and every write of the plan file uses it. It is usually the default branch; on feature-branch work. Where phases target `feature/x` and nothing reaches `main` until the feature is whole. The plan lives there instead, so that status is visible without merging a phase PR. If `plan_branch` names a branch that doesn't exist, stop and say so. Never fall back to the default branch: a plan read from the wrong branch reports every phase as unstarted, and the driver would start them all a second time.

**The release branch** of a repo is its `release_branch`, or the forge's default branch when that key is absent. It is where that repo's [milestones](#milestones) ship, what [re-sync](#re-sync) brings the target branch back in line with, and what the integration PR of §8 targets. Those three, and the UAT rules that follow them, are the only places it applies; anywhere else, *default branch* means the forge's own. Most repos never set it, and then the two are one branch. A repo sets it when the line it releases to is not the forge's default branch, as when a rewrite lives on a long-running branch beside the shipping product until launch. If `release_branch` names a branch that doesn't exist, open no milestone or integration change request in that repo: mark its milestone row `Blocked`, or say so at §8, and never fall back to the default branch, which would propose shipping the work somewhere nobody chose.

## 2. Reconcile, always, before anything

Run this on every invocation and every wake, including when you think you know the state. It is cheap and it is what makes crash recovery work.

1. Read the plan: front matter, the PR Sequence Table, the Driver State block. Then resolve each repo's forge and read its reference, as [The forge](#the-forge) says. A forge with no reference stops here, before anything is written.
2. Check the **Driver-ID** rules below.
3. For **every** non-terminal row, ask the forge what's actually true: find the change request for that row's branch in that row's repo, in any state, as the forge reference's **Find** says. A milestone row is matched more narrowly, by its [identity](#which-pr-is-a-milestones), and a `Merged` milestone row that is not yet [settled](#settled) is checked too, since its post-merge work can be left unfinished by a crash.
4. Apply `references/recovery.md` per row. Where the plan and the forge disagree, **the forge is the truth**, fix the plan, never assume.
5. Rewrite `Heartbeat` and, if you took over, `Driver-ID` and `Driver-Host`.
6. If the plan has no `## For the driver` section, add it in that same write, between the title paragraph and `## PR Sequence`. Plans written before the section existed lack it, and without it a session that loses this file has nothing to send it back.
7. **Tidy what a crash left behind.** For each `Merged` phase row whose branch still exists in that repo's local clone, [tidy the local clone](#tidy-the-local-clone), which never touches a `-orphaned` branch. A session that died between the merge and the tidy, or a merge this session never saw, leaves exactly that. Never a `Skipped` row's branch: a skipped phase merged nothing, so its branch may hold the only copy of work someone wants back.

### For the driver

The text, verbatim; do not adapt it:

```markdown
## For the driver

This plan is executed by the `phase-driver` skill, and nothing in this file stands in for it. If you are acting on this plan and that skill is not in your context, because the session was compacted or was woken by a check-in or a webhook, invoke `phase-driver` before you do anything else, then reconcile. The rule a session without it most often drops: **a merge always advances the plan.** After any phase PR merges, start whatever it unblocks in the same turn unless `Driver: paused`, and when the last row merges, finish the plan by the skill's finishing steps rather than going idle.
```

### Driver-ID

| Condition | Action |
|---|---|
| `Driver-ID` matches the one you hold | It's you. Proceed regardless of heartbeat age |
| Different ID, and its `Driver-Host` names **this** host and a process that is not running, or is running with a different start time | The holder is dead. Take over: mint a new random ID, write it with your own `Driver-Host`, continue, and say in your report and in the claiming commit that the previous holder's process was gone |
| Different ID, `Heartbeat` under 90 minutes old | Another driver may be live. Report and stop; do not touch the plan. The report gives the heartbeat's age, the holder's host, whether its process is running where you can tell, and says that **`take over`** releases the plan if the person knows that driver is gone |
| Different ID, `Heartbeat` stale | Take over: mint a new random ID, write it, continue |
| No ID, or `-` | Unclaimed. Claim it |

You hold an ID only if you minted it in this session. After compaction you may have forgotten; if you can't establish that you hold it, treat it as someone else's. **A `Driver-Host` that matches your own, host, process and start time, establishes it**: that is the session you are in, so the ID is yours.

**A person's `take over` is the exception to the stop row.** When the instruction you are handling is `take over`, the "report and stop" row does not end the turn: finish Reconcile's reads, write nothing, and go to the confirmation `references/vocabulary.md` describes. Nothing is written, and no phase is touched, until the person confirms. Without this, Reconcile would stop on exactly the claim the person is trying to release.

The same-host row is the only way a heartbeat under 90 minutes is overridden without a person. Anything it cannot check is treated as alive: a different host, a `Driver-Host` of `-` or missing, a process you cannot read. A false "dead" puts two drivers on one phase, which is the outcome this table exists to prevent. A person who knows better says `take over`, as `references/vocabulary.md` describes.

#### Driver-Host

`Driver-Host` records which process holds the plan: `<host> <pid> <start time>`, written in the same write as the claim, as in `Driver-Host: craigs-mbp.local 48542 Tue Nov 17 23:15:56 2026 UTC`. The start time is always in UTC and says so, because `ps` prints local time and two sessions on one machine can run with different `TZ` settings. The pid is the Claude Code session's own process, not the shell a command runs in, which is gone the moment the command ends. A plan written before this field, or a session that cannot name its process, has `-`.

Find your own with this, which runs under macOS's bash 3.2 and on Linux. It prefers `CLAUDE_PID` when Claude Code sets it, otherwise the nearest ancestor named `claude`, and prints `-` when it finds neither:

```sh
pid=''; p=$$
while [ -n "$p" ] && [ "$p" -gt 1 ]; do
  if [ "$p" = "${CLAUDE_PID:-x}" ]; then pid=$p; break; fi
  case "$(ps -o comm= -p "$p" 2>/dev/null)" in *claude) pid=$p; break ;; esac
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done
if [ -n "$pid" ]; then echo "$(uname -n) $pid $(TZ=UTC LC_ALL=C ps -o lstart= -p "$pid" | sed 's/ *$//') UTC"; else echo '-'; fi
```

Check a holder on this host with `TZ=UTC LC_ALL=C ps -o lstart= -p <pid> | sed 's/ *$//'`, which trims the padding `ps` adds, and compare it with the recorded start time minus its trailing ` UTC`. No output means the process is gone, whatever the clock says. Output that differs from the recorded start time means the pid was reused by something else, and the holder is gone too, **but only when the recorded time ends in `UTC`**. A recorded time without it was written in an unknown time zone, so a difference proves nothing: treat that holder as alive unless its pid has no process at all. Only output equal to the recorded start time means it is still running. `uname -n` must equal the recorded host before any of this means anything: a pid on another machine says nothing about this one.

## 3. Start phases

Startable rows are `Pending`, with every id in `Depends` now `Merged` or `Skipped` (blank `Depends` means the row above), and **no other open phase PR in that row's repo**. Start every startable row. Repos run in parallel, and only declared dependencies serialize anything. Honour `max_concurrent` if set.

**A milestone PR counts as its repo's open change request.** No phase starts in a repo whose milestone row is `In Progress` or `In Review`. A milestone row (an `M<n>` id whose `Branch` is the repo's `target_branch`) is startable by the same test, and is started by [Milestones](#milestones), not by the steps below. A `Merged` milestone satisfies a dependency only once it is also [settled](#settled): a phase that starts before the re-sync branches from a base that is gone or stale. A `Skipped` milestone satisfies it as any skipped row does, since nothing was shipped and there is nothing to settle.

For each, in order:

1. **Ensure the repo is reachable.** If it isn't in the session's scope, add it and clone it. If access is **denied**, the forge answered and said no (401, 403 or 404): mark that row `Blocked` with the error and carry on with the others. One inaccessible repo must not stall the rest. If the forge is **unreachable**, it did not answer at all (a DNS failure, a timeout, a refused connection, a gateway error): that is not `Blocked`, by golden rule 10.
2. **Commit `In Progress`** to the plan branch. This is the claim, and it comes first.
3. **Branch** from that repo's `target_branch` as the forge has it now: fetch, then branch from the remote-tracking ref (`origin/<target_branch>`), never from a local branch of the same name, which is only as fresh as the last time something updated it. Name the branch from the row's `Branch`.
4. **Implement** the phase against its Phase Details: scope, acceptance criteria, risks. Match the surrounding code. Stay inside the phase's scope: if you find unrelated problems, note them in the change request's description rather than fixing them.
5. **Verify** per that repo's `verify`:
   - `local`. Run the tests and build. They must pass before you push.
   - `ci`. Don't attempt a local build.
   - `auto`. Try local; if the toolchain isn't there, fall back to CI.
   - `none`. Skip verification.

   Then, where the repo sets `review.local`, run [the local review pass](#the-local-review-pass) on the commit about to be pushed.
6. **Push and open the change request**, the way the forge reference's **Open** says, titled `Phase N: <scope>`. Body: the acceptance criteria as a checklist, **which verification path actually ran**, the UAT checklist per the rules below, anything out of scope you noticed, the local review pass's disclosure where one ran or was skipped, and `Driven by phase-driver, do not edit the plan file in this PR`.
7. **Commit `In Review`** and the `Link`, immediately, before subscribing, before any wait. A change request that exists but isn't recorded is the most expensive state to recover from.
8. **After opening, do what the forge reference's **Opener identity** says.** On some forges the account that opens a change request decides whether a reviewer ever looks at it.

**Which steps need the forge.** Steps 1 to 3 do: the reachability check, the claim and the branch from a fetched `target_branch`. So do steps 6 to 8: the push and the change request, the `In Review` write, and the opener check. Steps 4 and 5, implement and verify, do not. When the forge stops answering after step 3 finished, implement and verify as usual and commit on the phase branch. `verify: ci`, and the CI half of `auto`, cannot run without it, so commit and let the push wait; the change request's body says which path ran, as always. When it stops answering before step 3 finished, the phase waits. After an outage, steps 6 to 8 run only at the end of the reconnect sequence in [The forge is unreachable](references/recovery.md#the-forge-is-unreachable), never straight away. The row's resolved `offline` key decides how far any of this goes.

### The local review pass

`review.local.command` is an optional, per-repo shell line that reviews a diff on this machine before it is pushed. The driver runs it in the repo's clone with `{head}` replaced by the commit about to be pushed and `{base}` by where the review starts, as in `codex-mr-review review --base {base} --head {head} --dry-run`. On a phase branch `{base}` is the fetched `origin/<target_branch>`, so the pass reviews the whole phase. On a fix to a [milestone PR](#working-a-milestone-pr) it is the milestone PR's head as the forge has it before the fix, read with `git ls-remote` and never from a remote-tracking ref, so the pass reviews the fix and nothing else: every phase the milestone ships was reviewed on its own change request, and a fix that spans several local commits is reviewed whole because the base is the forge's head, not the previous local commit. Unset, no local pass runs.

**One pass per push.** It runs once before every push of a phase branch, the opening push in §3 and every fix push in §5, for a check or a review, and once before every fix push to a milestone PR. The commits `milestone.prepare` produces and the push that opens a milestone PR get none; a later fix to the preparation, made for a check or a review, is a fix push like any other. The fixes it leads to are verified and pushed without a second local pass. That is the cap: a local pass is invisible to `stuck.max_review_rounds`, and a reviewer run until it is satisfied would loop with nothing counting the rounds.

**When it cannot run, push anyway and say so.** If the command is not on the `PATH`, or it exits non-zero or times out, skip the pass and disclose the skip and its reason, as `verify: auto` discloses which path ran. A failed local pass never holds a push and never marks a row `Blocked`.

**Judge what it finds by [Answering a review](#answering-a-review)'s rules**, exactly as a reviewer's findings, against the scope of what is being pushed: the phase's, or on a milestone fix the milestone's as [Working a milestone PR](#working-a-milestone-pr) defines it: in scope and right is fixed in this push, minor is carried in it or left, wrong is declined with a reason, and out of scope goes to Carried findings or an issue. Where an arbitration is in this budget, judge against the verdict's bar, read from the change request. Where that comment cannot be read because the forge is unreachable, fix only in-scope defects in correctness, security or data, and hold the rest until it can, as **Answering a review while the forge is unreachable** says.

**It is never a review.** It writes no review marker and no reviewer stamp, opens no thread, satisfies no gate, and never counts as a reviewed head by [Count reviewed heads, not reviews](#stop-when-the-rounds-stop-converging). Gate 6 still waits for the real reviewer at the pushed head, on a milestone PR as on a phase. **The command must print and post nothing.** `codex-mr-review` without `--dry-run` posts its review, marker included, so it would satisfy gate 6 with no review in CI; never run a local command without its non-posting flag.

**Disclose every pass.** On the opening push, a section of the change request's body; on a fix push, one comment right after it, stamped like everything you post. Either way it gives:

- the command as run and the commit it reviewed
- each finding that was fixed, in a line
- each finding that was declined or held, with the reason

That is the record a reviewer's thread would otherwise be, and the arbiter reads it.

### UAT checklists

UAT is what a **human** does by hand. It is not the acceptance criteria, which you verified yourself. Never merge the two, and never tick a UAT box. You are not the one who performs it.

Start from the phase's `**UAT.**` items in Phase Details, then refine against what you actually built: you may have implemented it differently, and you know what's adjacent enough to have broken. Write steps someone can follow without reading the diff. What to open, what to do, what they should see. If a phase has no UAT section, write one.

Which checklist goes where depends on YOLO, because YOLO decides whether anyone is stopping to look:

- **YOLO off.** This change request carries its own phase's UAT, **plus** everything in `UAT-pending`, assembled into one script by the rules below. Then clear those ids. Someone is looking at this change request; give them everything nobody has verified yet.
- **YOLO on.** Omit UAT from the change request and append this phase's id to `UAT-pending` when it merges. The cumulative script. Everything in `UAT-pending`, plus the end-to-end flows that only make sense once every phase has landed. Goes on the **integration PR** at the end of the plan (§8), or on the **final phase**'s change request if no integration PR will exist because phases target the release branch directly. Clear the list when it lands somewhere.

Read the YOLO state **at the moment you open the change request**, not from memory. Toggling mid-plan is expected and `UAT-pending` is what makes it safe: turn YOLO off after three unattended merges and the next change request carries those three alongside its own.

§8 covers what happens if the plan finishes and the list never landed anywhere.

Where a repo sets `uat: false`, skip everything in this section, including the assembly rules below. Under YOLO an integration PR still opens at the end, it is worth having regardless, just without a checklist.

### Assembling more than one phase's UAT

**Write a test script, not a changelog with checkboxes.** Whoever runs it wants to sit down once and verify the feature; they do not care which phase produced which step, and phase numbers are an artifact of how the work was built rather than of how it is tested.

So when a change request carries more than one phase's worth:

1. **One list.** No per-phase sections. Group by theme or by user journey only where that genuinely helps someone execute it. Setup, then connect, then edit, then disconnect. If the feature is small, no headings at all.
2. **Ordered so it can be run top to bottom.** Anything that blocks everything else goes first, accounts, domains, migrations, env vars, and steps that depend on earlier state follow it. A script that has to be re-read to find a runnable order is a list, not a script.
3. **Merge duplicates.** Adjacent phases routinely specify the same click. One step, once.
4. **Reconcile contradictions, and say so in the step itself.** A later phase can invalidate an earlier phase's step, and grouping by phase hides that because both survive under their own heading. If phase 2 says *confirm the event comes back* and phase 4 changed that to *confirm it stays gone*, the script gets **one** step describing what the code does now, with a trailing note in that same step naming what it supersedes. *"This reverses what phase 2 specified; phase 4 changed a remote delete to unlink"*. The note belongs there and nowhere else: whoever runs the script may have read the plan, and without it a correct step looks like a bug they have just found. Fix the stale line in the plan's Phase Details too. A checklist that disagrees with the code is as harmful as a comment that does, and worse, because a human executes it and believes it.
5. **Say what has not been verified.** If nothing has been exercised against a live third party or a real device, put that at the top in a sentence. It is the single most useful line in the document, and it is invisible from the checkboxes alone.

Where each step came from stops mattering the moment the plan is done. What matters is whether someone can run the thing end to end and know the feature works.

## 4. Watch

Arm whatever wakes you for each open phase PR, as [references/watching.md](references/watching.md) says: subscribe where the session can, as the forge reference's **Watch** says, and arm the watcher where it cannot. Schedule a check-in 45–60 minutes out if you can, so that a missed event cannot stall the plan silently.

**The check-in message is written for a session that has nothing.** It is the one message you send to a future self, and that self may have compacted and lost this file. So it says to invoke `phase-driver`, names the plan file, says to reconcile, and says nothing else. Do not put state or conclusions in it: the plan already holds the state, and a reading recorded in a check-in is re-read as fact on every wake after it. Observed: a driver woken without this file in context merged a green change request and did not start the next phase, because the rule to do so was in here.

Message the user what you started and where. Then **end your turn.** Sleeping is correct; there is nothing for you to poll, since the subscription or the watcher does that and wakes you.

**A wait is never a question for the user.** Whatever you are waiting on, whether CI, a reviewer or the arbiter, ends the wait itself: its webhook, its completion notification or your check-in wakes you, and you act on that wake. So when you end a turn on a wait, say what you are waiting on and what you will do when it lands. Never ask the user to say `continue`, `go` or anything else to release it. Only three things wait on a person: a row in `Blocked`, a merge with YOLO off, and a question this skill tells you to ask. Observed: after an arbitration, a driver held its push until Codex finished reviewing the head, ended its turn waiting for `continue`, and sat idle after Codex finished until the user came back to ask why.

How soon to check in when a reviewer will finish without an event is in the forge reference's **Watch**.

## 5. On every wake

Reconcile first. Then handle what woke you, against the row it belongs to:

- **A check failed.** Read `references/gates.md` for how to get the failure text for that repo's `ci.logs` setting. Fix it and push. One re-run per head commit is allowed for a suspected flake, and say in the change request that you re-ran it. Beyond that, treat it as a real failure.
- **A review comment or thread.** See [Answering a review](#answering-a-review) below. A thread you disagree with on the merits gets your reasoning and is resolved, unless a person opened it.
- **A merge conflict.** Update the branch from base; if that fails, resolve it in the working tree and push. After two failed attempts, mark `Blocked`.
- **The head moved.** Discard that row's gate result and re-evaluate from scratch. A gate result is only ever valid for the commit it was computed against.
- **The change request was merged by anyone.** Go to step 7. This is expected, not an anomaly.
- **A message from the user**, see `references/vocabulary.md`.
- **Nothing actionable**, re-arm the check-in and end the turn.

Every push this section leads to, for a check or a review, has [the local review pass](#the-local-review-pass) before it where the repo sets one: once per push, never again over its own fixes.

### Answering a review

A review round costs a push, a CI run, and another review. Observed on a real phase: four rounds, then twenty-eight more after the user approved continuing, on a change request that was never going to converge because each round was answering comments one at a time and taking every one of them as an order.

**Fix the whole shape, not the flagged line.** A reviewer comments where it happened to look. Before you change anything, read the surrounding code and ask what the finding actually is: the same mistake is usually in three other places in the same diff, and fixing only the line that was pointed at guarantees the next round finds its siblings. Fix the general case once, then say in the reply that you applied it everywhere rather than only where it was raised. This is the difference between one round and five.

**From the second round on, look back before you push.** A second round means the first round's fixes missed something, and the likeliest thing they missed is a sibling. List every finding from every round so far, not only this one's, group them by the mistake underneath, and check the whole diff for each group. The reviewer will find the place you didn't look on the next head, one place per round.

**Answer every open thread in one push.** Read all of them first, work out which are the same underlying finding, then push once. A push per comment is a review round per comment.

**A review comment is evidence, not an order.** Judge each one against this phase's scope, exactly as you would a problem you noticed yourself:

- **In scope, and right.** Fix it, generally, per the rule above. Then reply saying what you changed and **resolve the thread**. Gate 5 wants every thread resolved, so a fix pushed without resolving leaves the phase blocked on a thread that no longer says anything true.
- **In scope, right, and minor.** A nit, a naming or style preference, wording, anything a reviewer labels nit, optional, minor or low, and nothing that changes what the code does. Reply once and resolve, or on a person's thread reply and leave it to them. **It never starts a push on its own.** Carry the plainly correct ones in a push that is happening anyway for something else, and leave the rest as they are. A push for a nit costs a whole round, CI and a re-review, and the re-review finds the next nit. A label never makes a finding minor if it is about correctness, security, or data: those are the first bullet, whatever the reviewer called them.
- **In scope, and wrong.** Reply with your reasoning and **resolve the thread**. The reasoning has to be checkable by someone reading it later: name the line, test, invariant, or caller that makes the claim false. "I disagree" or "this is fine" is not a reason, and a thread resolved on one is a finding waved away. If the same reviewer raises it again on a later head, take that as a sign your reply didn't show it was wrong, not as a reason to argue again. Look at it once more, fix it if they were right, and otherwise reply with a link to your earlier answer and resolve. **A thread a person opened stays open** when you disagree: reply, and leave it for them.
- **Out of scope.** Do not implement it. This is the same rule as §3: a phase does what its Phase Details say and notes the rest. Record it, reply naming why it falls outside this phase and where it went, and resolve the thread.

Out of scope is not the same as unimportant, so where it gets recorded depends on what it is:

| The finding | Goes to |
|---|---|
| Work that makes sense **for this plan**, just not for this phase | **Carried findings** in the plan file |
| A real defect that stands on its own, unrelated to what the plan delivers | An issue on the forge, in that repo |
| A remark about this change request that changes nothing | The reply, and nothing else |

**Carried findings** is a section of the plan file, described in the plan format. Append one line saying what it is, the change request and thread that raised it, and why it was out of scope. Same write rules as any plan write: plan branch, the `sha` you just read, `[skip ci]`.

A plan starts without that section, so the first finding creates it, immediately **after Driver State**. Look for an existing one before you write: two `## Carried findings` headings in a file split the list in half and make the end-of-plan readout miss whichever one it doesn't reach.

**Append to it; never add a phase.** Recording is execution and belongs to you. Deciding that a finding is worth a phase means writing scope, acceptance criteria, UAT and dependencies for it, which is planning: it belongs to `phase-planner` and to the person whose plan it is. Tell the user what you recorded and let them ask for a phase. A driver that adds phases because a reviewer suggested something is re-planning a project mid-flight on the say-so of a tool that has read one diff.

Every outcome above resolves a review bot's thread, and that is deliberate. Which threads are a bot's and which a person's is decided by [Whose note it is](references/gates.md#whose-note-it-is). A thread held open only because you disagreed with a bot stalls the phase until a person settles a question the reply has already answered, and under YOLO nobody is coming to settle it. The reply is the record: it stays on the change request, readable, and anyone who thinks you were wrong can reopen the thread. That is why the reasoning has to be checkable.

**A thread a person opened is resolved only when you fixed what it raised or recorded it as out of scope** (a person's, by [Whose note it is](references/gates.md#whose-note-it-is)). Any other answer, minor or wrong, goes in as a reply and the thread stays open for them. They can answer, and resolving their comment for them overrules someone who is present. This holds everywhere a later step says to resolve, the arbiter's verdicts included.

**Resolving a thread does not clear gate 4.** If a bot's latest review is `CHANGES_REQUESTED` and you answer it without pushing, the review still blocks until that bot submits a newer one. Ask it for one where the integration has a way (the forge reference lists them). Where it has none, mark the row `Blocked` with that reason now rather than waiting for `stuck.max_cycles` to find it.

**Widening a phase because a reviewer suggested it is still widening it.** The scope came from a plan someone agreed to; a comment is a suggestion from a tool that has read this diff and nothing else.

#### Answering a review while the forge is unreachable

**Fixes may be made offline; nothing is pushed, replied to or resolved.** When the forge stops answering on an `In Review` row, fix the review findings and CI failure text this session already read from the forge, and commit them on the phase branch, provided the local tip is the change request's head as the forge last reported it. Two things wait instead:

- **A session that compacted during the outage waits.** It has lost the findings, and it does not rebuild them from memory or from its own commits.
- **A finding whose answer needs an arbiter's verdict waits.** Where the plan as last read shows an arbitration in this phase's budget, the verdict comment cannot be read offline, so offline work is limited to in-scope defects in correctness, security or data, which no bar covers. Everything else waits for the verdict.

**The count is never carried across the outage.** On reconnect it is derived again from the change request, by **Derive the count; never remember it** above, and the budget table below is applied to it before anything is pushed. The table itself is unchanged: an arbitration or a stop it calls for holds the push exactly as it would have without the outage. The reconnect steps are in `references/recovery.md`, **Offline work on a phase in review**. The row's `offline` key governs this as it governs §3.

#### Stop when the rounds stop converging

**Count the review rounds on this change request.** At `stuck.max_review_rounds` (default `3`, `null` to disable), or sooner where the [repo's own rules](#the-repos-own-stop-rules) call for a stop, step back and arbitrate. When the arbiter's extra rounds run out, stop for a person.

**Count reviewed heads, not reviews.** A round is one head commit that a required reviewer evaluated, so the count is the number of distinct shas on this change request for which **any** `review.required` entry is satisfied by gate 6's own test: a review or inline comment at that sha by one of its `logins`, a check run named by its `check` at that sha passing the entry's `proof`, a review marker naming that sha for a `marker` entry, or a 👍 that belongs to that head. A review-state record never counts here, even where it is proof for gate 6: the forge reference says why.

**A reaction belongs to exactly one head.** It carries no sha, so bound it: a 👍 belongs to the head that was current when it was created, at or after that head's push and before the next head's push. Gate 6 asks only about the current head, where "at or after this head was pushed" is the whole test. Counting heads asks about all of them, and the same clause unbounded makes one reaction on the third head satisfy the first two as well, producing a count of three from a single 👍 and stopping the phase before one finding has been answered.

**A marker needs none of that bounding.** A review marker carries the full sha it reviewed, so it counts for that sha and no other, the same as a review does. Two markers for one sha are one round, like two reviews of it. For a `marker` entry the marker is the only thing that counts: a review, inline comment or 👍 from the accounts in its `logins` does not make a head reviewed, by the same rule as gate 6.

Counting submissions instead breaks in both directions. Three required reviewers all reviewing the opening head would exhaust a budget of three before the driver had answered anything once, though answering all three costs a single push and is plainly one round. And a `check:` entry posts no review at all, so a submission count sits at zero forever for managed Claude review and for review workflows, and the stop never fires for the setups most able to loop.

**Derive the count; never remember it.** Read it from the change request on the wake you are in. A session that keeps the tally in its head loses it to compaction and then sees round one again, which is how a change request reaches twenty-eight rounds with nobody able to say it had.

`stuck.max_cycles` does not cover this. That one counts a gate failing with an **unmoved head**, and a review round moves the head every time by construction, so this loop reads as progress on every pass.

**The budget.** Subtract this phase's baseline in `Review-baselines`, if it has one, from the derived count, and call the result the effective count. An arbitration is **in this budget** when this phase has an entry in `Arbitrations` whose count is above its baseline, or above zero where it has no baseline, so a `continue` from a person starts a budget that gets its own arbitration. Then, first match wins:

| Situation | Do this |
|---|---|
| `review.required` is empty, a [stop rule of the repo's own](#the-repos-own-stop-rules) fires, and no person has answered on the change request since your report on this head | **Do not push.** Report once and wait for an answer, as [below](#the-repos-own-stop-rules) |
| No arbitration in this budget, effective count below `max_review_rounds`, and no repo stop rule [counts](#the-repos-own-stop-rules) on this head | Answer the review as above |
| `stuck.arbiter: null`, and the effective count is at or past `max_review_rounds` or a repo stop rule counts | [Stop for a person](#stop-for-a-person) |
| No arbitration in this budget, and the effective count is at or past `max_review_rounds` or a repo stop rule counts | **Do not push.** [Arbitrate](#arbitrate) |
| Arbitrated at count *A*, derived count at or past *A* + `extra_rounds`, or a repo rule fires that sends a loop after the arbiter to a person | [Stop for a person](#stop-for-a-person) |
| Arbitrated at count *A*, derived count below *A* + `extra_rounds` | Answer the review [under the verdict](#after-the-verdict) |

**A person's `arbitrate` is the other way an arbitration enters a budget**, as `references/vocabulary.md` defines it: at a stop it starts a new budget with an arbitration at once, and before the threshold it is an early one in this budget. Either way it takes the same last two rows.

**An arbitration in this budget always takes the last two rows**, whatever the effective count. One can now happen before `max_review_rounds`, when a repo's rule fires early, and the heads after it are answered under its verdict and stop at its count plus `extra_rounds`, not at the threshold.

**"At or past", never "at".** Missed webhooks, a session that was down for a while, or a change request that was already over the threshold before this rule existed can all arrive with the count beyond a boundary, and a test for equality lets that phase walk past the backstop.

**`extra_rounds` counts the same way `max_review_rounds` does**, in reviewed heads, measured from the arbitration's own count rather than from the threshold, so an arbitration that happened late still gets its full allowance. With the defaults: the arbitration answers head 3, heads 4 and 5 are answered under the verdict, and head 6 stops, unanswered, exactly as head 3 would have without an arbiter.

**This runs whether YOLO is on or off.** YOLO decides who presses merge. Nothing about a person merging means they should be the one to sort a review loop's nits from its bugs, and a phase that gets to its merge gate without them is the point of both modes.

#### The repo's own stop rules

A repo may say for itself when a review loop should stop, in its `CLAUDE.md`, `AGENTS.md` or contributing guide: a cap on fix rounds, or a rule like "when a round's findings are mostly follow-ups on the previous round's fixes, stop pushing and escalate." Those rules bind the phase like anything else the repo says. Most were written before the repo had an arbiter, so the "escalate" in them means a person, and read literally they skip the arbiter this plan configured. Read them this way instead.

**The arbiter is the escalation.** A repo rule that says to stop and escalate a review loop is answered by arbitrating, not by stopping for a person. Where it fires before `max_review_rounds`, as a follow-ups rule can on head 2, arbitrate on that head: record `<phase id>:<derived count>` in `Arbitrations` exactly as at the threshold, and the stop for a person then comes at that count plus `extra_rounds`, like any arbitration. **A repo rule counts only from an effective count of 1.** That keeps the `Arbitrations` entry it records above the baseline, which is what puts an arbitration in this budget; one recorded at the baseline is outside it, and the next wake would arbitrate again. At an effective count of 0 there is no reviewed head in this budget for an arbitration's stop to count from, and there are two ways to get there. Just after a `continue`, the head the person answered is the one the rule fired on, so answer the review and let the rule count again from the next reviewed head. With `review.required: []` no head is ever counted, so neither an arbitration's stop nor a `continue` baseline can work: an arbitration could never reach *A* + `extra_rounds`, and a baseline of 0 would block the row again on the next wake. So don't arbitrate and don't mark the row `Blocked`. Post the stop report once for that head, and push nothing until a person answers. That is a question this skill tells you to ask, so it waits on a person. **Their answer on the change request, dated after your report, clears this head's stop**, and it is durable where a count is not: act on what it says, and don't stop again on the same head. An answer given in the session instead goes on the change request as a comment quoting it before you act, so the next wake finds it.

Go straight to a person only when `stuck.arbiter` is `null`, or when the repo's rule itself says the arbiter does not stand in for the person it names. Once the arbiter has run in this budget, a repo rule that fires again and says it goes to a person after the arbiter is followed: [stop for a person](#stop-for-a-person) then, even short of `extra_rounds`.

**A tighter budget wins.** A repo that caps fix rounds below what this plan allows ends the loop where its cap runs out, counted the repo's way. With an arbiter the plan allows `max_review_rounds + extra_rounds - 1` fix pushes: the ones before the arbitration, the arbitration's own, and the ones answered under the verdict. Without one it allows `max_review_rounds - 1`. When the repo's cap runs out first, do what the repo says happens then, such as filing what is left and merging; where it says nothing, [stop for a person](#stop-for-a-person). The planner should have matched the plan to the cap. When it didn't, say so once on the change request.

**Name both when you stop or arbitrate.** The comment says which repo rule fired, if any, and where this plan's arbiter stands: not run yet, ran at count *A*, or not configured. A stop report that cites a repo rule and says nothing about the arbiter is how the arbiter gets skipped without anyone seeing it.

Observed: a repo's `CLAUDE.md` said a round of follow-ups on the previous round's fixes meant "stop pushing and escalate" to its owner, "whatever the round count." On head 3, the plan's threshold, with a Fable arbiter configured there, a round-3 finding followed up a round-2 fix. The driver took the repo's sentence at its word: it marked the row `Blocked`, posted a stop report citing the rule, and asked for `continue`. The arbiter never ran, and nine dependent phases waited until the user asked why.

#### Arbitrate

At the threshold the driver is the wrong one to judge the loop. It wrote every fix the reviewer has been finding fault with, and it comes to each round focused on the newest comment. So the judgement goes to an **arbiter**: a subagent with a fresh context, on `stuck.arbiter.model` (default `fable`). The fresh context matters more than the model. It hasn't written any of the fixes, so it has nothing to defend.

1. **Record it first.** Append `<phase id>:<derived count>` to `Arbitrations` in Driver State, as a plan write like any other. That is golden rule 2, and it is what stops a session that dies mid-arbitration from starting a second one. **For a person's `arbitrate` at a stop**, the same write also sets `Review-baselines` to `<phase id>:<count - 1>` and the row back to `In Review`, as `references/vocabulary.md` says: one write, so no session can clear the stop without recording the arbitration.
2. **Start the arbiter and wait for its answer.** Don't push while it runs. Run it in the foreground (the Agent tool's `run_in_background: false`), so the verdict comes back inside this turn. If it does run in the background, its completion notification is your wake: act on the verdict then, without asking anyone. Brief it with facts, not conclusions:
   - **a fresh export of the plan**, not a path to it, and the phase id, for its Phase Details (scope, acceptance criteria, risks) and Carried findings. Read the plan from the plan branch as the forge reference's **Write the plan** says, write that text to a file outside the repo's working tree, such as the session's scratch or temp directory, and give the arbiter that file with this sentence: *this is the plan branch's current content; any copy of the plan in the checkout may be stale and is not to be read.* Observed: an arbiter given a path read a stale, untracked copy in the checkout and reported a Carried findings entry missing that the plan branch held. A file inside the working tree can also be committed by accident
   - the repo, change request number, base branch, head sha, and the path of the local checkout, so it can read the whole diff against base rather than the latest commit
   - every review finding on the change request from every round, resolved or not, with links
   - what you changed in each round, one line per commit
   - the local review pass's disclosures, where the repo sets `review.local`: what each pass found, and what was fixed, declined or held, as local findings rather than a reviewer's
   - the repo's own review rules, if it has any, by path and quoted: a severity bar, a threat model or a budget the repo set binds the verdict as much as the limits below
   - where a person said `arbitrate`, that a person asked for this arbitration, and at a stop that the previous budget ran out at this head. A fact, not an opinion about the findings

   **Do not tell it which findings you think are wrong or minor.** It is there to disagree with you, and an arbiter handed your opinion tends to give it back.
3. **What it returns.** Findings grouped by the mistake underneath them, and for each group: the mistake in one line, a verdict, and the reasoning. For `rework` and `fix`, where in the diff the general fix goes. Then an overall call, one of *converging*, *needs rework*, or *ready*, and **the bar**: a sentence or two on what still counts as worth a round on this phase.

   | Verdict | Meaning | You |
   |---|---|---|
   | `rework` | The same mistake resurfacing, round after round, in new places | Fix it across the whole diff, as the arbiter describes it, not where the comments point |
   | `fix` | Real, in scope, and separate from the rest | Fix it, generally |
   | `carry` | Belongs to this plan, not this phase | Carried findings |
   | `issue` | A real defect unrelated to what the plan delivers | An issue on the forge |
   | `accept` | Real, and not worth a round | Reply with the arbiter's reasoning and resolve a bot's thread |
   | `reject` | The finding is wrong | Reply with the arbiter's reasoning and resolve a bot's thread |

4. **Its limits.** Say these in the brief. It may not `accept` an in-scope defect in correctness, security, or data: those are `fix` or `rework`. It may `reject` only with the checkable reasoning [a disagreement needs](#answering-a-review). It never widens the phase or adds one; out of scope is `carry` or `issue`. On a thread a person opened, an `accept` or `reject` goes in as a reply and the thread stays open, [as anywhere else](#answering-a-review).
5. **Post the verdict before you act on it.** One comment on the change request whose first line is `<!-- phase-driver:arbiter <phase id>:<count> -->`, with the same entry you recorded in step 1, then the overall call, the bar, and each group with its verdict and reasoning. Say whether it came from a separate subagent, and, where a person said `arbitrate`, that a person asked for it. Under YOLO the phase can merge without anyone having read the change request, and this comment is how someone reading it afterwards finds out why threads were resolved without a fix.
6. **Act on it in one push**, by the table, in the turn the verdict lands. Resolve each bot's thread with its reply, and each person's thread only where you fixed or carried what it raised, telling them apart by [Whose note it is](references/gates.md#whose-note-it-is). Where you are sure a verdict lets through something broken, fix it anyway and say so in the reply: the limits run one way, so you can do more than it asks about a defect, never less.

**An arbitration is not a stop.** It is what happens instead of the stop at `max_review_rounds`, and instead of the stop a [repo's own rule](#the-repos-own-stop-rules) asks for. The row stays `In Review`, nothing is written to `Review-baselines` (except by a person's `arbitrate` at a stop, which starts a new budget), and you go from the verdict to the push without anyone's say-so. If a required reviewer is still reviewing the current head when the verdict lands (a 👀 from it, or its check run in progress), you may hold the push so its findings join the same one, since that saves a round. That hold is a wait like any in §4: end the turn saying what you are waiting on, let its result or your check-in wake you, and push then. The first point at which a person is needed is [Stop for a person](#stop-for-a-person), at the arbitration's count plus `extra_rounds`.

**Without a subagent**, as in a claude.ai skill upload, do the pass yourself against the same brief, starting from the diff and the findings rather than from your own replies, and reading the plan from that fresh export rather than from the checkout, and say in the comment that the arbitration was not independent. A model the session can't use falls back to the session's model, the same as a skill's `model`.

**An `Arbitrations` entry in this budget with no verdict comment carrying that same entry in its marker** means a session died between recording the arbitration and posting it. Run the arbiter again; don't record it twice. A verdict from an earlier budget doesn't count: its marker names a different entry.

#### After the verdict

The verdict covers the rest of the budget, up to the stop at the arbitration's count plus `stuck.arbiter.extra_rounds` (default `3`). On each round until then, **read the verdict comment from the change request**, the one whose marker names this budget's `Arbitrations` entry, rather than remembering it. Judge new findings against it:

- **Below the bar**, accept it, with a reply saying so and linking the verdict. The bar never covers an in-scope defect in correctness, security, or data, the same limit the arbiter works under: fix those whatever the bar says.
- **In a group the arbiter called `rework`**, the rework missed a place. Fix that mistake everywhere again, not just where it was found.
- **Anything else**, answer it as [above](#answering-a-review).

The arbiter runs once per budget. A second loop inside the same budget is the evidence a person needs, and the stop below hands it to them. A person's `arbitrate` at that stop is how a new budget and its arbitration begin.

#### Stop for a person

**Do not push again.** Mark the row `Blocked`, record the round count in `Note`, and post one comment on the change request containing:

1. What you changed in each round so far, one line each.
2. What is still flagged on the current head.
3. **Whether the newest findings are new ground or the same class resurfacing in new places.**
4. If the arbiter ran, a link to its verdict and what changed after it.

Line 3 is the one that earns the stop. "Round four, and the last three findings are the same retry-logic issue in three more files" says the phase needs reworking rather than another patch. "Round four, three unrelated real bugs" says carry on. Same count, opposite answers, and only the report tells them apart. Line 4 says whether stepping back helped: a loop that kept going after an arbiter called for rework is a phase that needs replanning, not more rounds.

**Do not ask "shall I continue?"** A bare question gets a yes, because nothing in it gives anyone grounds to say no. That is the observed failure: a stop at four rounds was approved and ran twenty-eight more. Report the evidence and let the answer follow from it.

The user resumes with `continue`. Starting the budget again means **writing down where it restarted**: add this phase's current reviewed-head count to `Review-baselines` in Driver State, as `<phase id>:<count>`, and subtract that phase's baseline from every later count. The new budget gets its own arbitration at its own threshold.

Where an arbiter is configured, the user can resume with `arbitrate` instead: a new budget that arbitrates at once rather than at its threshold, with the baseline one below the current count so that the arbitration belongs to it. `references/vocabulary.md` has the rule. The stop report does not offer either word as a question; it gives the evidence, and the person chooses.

Without the baseline the stop is a trap rather than a checkpoint. The count is derived, so the next wake re-derives a number still at or above the threshold, blocks the row again, and no amount of saying `continue` moves it. The baseline is the one piece of this that has to be written down, for the same reason everything else in the plan file is: the session that agreed to continue will not be the session that carries on.

**It is keyed by phase, and it is not the `Note`.** Phases run concurrently across repos, so two rows can be stopped at once, and an unqualified baseline would be overwritten by whichever row was continued last, then subtracted from the wrong phase. `Note` is one plan-wide free-text field and cannot hold per-phase state that anything reads back. `Review-baselines` and `Arbitrations` sit beside `UAT-pending`, which is per-phase runtime state for the same reason.

When a change request has no outstanding work, evaluate `references/gates.md` against it, using that repo's resolved config. Then:

- **YOLO on.** Not for a milestone PR, which is never yours to merge; see [Milestones](#milestones). Re-read the head SHA as your *last* read before merging, with no other calls in between, and merge with that repo's `merge.method`, as the forge reference's **Merge** says. Then **delete the phase branch**, unless the repo sets `merge.delete_branch: false`. Why the driver does this itself, and what to do when a delete is refused, is in the forge reference's **Delete the branch**.
- **YOLO off.** Do not merge. Tell the user it's ready, with the change request's link and a per-gate summary, and set the row's `Note` to `ready to merge`. Re-ping only if the head moves and it passes again. Don't nag on a timer.

Delete only a branch **you** created: it must match that repo's `branch_prefix`, and it must not be the plan branch, any repo's `target_branch`, or any repo's release branch. Those four checks are the whole guard, and skipping them is how a driver deletes the branch its own plan lives on. The guard has one exception, and only one: the [re-sync](#re-sync) of a milestone row's own branch, after that row's change request is confirmed merged, and never when that branch is the plan branch.

`YOLO` lives in the Driver State block. A repo may also pin `yolo: false` in front matter, which wins, config can restrict, never enable.

**If a gate fails for the same reason on consecutive wakes with an unmoved head**, count it. At `stuck.max_cycles` (default 5), mark that row `Blocked` with the reason and tell the user. Count per row: one stuck platform must not stall the others.

The unmoved head is what this rule turns on, so it says nothing about a phase that is moving and getting nowhere. `stuck.max_review_rounds` in §5 covers that case.

## 7. After a merge

However the change request merged. You, the user from their phone, or anyone else:

1. Stop watching that change request, as [references/watching.md](references/watching.md) says.
2. **Commit `Merged`** to the plan branch. If YOLO was on and the change request carried no UAT checklist, append that phase's id to `UAT-pending` in the same write. Then [tidy the local clone](#tidy-the-local-clone) for that phase's branch.
3. Comment on the change request and tell the user.
4. **Start whatever rows that unblocks**, in the same turn, unless `Driver: paused`.
5. **If that was the last row**, meaning every row is now `Merged` or `Skipped`, go to §8, in this same turn.

A merge always advances the plan. YOLO changes who presses the button, never whether the plan moves.

**When the merged change request is a milestone row's**, the steps run in this order instead: commit `Merged`; [re-sync](#re-sync) the target branch; run that repo's `milestone.after_merge`, if set, and then post its marker comment on the milestone PR (see [Settled](#settled)); tell the user, including anything `after_merge` produced; then start whatever it unblocks, and go to §8 if it was the last row. Re-sync comes before anything starts, because a phase branched from a target branch that is still the pre-merge one, or gone, starts from the wrong base.

Step 5 is the one that gets skipped, so it is worth saying why it exists. Every other transition here is chained: §5 sends a merge to §7, and step 4 sends an unblocked row back to §3. The last merge is the one where step 4 finds nothing to start and the list simply ends, which feels like a completed turn because the previous merges ended the same way. It is not one. Finishing is a transition like any other, and §8 is unreachable from here unless you take it.

### Tidy the local clone

**After a phase's change request merges, however it merged, remove that phase's branch from your own clone of the repo.** The forge removes the remote branch: GitLab at merge, GitHub by the delete in §5. Nothing removes the local one. A clone driven through a whole plan otherwise ends with one stale branch per phase, and `git branch` stops being a list of the work still in flight.

In that repo's clone, in this order:

1. `git fetch --prune origin`, so the remote-tracking refs of branches the forge deleted go too.
2. If the phase branch is checked out, `git switch --detach origin/<target_branch>`. Detached, so that no local copy of the target branch is created or relied on; §3 branches from the remote-tracking ref.
3. `git branch -D <branch>`. Capital `-D`, because a squash or rebase merge leaves the branch's own commits off the target branch, and `-d` refuses a branch that has in fact landed.
4. `git update-ref -d refs/phase-driver/pushed/<branch>`, where it exists. It is the record of what the driver pushed during a reconnect, as `references/recovery.md` says, and it means nothing once the phase has merged.

**The guard is the one every delete has**, checked before step 2: the branch matches that repo's `branch_prefix`, is not the plan branch, and is not any repo's `target_branch` or release branch. **A branch whose name ends `-orphaned` is never tidied**, here or by Reconcile: it holds work set aside when a claim was lost or a phase was reset, as `references/recovery.md` says, and a person decides what happens to it. Name any that exist in the clone once per session, in your status report, so they are not forgotten. A milestone row's branch is a `target_branch`, so this never touches it; its [re-sync](#re-sync) is a separate step. **Also leave the branch, and say so once, when the working tree has uncommitted changes, or when the branch's tip is not the change request's final head sha** as the forge reports it. Compare the sha, not the history: after a squash or rebase merge, and once the prune has removed the remote branch, the branch's commits are on no remote ref even when every one of them landed. Anything past that sha, or uncommitted, was not part of what merged, so it is either leftovers or someone's work in progress, and neither is yours to throw away.

This is your clone only, never a person's checkout or a runner's build directory, which is why `merge.delete_branch` does not govern it: that key is about the branch on the forge. **A failure here is not a failure of the merge.** Say so once and carry on; nothing downstream depends on the local branch being gone.

## Milestones

A milestone row ships a repo's `target_branch` to its [release branch](#1-find-the-plan) at a point the plan names. It is the integration PR of §8, moved to where a later phase needs the work released, and it keeps that change request's one rule: **the driver opens it and never merges it.**

**Recognise it by both signs together:** an `M<n>` id, and a `Branch` equal to the repo's resolved `target_branch`. A row carrying one sign without the other, an `M` id on a `claude/` branch or a phase id on the target branch, is a plan error. Mark it `Blocked`, say which sign is missing, and leave it for a person. A row that is a milestone where the target branch *is* the release branch is the same error: there is nothing to ship.

### Opening a milestone PR

When a milestone row is startable, in order:

1. **Commit `In Progress`** to the plan branch. The claim, as for a phase.
2. **Prepare.** If the repo sets `milestone.prepare`, follow it on the target branch and push the result as commits straight to that branch. Where the branch refuses direct pushes, put them through one small change request into it under the ordinary gate, and merge it by the ordinary YOLO rule. If preparation fails, or its own checks do not pass, do not open the change request: mark the row `Blocked` with what failed.
3. **Open the change request** from the target branch to the release branch, titled `Milestone M1: <scope>`, the way the forge reference's **Milestone and integration change requests** says, and for the same reason as a phase PR. The body carries: what ships, phase by phase, each with its change request's link; anything the shipped phases recorded as out of scope, and open Carried findings that name them; the assembled UAT script for every id in `UAT-pending` that this milestone ships plus the milestone's own **UAT**, by the rules in §3; and a line saying **a person merges this change request, not the driver.** Clear those ids from `UAT-pending` in the next write. No [local review pass](#the-local-review-pass) runs before this push or before the preparation's: the phases it ships were each reviewed on their own change requests.
4. **Commit `In Review`** and the `Link`, at once, before any wait.

**An explicit milestone row opens its change request with YOLO on or off.** It is a checkpoint the plan's author put in the table, and later phases wait on it. YOLO decides who merges phase PRs and nothing else.

**Never merge it**, in any YOLO state. `merge` and `merge now` do not apply to it; answer that it is the person's to merge.

### Which PR is a milestone's

Every milestone row in a repo has the same head and base, so head and base alone do not say which milestone a change request belongs to. A change request is this row's when:

- it is the change request in the row's `Link`, where the row has one. The link is authoritative; or
- with no link, its head is the target branch, its base is the release branch, and **its title starts `Milestone <id>:`** with this row's id. The title is set in step 3 and is the one identifier that survives a crash before step 4.

A change request that matches head and base but names another id is that other row's, never this one's. Adopt an open change request only for a row whose dependencies are all `Merged` or `Skipped`: a change request found for a row that is not yet startable is a mismatch to report, not one to adopt. Since a repo has at most one open milestone PR, two rows claiming one PR always means one of them is wrong.

### Working a milestone PR

Between opening and the person's merge, a milestone PR is handled like any change request you opened, by the rules already in §5 and `references/gates.md`, none of them restated here: a failed check is read and fixed, a review is answered under [Answering a review](#answering-a-review) with its outcomes for in scope and right, minor, wrong and out of scope and its treatment of a person's thread, and `stuck.max_cycles`, `stuck.max_review_rounds`, the arbiter and the repo's own stop rules all apply. Four things are particular to it:

- **Scope.** "In scope" means the union of the scopes of the phases the milestone ships, read from their Phase Details, **plus what `milestone.prepare` asked for**. The preparation is your own work on this change request, so a wrong version or a bad changelog line is yours to fix, not to carry. Work none of those covers is out of scope, and goes to Carried findings or an issue as it would on a phase.
- **Where a fix goes.** A commit pushed straight to the target branch, which is the change request's head, the same as the preparation. No fix change request into the feature branch, unless that branch refuses direct pushes. Where the repo sets `review.local`, [the local review pass](#the-local-review-pass) runs once before each fix push with `{base}` at the milestone PR's head before the fix, so it reviews the fix alone, and its disclosure is one stamped comment after the push, as on a phase.
- **The head moving.** Every fix commit moves the head, so the gate result is discarded and re-evaluated against the new head, and gate 6 needs the reviewer at that head, exactly as on a phase PR. Rounds are counted the same way, as reviewed heads, starting from the head the change request opened at, so the preparation's commits are not rounds. `Review-baselines` and `Arbitrations` take the milestone's id, as in `M1:3`, a person's `arbitrate` included. The arbiter's brief names every shipped phase's details.
- **When the gates pass.** Tell the person it is ready, with the per-gate summary, and set the row's `Note` to `ready to merge`, as for a phase with YOLO off. Include the warning about skip instructions in its commits, where the forge reference's **Milestone and integration change requests** says to. Then wait. A row that reaches a stop goes `Blocked` like any other.

The implicit final milestone, §8's integration PR, is not worked this way. §8's rule for it stands.

### Re-sync

After a milestone PR is confirmed merged, bring its target branch back in line with the release branch, by these rules and no others. Read both heads with `git ls-remote`, never from remote-tracking refs.

- **No non-terminal row still targets the branch.** Skip the re-sync. Nothing needs it.
- **The branch is gone**, as when the repo deletes head branches on merge. Re-create it at the release branch's head, with a lease that requires it still to be absent.
- **It exists, and its head is an ancestor of the release branch**, as after a merge commit. Fast-forward it to the release branch's head, with a plain push, never a forced one.
- **It exists, is not an ancestor, and its head is exactly the head the milestone PR was merged at**, as after a squash or rebase merge. Move it to the release branch's head, with a lease on that merged head. Nothing is lost: everything on it reached the release branch in that merge.
- **It holds commits beyond the merged head.** Change nothing. Report it, and start nothing in that repo until a person has sorted it out.

**Every move is conditional on the head you just checked.** Someone can push to the branch between your read and your write, and an unconditional force would delete their commits, which is the one outcome the last case exists to prevent. So the push itself carries the check: the forge reference's **Re-sync a branch** gives the push for each case.

A push rejected by its lease or as a non-fast-forward means the branch moved under you. Re-read both heads and apply the rules again from the top; you will usually land in the last case.

Any doubt is the last case. Moving a branch is the only force the driver applies to a ref it did not create, so it refuses on anything it cannot prove is safe. A refused update (protection, a ruleset, a sandbox that will not move refs) is reported once, with the matching command from the forge reference, filled in, and nothing in that repo starts until the branch is where it should be. Never hand anyone a bare `--force`. Never re-sync the plan branch: a plan with milestone rows does not live on a branch they ship.

### Settled

A `Merged` milestone row is **settled** when its post-merge work is done, and a row that depends on it starts only then. Two things, each read from the forge and neither from memory:

1. **The branch is re-synced**, or no non-terminal row still targets it. Re-synced means the branch exists and the milestone PR's merge commit is an ancestor of its head. That holds after every successful re-sync case, and keeps holding as later phases land on top.
2. **`after_merge` ran**, where the repo sets it: the milestone PR carries a comment whose first line is `<!-- phase-driver:after-merge <id> -->`. Post it right after `after_merge` finishes, saying what it did. A session that died after the `Merged` write and before this comment runs `after_merge` again on the next wake, so write it to be safe to repeat, as updating an installed copy is.

Reconcile checks every `Merged` milestone row that is not settled, finishes whichever of the two is missing, in that order, and only then lets anything in that repo start.

## 8. Finishing the plan

When every row is `Merged` or `Skipped`, in this order: **open the integration PR if YOLO is on**, in each repo whose `integration_pr` is not `false`, then set `Driver: idle`, clear `Active`, post a summary of what shipped, and stop.

**This section governs a plan with no milestone rows, and its integration PR is the implicit final milestone.** A plan that has milestone rows shipped through them: no integration PR is opened, and finishing is `Driver: idle`, the summary, and the readout of Carried findings and any `UAT-pending` below.

**The summary names every open entry in Carried findings**, alongside outstanding UAT. Those are the things a reviewer raised that no phase did, and the end of the plan is the last moment anyone is looking. A plan that completes with a list nobody read is the same failure as UAT that reaches no one.

**Two actions here, and only one of them is withheld.** *Opening* the integration PR is yours and needs no permission: YOLO means nobody was watching, and this change request is the entire handoff. *Merging* it is never yours. Read "never merge it" below as the second of those, not as the change request being off-limits.

**Everything in this section is YOLO-only.** With YOLO off the developer merged every phase themselves and read every checklist as they went. They know exactly where the branch stands, and opening a change request to their release branch on their behalf presumes a decision they are already positioned to make. The handoff exists because YOLO means nobody was watching.

### The integration PR

Phases usually target a feature branch rather than the default one, so that nothing reaches `main` until the feature is whole. When the last phase merges, that branch is finished and nobody has been asked to look at it as a whole. Every review so far was of one phase against its siblings.

So, with YOLO on: **for each repo whose `target_branch` is not its release branch, which merged at least one phase, and whose resolved `integration_pr` is not `false`, open a change request from `target_branch` to that repo's release branch.** Title it `<project>: <n> phases`. Body: what shipped, phase by phase with links; anything the plan recorded as deliberately out of scope; and any setup the feature needs that no change request could contain.

**`integration_pr: false` means no implicit final milestone in that repo.** The plan's author has said how the feature branch reaches the release branch, and it is not through a change request the driver opens. So open nothing from that repo's `target_branch`, and do not treat the plan as unfinished for it. The key has no effect on explicit milestone rows: an author who wrote one wants it opened, and [Milestones](#milestones) opens it. Where no integration PR is opened because of this key, the cumulative UAT script that PR would have carried goes to [the fallback](#the-fallback).

**Never merge it. YOLO opens this change request and does not merge it**, and that is not an inconsistency. YOLO is a judgement about *phase* change requests. Work the plan produced, scoped by the plan, verified by the driver, gated per phase. This one is the whole feature landing on the branch everything else builds on, and none of that reasoning reaches it. Open it, report it, go idle.

**A plan that calls this "the only human merge gate" is describing the merge.** Plans say that, in those words or close to them, because it is true and worth writing down. It is not an instruction to wait for permission before opening: the gate cannot gate anything until the change request exists, and a driver that reads it that way ends the plan by telling the user about a change request that isn't there. Front matter configures you; the plan's prose describes the work. Where the two appear to disagree about *opening* this change request, this section wins.

Don't wait on its CI either. Checks that were scoped to the default branch may report here for the first time. CodeQL and mobile build services commonly are, and a first red result on a check no phase ever saw is information for the user, not a gate for you to drive to green.

**The cumulative UAT checklist goes on the integration PR**, not on the final phase's change request, whenever an integration PR will exist. With YOLO on the final phase PR is merged by the driver within minutes of opening, so a checklist placed there is written into something nobody had to read. The integration PR is the first thing on the whole plan a human must act on, which is the only place a checklist has leverage. Clear `UAT-pending` when you open it.

With more than one repo, the **home repo's** integration PR carries the entire script across all repos, and the others link to it. UAT is end-to-end by nature; splitting it by repo produces two lists that each describe half a user journey, the same reason it is not split by phase.

Where `target_branch` *is* the release branch there is no integration PR to open, and the rules stand as they were: the final phase PR carries the cumulative checklist. Same with YOLO off, where every change request carried its own UAT as it went and there is no backlog to hand over.

### The fallback

If the plan completes with `UAT-pending` non-empty and no integration PR carried the cumulative script: every repo targets its release branch, `integration_pr: false` turned it off, or the final phase was skipped or merged before you assembled the list. Assemble the cumulative script by the rules in §3, then:

- **Where the home repo's forge reference says issues are available**, open an issue there titled `UAT: <project>` with the script, as that reference's **Issue fallback** says, and clear `UAT-pending`.
- **Otherwise**, post the script as a comment on the last change request the plan merged. Leave `UAT-pending` as it is, and say in the completion summary that the script went to a comment on a merged change request, which nobody is asked to read, and that every id still in `UAT-pending` is unverified.

Never drop them; unverified work that nobody knows is unverified is the thing this exists to prevent. The comment is the weaker of the two, which is why `UAT-pending` keeps the ids: a person reading the plan later still sees what nobody has tested.

## Writing to the plan

Write to the plan branch of `home_repo` as the forge reference's **Write the plan** says, passing the write token you read at the start of the transition. Message: `chore(plan): <project> phase <N> -> <Status> [skip ci]`.

Re-read the write token at the start of **every** transition, never reuse one from an earlier transition.

On a write-token conflict: re-read, **re-run the Driver-ID decision on what you just read**, and only then re-apply your change and retry. Three failures means another driver is active, so stop and report rather than forcing it.

Re-running that decision is what makes the write token a lock rather than a speed bump. A stale token means someone else wrote between your read and your write, and the write that beat you may have been another driver claiming this plan. Re-applying your change blindly puts your own `Driver-ID` back over theirs, and now two drivers each believe they hold the claim and start the same phase. So if the re-read shows a foreign ID with a live heartbeat, you lost the race: report and stop, and do not retry.

If the plan branch rejects direct commits, switch to `plan_writes: plan-pr`. Each transition becomes a single-file change request with auto-merge, targeting the plan branch, and tell the user once that you've done so.

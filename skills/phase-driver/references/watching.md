# Watching

How a driver gets woken while it waits on a change request: CI finishing, a reviewer answering, a push, a merge. The plan holds every piece of state; this file is only about what ends a wait.

## Subscribe where you can, watch where you can't

**If the session can subscribe to change-request activity, subscribe**, exactly as the forge reference's **Watch** says, and schedule the fallback check-in below. A cloud session on GitHub does this, and nothing in this file changes it.

**If it cannot, arm the watcher.** A local session in a terminal has no webhooks, and a forge behind a VPN could not deliver them anyway. Without something to wake it, a local driver that ends its turn on a wait simply stops.

Choose by what the session can do, not by where you think it is running. There is no setting for this.

## The watcher

A polling loop the driver fills in and runs under the Monitor tool. Every 60 seconds it snapshots each open phase change request, and it prints **one line only when something changed**, naming every change request that changed in that poll. A poll where nothing changed prints nothing.

What counts as a change, per change request:

- the head sha
- the state or conclusion of any check on the head
- a new comment, review or review-thread comment from anyone, except a note that is the driver's by [Whose note it is](gates.md#whose-note-it-is): written by the account the driver acts as **and** carrying the driver stamp, `<!-- phases:driver v=1 -->`, on a line of its own
- a new reaction from anyone other than the account the driver acts as. A reaction has no body to stamp, so reactions keep the account filter
- merged or closed

Reactions are on the list because some reviewers answer with nothing else: a 👍 from a reviewer on smart detect delivers no event, and it is often the whole answer.

**Use the template as written. Replace only the bracketed values.** A loop improvised on each wake is where a silent failure would hide: one that exits on its first failed request, or compares the wrong field, looks exactly like a quiet change request. The GitHub one was run against a real PR before it was written down, it tolerates a failed request without exiting, and it needs nothing but `gh`, `jq` (which `gh` carries for `--jq`) and the bash 3.2 that macOS ships.

### GitHub

```bash
PLAN='[plan path, e.g. docs/plans/acme.md]'
PRS='[open phase PRs, space separated, e.g. acme/web#42 acme/api#7]'
CHECKIN_MIN=[minutes to the fallback check-in: 45 to 60, or 10 to 15]
ONCE=[0 under Monitor; 1 for a background command that exits on its first line]

key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; printf '_'; printf '%s' "$1" | cksum | cut -d ' ' -f 1; }
D="${TMPDIR:-/tmp}/phase-driver-watch/$(key "$PLAN")"
mkdir -p "$D" || exit 1
WAKE="[phase-driver watcher] Invoke the phase-driver skill, then reconcile $PLAN."
say() { printf '%s %s\n' "$WAKE" "$1"; if [ "$ONCE" = 1 ]; then exit 0; fi; }
now() { date +%s; }

due=$(( $(now) + CHECKIN_MIN * 60 ))
old=$(cat "$D/checkin" 2>/dev/null)
case "$old" in ''|*[!0-9]*) old=$due ;; esac
[ "$old" -lt "$due" ] && due=$old
echo "$due" > "$D/checkin"

ME=''
WAIT=60
while :; do
  lines=''; up=0
  if me=$(gh api user --jq '.login | ascii_downcase' 2>"$D/err") && [ -n "$me" ]; then
    up=1; ME=$me
    if [ -f "$D/host.down" ]; then
      rm -f "${D:?}/host.down"
      lines="$lines github.com: the forge is answering again."
      echo $(( $(now) + CHECKIN_MIN * 60 )) > "$D/checkin"
    fi
  else
    if grep -q 'HTTP 40[134]' "$D/err" && ! grep -qi 'rate limit' "$D/err"; then
      kind=refused; msg="github.com: the forge refused access ($(grep -o 'HTTP 40[134]' "$D/err" | head -n 1))."
    else
      kind=unreachable; msg="github.com: the forge is unreachable ($(tr '\n' ' ' < "$D/err" | cut -c 1-100)); still polling, backing off to at most five minutes."
    fi
    if [ "$(cat "$D/host.down" 2>/dev/null)" != "$kind" ]; then echo "$kind" > "$D/host.down"; lines="$lines $msg"; fi
  fi
  [ "$up" = 1 ] && for pr in $PRS; do
    R=${pr%%#*}; N=${pr##*#}; K=$(key "$pr"); new="$D/$K.new"
    if [ -n "$ME" ] && {
      gh api "repos/$R/pulls/$N" --jq '"state \(.state) merged=\(.merged)", "head \(.head.sha)"' > "$new" &&
      sha=$(sed -n 's/^head //p' "$new") &&
      gh api --paginate "repos/$R/commits/$sha/check-runs?per_page=100" --jq '.check_runs[] | "check \(.name)=\(.conclusion // .status)"' >> "$new" &&
      gh api --paginate "repos/$R/commits/$sha/status?per_page=100" --jq '.statuses[] | "check \(.context)=\(.state)"' >> "$new" &&
      gh api --paginate "repos/$R/issues/$N/comments?per_page=100" --jq ".[] | select(((.user.login | ascii_downcase) == \"$ME\" and ((.body // \"\") | split(\"\\n\") | map(rtrimstr(\"\\r\")) | any(. == \"<!-- phases:driver v=1 -->\"))) | not) | \"item comment:\(.id)\"" >> "$new" &&
      gh api --paginate "repos/$R/pulls/$N/comments?per_page=100" --jq ".[] | select(((.user.login | ascii_downcase) == \"$ME\" and ((.body // \"\") | split(\"\\n\") | map(rtrimstr(\"\\r\")) | any(. == \"<!-- phases:driver v=1 -->\"))) | not) | \"item thread comment:\(.id)\"" >> "$new" &&
      gh api --paginate "repos/$R/pulls/$N/reviews?per_page=100" --jq ".[] | select(((.user.login | ascii_downcase) == \"$ME\" and ((.body // \"\") | split(\"\\n\") | map(rtrimstr(\"\\r\")) | any(. == \"<!-- phases:driver v=1 -->\"))) or ((.user.login | ascii_downcase) == \"$ME\" and (.body // \"\") == \"\") | not) | \"item review:\(.id)\"" >> "$new" &&
      gh api --paginate "repos/$R/issues/$N/reactions?per_page=100" --jq ".[] | select((.user.login | ascii_downcase) != \"$ME\") | \"item reaction \(.content):\(.id)\"" >> "$new"
    } 2>"$D/err"; then
      up=1
      if [ -f "$D/$K.down" ]; then rm -f "${D:?}/${K:?}.down"; lines="$lines $pr: the forge is answering again."; fi
      LC_ALL=C sort -o "$new" "$new"
      if [ -f "$D/$K.old" ] && ! cmp -s "$D/$K.old" "$new"; then
        what=''
        a=$(sed -n 's/^state //p' "$D/$K.old"); b=$(sed -n 's/^state //p' "$new")
        [ "$a" != "$b" ] && what="$what; now $b"
        a=$(sed -n 's/^head //p' "$D/$K.old")
        [ "$a" != "$sha" ] && what="$what; head moved ${a%"${a#???????}"} -> ${sha%"${sha#???????}"}"
        c=$(LC_ALL=C comm -13 "$D/$K.old" "$new" | sed -n 's/^check //p' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
        [ -n "$c" ] && what="$what; checks: $c"
        i=$(LC_ALL=C comm -13 "$D/$K.old" "$new" | sed -n 's/^item \(.*\):.*/\1/p' | sort | uniq -c | sed 's/^ *\([0-9]*\) \(.*\)/\1 new \2/' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
        [ -n "$i" ] && what="$what; $i"
        [ -n "$what" ] && lines="$lines $pr:${what#;}."
      fi
      mv "$new" "$D/$K.old"
    elif [ ! -f "$D/$K.down" ]; then
      : > "$D/$K.down"
      if grep -q 'HTTP 40[134]' "$D/err" && ! grep -qi 'rate limit' "$D/err"; then
        lines="$lines $pr: the forge refused access ($(grep -o 'HTTP 40[134]' "$D/err" | head -n 1))."
      else
        lines="$lines $pr: the forge is unreachable ($(tr '\n' ' ' < "$D/err" | cut -c 1-100)); still polling, backing off to at most five minutes."
      fi
    fi
  done
  [ -n "$lines" ] && say "Changed:$lines"
  if [ "$up" = 1 ]; then WAIT=60; else WAIT=$(( WAIT * 2 )); [ "$WAIT" -gt 300 ] && WAIT=300; fi
  if [ "$(now)" -ge "$(cat "$D/checkin")" ] && [ "$(cat "$D/host.down" 2>/dev/null)" != unreachable ]; then
    echo $(( $(now) + CHECKIN_MIN * 60 )) > "$D/checkin"
    say "Fallback check-in, every $CHECKIN_MIN minutes."
  fi
  sleep "$WAIT"
done
```

The `${D:?}` and `${K:?}` in its one `rm` are what let it start. Claude Code refuses an `rm` whose target could expand to the filesystem root when a variable is empty, and the guard makes the shell stop instead. Keep it.

Fill it in:

| Value | What goes there |
|---|---|
| `PLAN` | The plan file's path, as it appears in the repo |
| `PRS` | Every open phase change request in the plan, as `owner/repo#number`, separated by spaces. One watcher covers them all. Empty when the driver is waiting on the forge with nothing open, as [When the forge stops answering](#when-the-forge-stops-answering) says |
| `CHECKIN_MIN` | Minutes to the fallback check-in, below |
| `ONCE` | `0` under Monitor. `1` only for the fallback without Monitor, below |

It keeps its snapshots in a directory named for the plan under `$TMPDIR`, one file per change request, each named from the full identity plus a checksum so that `acme/web-api#1` and `acme/web_api#1` never share one. A re-armed watcher compares against the last one, so a change that lands while no watcher is running still prints on the first poll after re-arming. Arm a new watcher whenever the set of open change requests changes, and stop the old one.

**It asks the forge itself first.** Each poll starts with one request for the account it acts as (`gh api user`, or `glab api --hostname <host> user`), and polls the change requests only when that answers. The answer is tracked in a `host.down` file beside the per-change-request ones, which holds `unreachable` or `refused`. Every failed probe is classified again, and a line prints only when the category changes: an outage that ends in a 401, because the credentials expired meanwhile, prints the refusal rather than staying silent as unreachable, and the check-in comes back with it. So the watcher reports the forge's own state once per change of state, even with no change request in the list, and an outage prints one line for the host rather than one per change request.

**Skipping the driver's own comments.** The watcher skips a comment, review or review-thread comment only when it is the driver's by [Whose note it is](gates.md#whose-note-it-is): by the account `gh` is logged in as, **and** carrying `<!-- phases:driver v=1 -->` on a line of its own. The driver stamps everything it posts, so its own gate reports and replies never wake it. Everything else wakes it:

- **Your own comments.** In a local session the driver usually acts as your account. Before stamps, the watcher skipped that whole account, so your comments on the change request did not wake the session. They carry no driver stamp, so now they do.
- **A reviewer on your account**, whose notes carry a reviewer stamp, not the driver's.
- **A stamp typed by another account.** It hides nothing: the stamp counts only from the driver's own account.
- **A comment that merely mentions the stamp**, in a sentence or a code span. The test is for the stamp on a line of its own.

Two more things are skipped by account alone:

- **A review with an empty body from the driver's account.** GitHub creates one as the container for each reply the driver posts in a review thread. The reply inside it is the stamped item, so its container must not wake the session either.
- **Reactions from the driver's account.** A reaction has no body to stamp, so a 👍 you leave from your own account still wakes nothing. No gate reads it.

**The first poll after upgrading.** A watcher's snapshot files hold the items the old filter let through. Under this filter, the old driver's unstamped comments on a change request that is still open appear as new items, so the first poll after the upgrade prints one line per open change request. Answer that wake like any other: reconcile, find nothing new, re-arm.

### GitLab

For a repo whose forge is `gitlab`. The same loop, through `glab api` against the repo's `host`, so a GitLab watcher prints the same wake lines and keeps the same rules: silent when nothing changed, one line naming every MR that changed in a poll, a failed request reported once and never fatal, the check-in, and `ONCE`. What it snapshots per MR:

- the head sha, and whether the MR is open, merged or closed
- the head pipeline's status, and the status of each of its jobs
- the commit statuses on the head sha, which include external ones
- a new note, or a new note in a thread, from anyone, except a note that is the driver's by [Whose note it is](gates.md#whose-note-it-is): written by the account `glab` is logged in as **and** carrying the driver stamp on a line of its own. System notes are left out: a push already shows as a moved head
- among those, a note whose whole text is `@codex review` is printed as a `review request`. It is never the driver's, since the driver never writes that text on GitLab

A person's note asking `@codex review` reaches the watcher as a `review request`, and the wake answers it as the GitLab reference's [`@codex review` from a person](forge-gitlab.md#codex-review-from-a-person) says. Only a running watcher sees it: with no session watching the MR, nothing answers the request.

Reactions are not on the list: no gate reads them on GitLab. A request for changes is not either, because it adds no note; see the GitLab reference's **Watch**.

It needs `glab`, authenticated for the host, a `jq` binary (recent macOS ships one in `/usr/bin`; `glab api` has no `--jq` of its own), and bash 3.2. It was tested under macOS's `/bin/bash` 3.2 against a stand-in `glab` that replayed canned API responses and could be made to fail. It then ran under Monitor against gitlab.com for the whole of the first GitLab trial, [`examples/gitlab-local.md`](https://github.com/sixoverground/claude-phases/blob/main/examples/gitlab-local.md), which lists every line it printed: a finding, a marker, a moved head, a person's note and thread, a review request, a merge, and a network outage reported once and then its end. It never woke the session for the driver's own stamped notes.

```bash
HOST='[GitLab host, e.g. gitlab.com or gitlab.example.com]'
PLAN='[plan path, e.g. docs/plans/acme.md]'
MRS='[open phase MRs on that host, space separated, e.g. acme/web!42 acme/platform/api!7]'
CHECKIN_MIN=[minutes to the fallback check-in: 45 to 60, or 10 to 15]
ONCE=[0 under Monitor; 1 for a background command that exits on its first line]

key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; printf '_'; printf '%s' "$1" | cksum | cut -d ' ' -f 1; }
D="${TMPDIR:-/tmp}/phase-driver-watch/$(key "$PLAN")/gitlab-$(key "$HOST")"
mkdir -p "$D" || exit 1
WAKE="[phase-driver watcher] Invoke the phase-driver skill, then reconcile $PLAN."
say() { printf '%s %s\n' "$WAKE" "$1"; if [ "$ONCE" = 1 ]; then exit 0; fi; }
now() { date +%s; }
enc() { printf '%s' "$1" | jq -sRr @uri; }
api() { glab api --hostname "$HOST" "$@" > "$D/raw"; }

due=$(( $(now) + CHECKIN_MIN * 60 ))
old=$(cat "$D/checkin" 2>/dev/null)
case "$old" in ''|*[!0-9]*) old=$due ;; esac
[ "$old" -lt "$due" ] && due=$old
echo "$due" > "$D/checkin"

ME=''
WAIT=60
while :; do
  lines=''; up=0
  if glab api --hostname "$HOST" user > "$D/me" 2>"$D/err" &&
     me=$(jq -r '.username // empty | ascii_downcase' "$D/me" 2>>"$D/err") && [ -n "$me" ]; then
    up=1; ME=$me
    if [ -f "$D/host.down" ]; then
      rm -f "${D:?}/host.down"
      lines="$lines $HOST: the forge is answering again."
      echo $(( $(now) + CHECKIN_MIN * 60 )) > "$D/checkin"
    fi
  else
    if grep -q '(HTTP 40[134])' "$D/err"; then
      kind=refused; msg="$HOST: the forge refused access ($(grep -o 'HTTP 40[134]' "$D/err" | head -n 1))."
    else
      why=$(sed 's/^ *//; s/ *$//' "$D/err" | grep -v -e '^$' -e '^ERROR$' | head -n 1 | sed 's/^[A-Za-z]* "[^"]*": //' | cut -c 1-120)
      kind=unreachable; msg="$HOST: the forge is unreachable ($why); still polling, backing off to at most five minutes."
    fi
    if [ "$(cat "$D/host.down" 2>/dev/null)" != "$kind" ]; then echo "$kind" > "$D/host.down"; lines="$lines $msg"; fi
  fi
  [ "$up" = 1 ] && for mr in $MRS; do
    R=${mr%%!*}; N=${mr##*!}; P=$(enc "$R"); K=$(key "$mr"); new="$D/$K.new"
    if [ -n "$ME" ] && {
      api "projects/$P/merge_requests/$N" &&
      jq -r '"state \(.state)", "head \(.sha)", "check pipeline=\(.head_pipeline.status // "none") #\(.head_pipeline.id // "-")"' "$D/raw" > "$new" &&
      sha=$(sed -n 's/^head //p' "$new") &&
      pl=$(jq -r '.head_pipeline.id // empty' "$D/raw") &&
      { [ -z "$pl" ] || { api --paginate "projects/$P/pipelines/$pl/jobs?per_page=100" &&
          jq -r '.[] | "check \(.name)=\(.status)"' "$D/raw" >> "$new"; }; } &&
      api --paginate "projects/$P/repository/commits/$sha/statuses?per_page=100" &&
      jq -r '.[] | "check status \(.name)=\(.status)"' "$D/raw" >> "$new" &&
      api --paginate "projects/$P/merge_requests/$N/notes?per_page=100" &&
      jq -r --arg me "$ME" '.[] | select(.system | not)
        | (.body // "" | test("^\\s*@codex review\\s*$"; "i")) as $ask
        | ((.author.username | ascii_downcase) == $me
           and (.body // "" | split("\n") | map(rtrimstr("\r")) | any(. == "<!-- phases:driver v=1 -->"))) as $driver
        | select($ask or ($driver | not))
        | "item \(if $ask then "review request" elif .type == null then "note" else "thread note" end):\(.id)"' "$D/raw" >> "$new"
    } 2>"$D/err"; then
      up=1
      if [ -f "$D/$K.down" ]; then rm -f "${D:?}/${K:?}.down"; lines="$lines $mr: the forge is answering again."; fi
      LC_ALL=C sort -o "$new" "$new"
      if [ -f "$D/$K.old" ] && ! cmp -s "$D/$K.old" "$new"; then
        what=''
        a=$(sed -n 's/^state //p' "$D/$K.old"); b=$(sed -n 's/^state //p' "$new")
        [ "$a" != "$b" ] && what="$what; now $b"
        a=$(sed -n 's/^head //p' "$D/$K.old")
        [ "$a" != "$sha" ] && what="$what; head moved ${a%"${a#???????}"} -> ${sha%"${sha#???????}"}"
        c=$(LC_ALL=C comm -13 "$D/$K.old" "$new" | sed -n 's/^check //p' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
        [ -n "$c" ] && what="$what; checks: $c"
        i=$(LC_ALL=C comm -13 "$D/$K.old" "$new" | sed -n 's/^item \(.*\):.*/\1/p' | sort | uniq -c | sed 's/^ *\([0-9]*\) \(.*\)/\1 new \2/' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
        [ -n "$i" ] && what="$what; $i"
        [ -n "$what" ] && lines="$lines $mr:${what#;}."
      fi
      mv "$new" "$D/$K.old"
    elif [ ! -f "$D/$K.down" ]; then
      : > "$D/$K.down"
      if grep -q '(HTTP 40[134])' "$D/err"; then
        lines="$lines $mr: the forge refused access ($(grep -o 'HTTP 40[134]' "$D/err" | head -n 1))."
      else
        why=$(sed 's/^ *//; s/ *$//' "$D/err" | grep -v -e '^$' -e '^ERROR$' | head -n 1 | sed 's/^[A-Za-z]* "[^"]*": //' | cut -c 1-120)
        lines="$lines $mr: the forge is unreachable ($why); still polling, backing off to at most five minutes."
      fi
    fi
  done
  [ -n "$lines" ] && say "Changed:$lines"
  if [ "$up" = 1 ]; then WAIT=60; else WAIT=$(( WAIT * 2 )); [ "$WAIT" -gt 300 ] && WAIT=300; fi
  if [ "$(now)" -ge "$(cat "$D/checkin")" ] && [ "$(cat "$D/host.down" 2>/dev/null)" != unreachable ]; then
    echo $(( $(now) + CHECKIN_MIN * 60 )) > "$D/checkin"
    say "Fallback check-in, every $CHECKIN_MIN minutes."
  fi
  sleep "$WAIT"
done
```

Keep the guarded `rm` for the same reason as in the GitHub template.

Fill it in:

| Value | What goes there |
|---|---|
| `HOST` | The repo's resolved `host`, such as `gitlab.com` or `gitlab.example.com` |
| `PLAN` | The plan file's path, as it appears in the repo |
| `MRS` | Every open phase MR in the plan on that host, as `group/project!iid`, subgroups included, separated by spaces. Empty when the driver is waiting on that host with nothing open |
| `CHECKIN_MIN` | Minutes to the fallback check-in, below |
| `ONCE` | `0` under Monitor. `1` only for the fallback without Monitor, below |

One watcher covers every MR on one host. A plan with repos on more than one forge or host runs one watcher for each, and each keeps its snapshots in its own directory under the plan's, so they never share a file.

**Refused or unreachable.** A 401, 403 or 404 that GitLab itself sent, which `glab api` prints as `glab: <message> (HTTP <code>)`, prints as refused access. Anything else prints as unreachable, including a bare `glab: HTTP 403` with no GitLab message, which usually comes from a proxy in front of the host, as the GitLab reference's **Unreachable or denied** says.

**Skipping the driver's own notes** works as in the GitHub template: a note is skipped only when it is by the username `glab` is logged in as **and** carries the driver stamp on a line of its own. Your own notes, a reviewer's notes on your account, and a stamp typed by anyone else all wake the session. GitLab has no empty reply container, and the template reads no award emoji, so neither of the GitHub template's account-only skips is needed. The first poll after upgrading prints one line per open MR, as above.

## The wake message

Every line the watcher prints is a complete wake message for a session that has nothing: it says to invoke `phase-driver`, names the plan, says to reconcile, and then says what changed.

```
[phase-driver watcher] Invoke the phase-driver skill, then reconcile docs/plans/acme.md. Changed: acme/web#42: head moved 851f6c6 -> 2c00bee; checks: test=in_progress.
```

Act on it as on any wake: invoke the skill, reconcile, then handle what changed. What it says changed is a hint about where to look, never a substitute for reading the forge.

## The fallback check-in

The watcher prints the check-in itself, as a line with no change in it.

**Not while the forge is down.** While `host.down` says `unreachable`, the watcher prints no check-in: a wake then has nothing to reconcile against, and each one used to become another "still unreachable" message to the user. The deadline is kept, not pushed back. When the host answers again, the "answering again" line is the wake, and the next check-in is a full interval from then. Suppression keys on the host's own state and nothing else: a change request that fails while the host answers, refused or missing, does not suppress it, and neither does a list with nothing in it.
 It measures by wall clock, so a Mac that slept through the deadline gets its check-in on the first poll after waking, rather than a full interval later.

- **45 to 60 minutes** out, ordinarily.
- **10 to 15 minutes** out when the answer you are waiting on has no event of its own, typically a reviewer that has reacted 👀 and is still working.

A re-armed watcher keeps the earlier deadline when it is sooner than its own, so re-arming every 30 minutes does not push a 45-minute check-in away forever.

## When Monitor expires

Monitor stops a watch after its timeout, 30 minutes at most, and tells you once.

**An expiry with no events is not a wake.** Re-arm the watcher with the same values and end the turn. Do not reconcile, do not write a heartbeat, and do not post anything. **That holds during an outage too**: the user was told once that the forge is unreachable, and an expiry tells them nothing new, so re-arm silently and say nothing to them. Nothing happened. Treating it as a wake writes a plan commit and a comment every half hour all night, and wakes nobody for anything.

## Without Monitor

Where Monitor is unavailable, run the same template as a background shell command with `ONCE=1`. It exits after printing its first line, and its completion notification is the wake. Run it again after handling the wake, before ending the turn.

## The watcher holds nothing

A session that dies loses its watcher, and nothing is lost with it: the snapshots only decide what to print. The next session's reconcile re-arms it for every change request that is still open.

## When the forge stops answering

The watcher says so once when the forge itself stops answering it, and once when it answers again, never once per failed poll. While the host is down it does not poll the change requests, since they cannot answer either, and it backs off, doubling the interval up to five minutes. A change request that fails while the host answers is reported on its own, once, and does not hold up the others: a healthy one still reports its changes. A request the forge answered with 401, 403 or 404 prints as refused access rather than unreachable, because the driver treats the two differently: see [The forge is unreachable](recovery.md#the-forge-is-unreachable).

**Arm it with nothing open, too.** When the driver is waiting on the forge and has no change request to watch, as when a status write could not be made, it arms the watcher with an empty `PRS` or `MRS` for that host. The host's "answering again" line is then what wakes it. Without this a driver whose only waiting work has no change request yet has nothing that tells it the forge came back.

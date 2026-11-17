# Watching

How a driver gets woken while it waits on a change request: CI finishing, a reviewer answering, a push, a merge. The plan holds every piece of state; this file is only about what ends a wait.

## Subscribe where you can, watch where you can't

**If the session can subscribe to change-request activity, subscribe**, exactly as the forge reference's **Watch** says, and schedule the fallback check-in below. A cloud session on GitHub does this, and nothing in this file changes it.

**If it cannot, arm the watcher.** A local session in a terminal has no webhooks, and a forge behind a VPN could not deliver them anyway. Without something to wake it, a local driver that ends its turn on a wait simply stops.

Choose by what the session can do, not by where you think it is running. There is no setting for this.

## The watcher

A polling loop the driver fills in and runs under the Monitor tool. Every 60 seconds it snapshots each open phase change request, and it prints **one line only when something changed**. A poll where nothing changed prints nothing.

What counts as a change, per change request:

- the head sha
- the state or conclusion of any check on the head
- a new comment, review, review-thread comment or reaction from anyone other than the account the driver acts as
- merged or closed

Reactions are on the list because some reviewers answer with nothing else: a 👍 from a reviewer on smart detect delivers no event, and it is often the whole answer.

**Use the template as written. Replace only the four bracketed values.** A loop improvised on each wake is where a silent failure would hide: one that exits on its first failed request, or compares the wrong field, looks exactly like a quiet change request. This one was run against a real PR before it was written down, it tolerates a failed request without exiting, and it needs nothing but `gh`, `jq` (which `gh` carries for `--jq`) and the bash 3.2 that macOS ships.

### GitHub

```bash
PLAN='[plan path, e.g. docs/plans/acme.md]'
PRS='[open phase PRs, space separated, e.g. acme/web#42 acme/api#7]'
CHECKIN_MIN=[minutes to the fallback check-in: 45 to 60, or 10 to 15]
ONCE=[0 under Monitor; 1 for a background command that exits on its first line]

D="${TMPDIR:-/tmp}/phase-driver-watch/$(printf '%s' "$PLAN" | tr -c 'A-Za-z0-9' '_')"
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
  ok=1; lines=''
  if [ -z "$ME" ]; then
    ME=$(gh api user --jq '.login | ascii_downcase' 2>"$D/err") || { ok=0; ME=''; }
  fi
  for pr in $PRS; do
    [ "$ok" = 1 ] || break
    R=${pr%%#*}; N=${pr##*#}; K=$(printf '%s' "$pr" | tr -c 'A-Za-z0-9' '_')
    new="$D/$K.new"
    gh api "repos/$R/pulls/$N" --jq '"state \(.state) merged=\(.merged)", "head \(.head.sha)"' > "$new" 2>"$D/err" || { ok=0; break; }
    sha=$(sed -n 's/^head //p' "$new")
    {
      gh api "repos/$R/commits/$sha/check-runs?per_page=100" --jq '.check_runs[] | "check \(.name)=\(.conclusion // .status)"' &&
      gh api "repos/$R/commits/$sha/status" --jq '.statuses[] | "check \(.context)=\(.state)"' &&
      gh api --paginate "repos/$R/issues/$N/comments?per_page=100" --jq ".[] | select((.user.login | ascii_downcase) != \"$ME\") | \"item comment:\(.id)\"" &&
      gh api --paginate "repos/$R/pulls/$N/comments?per_page=100" --jq ".[] | select((.user.login | ascii_downcase) != \"$ME\") | \"item thread comment:\(.id)\"" &&
      gh api --paginate "repos/$R/pulls/$N/reviews?per_page=100" --jq ".[] | select((.user.login | ascii_downcase) != \"$ME\") | \"item review:\(.id)\"" &&
      gh api --paginate "repos/$R/issues/$N/reactions?per_page=100" --jq ".[] | select((.user.login | ascii_downcase) != \"$ME\") | \"item reaction \(.content):\(.id)\""
    } >> "$new" 2>"$D/err" || { ok=0; break; }
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
  done
  if [ "$ok" = 1 ]; then
    WAIT=60
    if [ -f "$D/down" ]; then rm -f "$D/down"; say "The forge is answering again."; fi
    [ -n "$lines" ] && say "Changed:$lines"
  else
    [ "$WAIT" -lt 300 ] && WAIT=$(( WAIT * 2 )); [ "$WAIT" -gt 300 ] && WAIT=300
    if grep -q 'HTTP 40[134]' "$D/err" && ! grep -qi 'rate limit' "$D/err"; then
      msg="The forge refused access ($(grep -o 'HTTP 40[134]' "$D/err" | head -n 1))."
    else
      msg="The forge is unreachable ($(tr '\n' ' ' < "$D/err" | cut -c 1-100))."
    fi
    if [ ! -f "$D/down" ]; then : > "$D/down"; say "$msg Still polling, backing off to at most five minutes."; fi
  fi
  if [ "$(now)" -ge "$(cat "$D/checkin")" ]; then
    echo $(( $(now) + CHECKIN_MIN * 60 )) > "$D/checkin"
    say "Fallback check-in, every $CHECKIN_MIN minutes."
  fi
  sleep "$WAIT"
done
```

Fill it in:

| Value | What goes there |
|---|---|
| `PLAN` | The plan file's path, as it appears in the repo |
| `PRS` | Every open phase change request in the plan, as `owner/repo#number`, separated by spaces. One watcher covers them all |
| `CHECKIN_MIN` | Minutes to the fallback check-in, below |
| `ONCE` | `0` under Monitor. `1` only for the fallback without Monitor, below |

It keeps its snapshots in a directory named for the plan under `$TMPDIR`. A re-armed watcher compares against the last one, so a change that lands while no watcher is running still prints on the first poll after re-arming. Arm a new watcher whenever the set of open change requests changes, and stop the old one.

**Skipping the driver's own comments.** The watcher ignores comments, reviews and reactions by the account `gh` is logged in as, so the driver is not woken by its own gate reports. In a local session that account is usually the person's own, so their comments on the change request do not wake the session either. Talk to the session instead.

## The wake message

Every line the watcher prints is a complete wake message for a session that has nothing: it says to invoke `phase-driver`, names the plan, says to reconcile, and then says what changed.

```
[phase-driver watcher] Invoke the phase-driver skill, then reconcile docs/plans/acme.md. Changed: acme/web#42: head moved 851f6c6 -> 2c00bee; checks: test=in_progress.
```

Act on it as on any wake: invoke the skill, reconcile, then handle what changed. What it says changed is a hint about where to look, never a substitute for reading the forge.

## The fallback check-in

The watcher prints the check-in itself, as a line with no change in it. It measures by wall clock, so a Mac that slept through the deadline gets its check-in on the first poll after waking, rather than a full interval later.

- **45 to 60 minutes** out, ordinarily.
- **10 to 15 minutes** out when the answer you are waiting on has no event of its own, typically a reviewer that has reacted 👀 and is still working.

A re-armed watcher keeps the earlier deadline when it is sooner than its own, so re-arming every 30 minutes does not push a 45-minute check-in away forever.

## When Monitor expires

Monitor stops a watch after its timeout, 30 minutes at most, and tells you once.

**An expiry with no events is not a wake.** Re-arm the watcher with the same values and end the turn. Do not reconcile, do not write a heartbeat, and do not post anything. Nothing happened. Treating it as a wake writes a plan commit and a comment every half hour all night, and wakes nobody for anything.

## Without Monitor

Where Monitor is unavailable, run the same template as a background shell command with `ONCE=1`. It exits after printing its first line, and its completion notification is the wake. Run it again after handling the wake, before ending the turn.

## The watcher holds nothing

A session that dies loses its watcher, and nothing is lost with it: the snapshots only decide what to print. The next session's reconcile re-arms it for every change request that is still open.

## When the forge stops answering

The watcher prints one line when the forge stops answering, and one when it answers again, never one per failed poll. While it is down it backs off, doubling the interval up to five minutes. A request the forge answered with 401, 403 or 404 prints as refused access rather than unreachable, because the driver treats the two differently: see [The forge is unreachable](recovery.md#the-forge-is-unreachable).

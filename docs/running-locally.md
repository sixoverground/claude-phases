# Running locally

The driver normally runs in a Claude Code cloud session, woken by webhooks. It can also run in a Claude Code session on your own Mac, in a terminal. This guide covers that case: when it is worth it, what changes, and how to keep a session alive long enough to finish a plan.

Everything below about the session's own behaviour comes from the plan that built this project's GitLab support, which was driven from a terminal on a Mac. Where something was seen there, the guide says so. Where it rests only on documentation, it links the page. [Commands in this guide](#commands-in-this-guide) says which commands were run on a Mac and which were not.

## When to run locally

Run locally when a cloud session cannot do the job:

- **A forge a cloud session cannot reach.** A self-managed GitLab behind a company VPN, or any host that only your machine can resolve.
- **A toolchain only your machine has.** An iOS app needs macOS and Xcode to build, and no cloud container has either. On a Mac with Xcode, the driver can build it before it pushes (`verify: local`) instead of waiting on CI.

Otherwise a cloud session is simpler. It needs no machine kept awake, and it can be started from your phone.

## What is different

**A watcher where webhooks were.** A cloud session subscribes to pull request activity and is woken by events. A local session has no webhooks, so the driver arms a watcher: a polling loop it runs under Claude Code's [Monitor tool](https://code.claude.com/docs/en/tools-reference#monitor-tool), which prints one line when a change request changes and nothing otherwise. The template, for GitHub and for GitLab, is in [`watching.md`](../skills/phase-driver/references/watching.md). You do not write or run it yourself; the driver does.

Two things about it were seen in practice:

- **Monitor's deadline.** Every watch has one, at most 30 minutes. When it expires with nothing to report, the driver re-arms it and does nothing else: no reconcile, no plan commit, no comment. That is by design, so a quiet night does not write a commit every half hour.
- **The check-in runs on the wall clock.** The watcher prints a fallback check-in every 45 to 60 minutes whether or not anything changed, measured by the clock rather than by time awake. A Mac that slept through the deadline gets its check-in on the first poll after it wakes.

**The session is a process on your machine.** It lives as long as the `claude` process does. Close the terminal, let the Mac sleep, or log out, and the driver stops. Nothing is lost when it does, because the plan file is the state, but nothing moves either until a session runs again. [Keeping the session alive](#keeping-the-session-alive) is the part of local running that needs care.

**You talk to it in the terminal, or from your phone.** See [Steering it from your phone](#steering-it-from-your-phone).

## Installing the plugin for a local session

In the terminal, start Claude Code in the repo and install the plugin, as the [README](../README.md#installing) says:

```
/plugin marketplace add sixoverground/claude-phases
/plugin install claude-phases@sixoverground
```

From your shell, without a session, `claude plugin install claude-phases@sixoverground` does the same once the marketplace is added (`claude plugin marketplace add sixoverground/claude-phases`).

Three things to know:

- **A running session keeps the version it loaded.** An update to the plugin does not reach a session that is already running. Claude Code's [plugin docs](https://code.claude.com/docs/en/discover-plugins#keep-plugins-updated) say to run `/reload-plugins`; the run behind this guide restarted the session after each release instead. Either way, do it at a quiet moment, such as after a milestone merges, not mid-phase.
- **An installed copy and a `--plugin-dir` copy collide.** If you work on the plugin and start Claude Code with `--plugin-dir <path>` to load a checkout of it, the installed copy loads too, and the two collide. Disable one: `claude plugin disable claude-phases@sixoverground` while you use the checkout, then `claude plugin enable claude-phases@sixoverground` after.
- **A cloud session does not load plugins you installed on your Mac**, so a plan you drive from both needs the plugin installed in each place. Install where the session runs.

## Keeping the session alive

This is the one part of local running with no recovery beyond the plan file. A session that dies overnight is noticed in the morning, and the plan waits until then. `docs/design.md` records this as a known gap: nobody notices a dead session.

**Run it in a terminal multiplexer**, so closing the terminal window does not end it. `screen` ships with macOS:

```sh
screen -S phases            # start a named session, then run claude inside it
# detach with Ctrl-a d; the session keeps running
screen -r phases            # reattach later
```

`tmux` works the same way (`tmux new -s phases`, detach with Ctrl-b d, `tmux attach -t phases`) and installs with Homebrew. Either is fine; the point is that the `claude` process does not belong to the terminal window.

**Keep the Mac awake.** A sleeping Mac stops the session, the watcher and any local runner together. `caffeinate` holds a power assertion for as long as it runs:

```sh
caffeinate -i -w <claude pid>     # prevent idle sleep until that process exits
caffeinate -i claude              # or start Claude Code under it
```

`-i` prevents idle sleep, and `-w` ends the assertion when the process with that pid exits, so it does not outlive the session. To find the pid, the driver already knows its own: Claude Code sets `CLAUDE_PID` for the commands it runs, and the shell those commands run in is a child of the `claude` process. On a laptop, closing the lid still sleeps the Mac on battery whatever `caffeinate` says, so leave it open or plugged in.

To see what is keeping the Mac awake, or whether anything is, read the settings without changing them:

```sh
pmset -g                  # sleep settings, and which processes are preventing sleep
pmset -g assertions       # the assertions currently held
```

To change the sleep settings themselves, use System Settings (Battery, or Energy on a desktop Mac), not this guide.

**A VPN or Wi-Fi drop is a wait, not a failure.** When the forge stops answering, the watcher prints one line saying it is unreachable, keeps polling with a back-off of up to five minutes, and prints one line when it answers again. Seen on this project's run during a Wi-Fi drop: one unreachable line, then one recovered line, and nothing in between. The driver marks nothing `Blocked` for an outage and counts nothing toward its stuck limits. A self-managed host behind a VPN usually fails as a DNS error or a timeout, which the driver reads as unreachable. When the VPN comes back the next poll picks up where it was.

## Steering it from your phone

Claude Code's [Remote Control](https://code.claude.com/docs/en/remote-control) connects the Claude mobile app, or claude.ai/code in a browser, to a session running on your Mac. The session keeps running locally; the phone is a window onto it.

Start the session with it on:

```sh
claude --remote-control "acme plan"     # or --rc; the name is optional
```

or turn it on in a session that is already running with `/remote-control` (or `/rc`). The session then appears in the session list in the Claude app and at claude.ai/code, and the terminal shows a QR code on request. From there you can say `status`, `pause`, `yolo off` and the rest of the driver's vocabulary, as you would in the terminal.

What the documentation says about it, which matters for a long run:

- It needs a claude.ai login on a Pro, Max, Ultra, Team or Enterprise plan, not an API key. On Team and Enterprise an Owner turns it on first.
- **The local process must keep running.** Remote Control does not keep the session alive; it is only a way in while the session is alive. Everything under [Keeping the session alive](#keeping-the-session-alive) still applies.
- An interactive session started with `--remote-control` reconnects by itself after the Mac sleeps or the network drops, once it is awake and online again.

## Resuming after a crash

If the session dies, or you quit the terminal by mistake, open a terminal in the same directory and continue the most recent conversation:

```sh
claude --continue                       # or -c
claude --continue --remote-control      # and reconnect your phone in the same step
```

**Even that is optional.** The plan file is the state, so a brand-new session works just as well: start `claude` in the repo and say **"run the next phase"**, or **`resume`** if the plan was paused. The driver reconciles the plan against the forge and carries on from wherever the last session stopped. **`status` is not a way to resume**: it reports progress and writes nothing, so it neither claims the plan nor starts any work. Say it first if you want to see where things stand, then one of the two above. `--continue` only saves re-reading the conversation.

**A dead session no longer holds the plan for 90 minutes.** The plan's Driver State records which process holds it (`Driver-ID`, and `Driver-Host` with the host, pid and start time). A new session on the same Mac sees that the recorded process is gone and takes over at once. A holder on another machine, or one whose process it cannot check, is treated as alive until its heartbeat is 90 minutes old. If you know that session is dead, say **`take over`**, and the driver releases the claim after you confirm.

## A clone of its own

**Give the driver a clone of each repo that nobody else uses**, separate from your own checkout and from any CI runner's build directory:

```sh
git clone https://github.com/acme/acme-web.git ~/phases/acme-web
cd ~/phases/acme-web && claude --remote-control
```

The driver checks out phase branches, resets, rebases and force-pushes with leases. In your checkout that moves your working tree under you and can lose uncommitted work. In a runner's build directory it changes what the runner is building. A clone costs one `git clone` per repo.

If a CI runner runs on the same Mac, the [hygiene checklist](../skills/phase-planner/references/hygiene.md) has the rest: separate DerivedData for an Xcode build, a simulator the runner does not use, one job at a time on the runner.

## Tokens, and which identity posts what

A local session acts as whatever its tools are logged in as on your Mac, usually you.

- **Change requests and comments.** On GitHub the driver opens PRs with the GitHub tools the session has; in a local session those normally act as your account. On GitLab, `glab` acts as the account it is authenticated as for that host. Check with `glab auth status --hostname <host>` before a plan starts.
- **Plan commits** carry the author in your git config, since the driver commits with git.
- **The watcher ignores its own account.** It skips comments, reviews and reactions by the account `gh` or `glab` is logged in as, so the driver's own gate reports do not wake it. In a local session that account is usually yours, so **your own comments on the change request do not wake the session either.** Talk to the session, in the terminal or from your phone.
- **Reviewers post as themselves.** A review bot or a review job posts under its own account, which is what the plan's `logins` name. Do not run a reviewer under your own account: the watcher would never see it, and for a `marker` reviewer anyone could then post its marker.

## What a night of waiting costs

A waiting driver has ended its turn, so it is not thinking while it waits. What a night costs is the turns it takes when something wakes it, and the polling in between.

- **Turns.** A wake is a turn: a change on a change request, a fallback check-in every 45 to 60 minutes, and a short turn each time Monitor's deadline passes, to re-arm the watcher. The re-arm turn does nothing else, by design. A night with nothing happening is a handful of small turns, not a stream of them.
- **API calls.** The watcher polls every 60 seconds, several requests per open change request per poll, for as long as it runs. On GitHub that counts against your account's API rate limit, so many open PRs at once, all night, add up. It backs off to five minutes while the forge is unreachable.
- **The Mac.** It stays awake, and on a laptop that means plugged in.

## Commands in this guide

Checked on a Mac running macOS (Darwin 27.2), Claude Code 2.1.327, Xcode 27.2. "Help" means the command's own help or man page was read; nothing that changes system settings was run.

| Command | Checked |
|---|---|
| `claude --remote-control [name]`, `--rc`, `/remote-control`, `/rc` | `claude --help` lists `--remote-control [name]`; the rest from the [Remote Control docs](https://code.claude.com/docs/en/remote-control). Connecting from a phone was not done for this guide |
| `claude --continue`, `-c` | `claude --help`, and the [CLI reference](https://code.claude.com/docs/en/cli-reference) |
| `claude --plugin-dir <path>` | `claude --help` |
| `claude plugin install`, `disable`, `enable`, `marketplace add` | `claude plugin --help`, and each subcommand's `--help` |
| `/plugin marketplace add`, `/plugin install`, `/reload-plugins` | [Plugin docs](https://code.claude.com/docs/en/discover-plugins); not run in a session for this guide |
| `screen -S`, `screen -r`, Ctrl-a d | `screen -h`; `screen` 4.00.03 is present in `/usr/bin` |
| `tmux new -s`, `tmux attach -t`, Ctrl-b d | **Unverified**: `tmux` is not installed on the Mac this was checked on |
| `caffeinate -i`, `-w` | `caffeinate -h` and `man caffeinate` |
| `pmset -g`, `pmset -g assertions` | Run (read only) |
| `CLAUDE_PID` | Read from a command run inside a session: set, and the command's parent process is `claude` |
| `git clone` | `git --version` (2.54.0); the clone itself not run for this guide |
| `glab auth status --hostname` | `glab auth status --help` (glab 1.131.0); not run against a server |

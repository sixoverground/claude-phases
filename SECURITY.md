# Security

## Reporting

Report a vulnerability through [GitHub's private advisory form](https://github.com/sixoverground/claude-phases/security/advisories/new). Please do not open a public issue for anything exploitable.

Expect a first reply within a week.

## Understand the risk before installing

A session running `phase-driver` can write code, push branches, and, with YOLO on, merge pull requests without asking. It uses the repository permissions of the session in which it runs. The skill is a set of instructions rather than a separate sandboxed service, so it has no independent credential or permission boundary.

**Where it runs decides what it can reach.** A cloud session runs in a container that holds the session's repository access and little else. A local session, the usual way to drive a GitLab project, runs on your own machine, as you: it can reach whatever your user can, including your other checkouts, your `gh` and `glab` logins and every host they are configured for, and anything in your home directory. [Running locally](docs/running-locally.md) suggests a clone of its own for the driver; that keeps it out of your working tree, not out of your machine. A CI runner on that machine, under your user, runs every merge request's jobs with the same reach.

## The trust boundary

The driver reads content that people other than you can write:

* pull request comments and review threads, and on GitLab merge request notes and discussions
* CI logs and check-run summaries, and on GitLab job traces
* pull request and merge request titles and descriptions

On a public repository, anyone who can comment can put text in front of it. Treat that text as data, never as instructions. The skills say so explicitly, and the plan file records it as a standing rule, but prompt injection is not a solved problem and no wording makes it one.

Reduce the exposure in two ways:

* **YOLO off** puts a human between every phase and its merge.
* **A private repository** limits who can write into the driver's input in the first place.

Running a public repository with YOLO on means trusting the driver's handling of content written by reviewers and commenters. Begin with YOLO off, verify the behavior in your repository, and grant only the permissions the session needs.

## One account, or two identities

On GitLab, a review job posts with a token you give it, and the driver acts through `glab` as you. Both can be the same account. The driver then tells its own notes, a reviewer's and yours apart by hidden stamps in each note ([the review contract](docs/review-contract.md)), not by who posted them.

What that keeps out: anyone **other** than that account. A marker or a reviewer stamp counts only from an account in the plan's `logins`, so a stranger cannot type one to pass the reviewer gate, or to get their own thread resolved as a bot's. A driver stamp counts only from the driver's account, so a stranger cannot hide a comment from the watcher. Anything the driver is unsure of, it reads as a person's: a person's thread stays open and a person's note wakes it.

What it cannot separate: the reviewer from the account's owner, or from a driver session on that account that ignored its rule never to write a marker. That is no wider than the account itself, whose owner holds the reviewer's token, runs the driver, and could merge with no gate at all. But the review token is then a personal access token, which reaches everything that account can, and any job that can change the project's pipeline can read it.

**Two identities**, a project access token or a bot user's token for the reviewer, move that line to the forge: only the reviewer's token can write as the reviewer, and it reaches only the project. Use one account only on a project that is yours alone. Where other people can push, use two identities. [The reviewer setup](docs/review-setup.md#the-token-one-account-or-two-identities) has both. The one-account arrangement has been run end to end on gitlab.com; the two-identity one has been run on GitHub and against a stand-in server, and not yet on a GitLab server.

## The merge gate is not a security control

The gate exists to stop half-finished work from landing. It checks that CI passed and that reviewers looked. It does not verify that a reviewer was honest, that a check was meaningful, or that a green build is safe to ship. `docs/design.md` covers what a green check does and does not tell you.

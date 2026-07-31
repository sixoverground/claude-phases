# Security

## Reporting

Report a vulnerability through [GitHub's private advisory form](https://github.com/sixoverground/claude-phases/security/advisories/new). Please do not open a public issue for anything exploitable.

Expect a first reply within a week.

## What these skills can do

Worth understanding before you install them, because the blast radius is larger than most skills.

A session running `phase-driver` writes code, pushes branches, and with YOLO on it merges pull requests without asking. It holds whatever repository permissions the session it runs in holds. There is no separate credential and no sandbox: the skill is instructions, and the authority is your session's.

## The trust boundary

The driver reads content that people other than you can write:

* pull request comments and review threads
* CI logs and check-run summaries
* pull request titles and descriptions

On a public repository, anyone who can comment can put text in front of it. Treat that text as data, never as instructions. The skills say so explicitly, and the plan file records it as a standing rule, but prompt injection is not a solved problem and no wording makes it one.

Two things reduce the exposure:

* **YOLO off** puts a human between every phase and its merge.
* **A private repository** limits who can write into the driver's input in the first place.

If you run this on a public repository with YOLO on, you are trusting the reviewer's output and every commenter with the merge button.

## The merge gate is not a security control

The gate exists to stop half-finished work from landing. It checks that CI passed and that reviewers looked. It does not verify that a reviewer was honest, that a check was meaningful, or that a green build is safe to ship. `docs/design.md` covers what a green check does and does not tell you.

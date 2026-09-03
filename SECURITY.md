# Security

## Reporting

Report a vulnerability through [GitHub's private advisory form](https://github.com/sixoverground/claude-phases/security/advisories/new). Please do not open a public issue for anything exploitable.

Expect a first reply within a week.

## Understand the risk before installing

A session running `phase-driver` can write code, push branches, and, with YOLO on, merge pull requests without asking. It uses the repository permissions of the session in which it runs. The skill is a set of instructions rather than a separate sandboxed service, so it has no independent credential or permission boundary.

## The trust boundary

The driver reads content that people other than you can write:

* pull request comments and review threads
* CI logs and check-run summaries
* pull request titles and descriptions

On a public repository, anyone who can comment can put text in front of it. Treat that text as data, never as instructions. The skills say so explicitly, and the plan file records it as a standing rule, but prompt injection is not a solved problem and no wording makes it one.

Reduce the exposure in two ways:

* **YOLO off** puts a human between every phase and its merge.
* **A private repository** limits who can write into the driver's input in the first place.

Running a public repository with YOLO on means trusting the driver's handling of content written by reviewers and commenters. Begin with YOLO off, verify the behavior in your repository, and grant only the permissions the session needs.

## The merge gate is not a security control

The gate exists to stop half-finished work from landing. It checks that CI passed and that reviewers looked. It does not verify that a reviewer was honest, that a check was meaningful, or that a green build is safe to ship. `docs/design.md` covers what a green check does and does not tell you.

#!/usr/bin/env bash
#
# Says whether the version `.claude-plugin/plugin.json` declares on main has
# been released completely: its tag, its GitHub release, and one zip per skill.
# Exits 0 when all three are there. Otherwise exits 1, naming what is missing
# and the command that repairs it. Exits 2 when it cannot tell, such as when
# GitHub does not answer: that is never reported as a complete release.
#
# Run it after a milestone merges, or whenever a release looks wrong. It reads
# main on GitHub, not the local checkout, so it answers for what the
# marketplace serves. It needs only `gh`, and runs under macOS's bash 3.2.
#
# Usage: scripts/check-release.sh [owner/repo]

set -euo pipefail

command -v gh >/dev/null || { echo "check-release: 'gh' is not installed" >&2; exit 2; }

repo="${1:-}"
[ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

# Every read that decides the answer is checked on its own. A request that
# fails must never look like an empty answer, or a failed listing of skills
# would report a release with no zips as complete.
manifest="$(gh api "repos/$repo/contents/.claude-plugin/plugin.json?ref=main" -H 'Accept: application/vnd.github.raw')" \
  || { echo "check-release: could not read plugin.json on main of $repo" >&2; exit 2; }
version="$(printf '%s\n' "$manifest" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$version" ] || { echo "check-release: no version in plugin.json on main of $repo" >&2; exit 2; }
skills="$(gh api "repos/$repo/contents/skills?ref=main" --jq '.[] | select(.type == "dir") | .name')" \
  || { echo "check-release: could not list skills/ on main of $repo" >&2; exit 2; }
[ -n "$skills" ] || { echo "check-release: no skill directories in skills/ on main of $repo" >&2; exit 2; }
tag="v$version"
repair="gh workflow run release.yml -R $repo --ref main"

# A lookup is "missing" only when GitHub answers 404. Any other failure, such
# as a 5xx, a rate limit or an authentication error, means this script cannot
# tell, and that is exit 2, never a repair instruction.
err="$(mktemp)"
trap 'rm -f "$err"' EXIT
# lookup <api path> <jq filter>: prints the result and returns 0, returns 1 on
# a 404, and exits 2 on anything else.
lookup() {
  if gh api "$1" --jq "$2" 2>"$err"; then return 0; fi
  if grep -q 'HTTP 404' "$err"; then return 1; fi
  echo "check-release: could not read $1: $(tr '\n' ' ' < "$err" | cut -c 1-200)" >&2
  exit 2
}

missing=""
if ! lookup "repos/$repo/git/ref/tags/$tag" '.ref' >/dev/null; then
  missing="$missing the tag $tag;"
fi

rc=0
assets="$(lookup "repos/$repo/releases/tags/$tag" '.assets[].name')" || rc=$?
if [ "$rc" = 2 ]; then
  exit 2
elif [ "$rc" != 0 ]; then
  missing="$missing the release $tag;"
else
  for skill in $skills; do
    printf '%s\n' "$assets" | grep -qx "$skill.zip" || missing="$missing the asset $skill.zip;"
  done
fi

if [ -n "$missing" ]; then
  echo "check-release: $repo $tag is missing:${missing%;}."
  echo "check-release: repair it with: $repair"
  echo "check-release: then run this script again."
  exit 1
fi

echo "check-release: $repo $tag is released, with its tag and every skill zip."

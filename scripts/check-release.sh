#!/usr/bin/env bash
#
# Says whether the version `.claude-plugin/plugin.json` declares on main has
# been released completely: its tag, its GitHub release, and one zip per skill.
# Exits 0 when all three are there. Otherwise exits 1, naming what is missing
# and the command that repairs it.
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

version="$(gh api "repos/$repo/contents/.claude-plugin/plugin.json?ref=main" -H 'Accept: application/vnd.github.raw' \
  | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$version" ] || { echo "check-release: no version in plugin.json on main of $repo" >&2; exit 2; }
tag="v$version"
repair="gh workflow run release.yml -R $repo --ref main"

missing=""
if ! gh api "repos/$repo/git/ref/tags/$tag" >/dev/null 2>&1; then
  missing="$missing the tag $tag;"
fi

if ! assets="$(gh release view "$tag" -R "$repo" --json assets --jq '.assets[].name' 2>/dev/null)"; then
  missing="$missing the release $tag;"
else
  for skill in $(gh api "repos/$repo/contents/skills?ref=main" --jq '.[] | select(.type == "dir") | .name'); do
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

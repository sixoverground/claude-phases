#!/usr/bin/env bash
#
# Creates the tag and GitHub release for the version `.claude-plugin/plugin.json`
# declares, if that version hasn't been released yet.
#
# The tag is DERIVED from the manifest rather than asserted next to it, which is
# the point: the two cannot disagree, because only one of them is written by
# hand. Bumping the version and merging is the whole release ritual.
#
# Idempotent. A plugin.json edit that doesn't touch the version (a description,
# a keyword) finds its tag already present and exits quietly, so this is safe to
# re-run and safe to fire on any push that touches the manifest. Re-running it
# still ensures the skill zips are attached, which is how a release that missed
# them gets them without cutting a new version.
#
# It attaches the zips itself rather than leaving that to package-skills.yml.
# GitHub does not start a workflow from an event raised with the repository's
# GITHUB_TOKEN, so a release created here fires no `release: published` run at
# all. That is not a subtlety anyone should have to hold: v0.2.0 through v0.3.0
# were published by hand and got their zips, v0.4.0 was the first cut by this
# script and shipped with none, and nothing failed to say so.
#
# Usage: scripts/release.sh [--dry-run]

set -euo pipefail

dry_run=""
[ "${1:-}" = "--dry-run" ] && dry_run=1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

command -v gh >/dev/null || { echo "release: 'gh' is not installed" >&2; exit 1; }

version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .claude-plugin/plugin.json | head -1)"
[ -n "$version" ] || { echo "release: no version field in .claude-plugin/plugin.json" >&2; exit 1; }

tag="v$version"

# Attaching is separate from creating so that re-running against an existing
# release repairs its assets instead of exiting on the first check.
attach_zips() {
  local out
  out="$(mktemp -d)"
  "$repo_root/scripts/package-skills.sh" "$out" >/dev/null
  # --clobber so a re-run replaces the assets rather than failing on names that
  # are already there.
  gh release upload "$tag" "$out"/*.zip --clobber
  rm -rf "$out"
  echo "release: attached skill zips to $tag"
}

if gh release view "$tag" >/dev/null 2>&1; then
  echo "release: $tag already released"
  [ -n "$dry_run" ] && { echo "release: would ensure skill zips are attached"; exit 0; }
  attach_zips
  exit 0
fi

# The CHANGELOG section for this version, if there is one. Stops at the next
# `## [` so it takes one release's notes and not the rest of the file.
notes="$(awk -v v="$version" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/      { exit }
  found                  { print }
' CHANGELOG.md)"

# Trim leading and trailing blank lines.
notes="$(printf '%s' "$notes" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -n "$dry_run" ]; then
  echo "release: would create $tag"
  if [ -n "$notes" ]; then
    echo "--- notes from CHANGELOG [$version] ---"
    printf '%s\n' "$notes"
  else
    echo "--- no CHANGELOG section for [$version], would use --generate-notes ---"
  fi
  exit 0
fi

# --target main so the tag is cut from the merge commit that carried the bump,
# regardless of what happens to be checked out.
if [ -n "$notes" ]; then
  printf '%s\n' "$notes" | gh release create "$tag" --target main --title "$tag" --notes-file -
else
  echo "release: no CHANGELOG section for [$version], falling back to generated notes" >&2
  gh release create "$tag" --target main --title "$tag" --generate-notes
fi

echo "release: created $tag"

attach_zips

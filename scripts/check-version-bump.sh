#!/usr/bin/env bash
#
# Fails when the plugin changed but its version didn't.
#
# The marketplace serves this repo's default branch, so the version a consumer
# actually installs is `.claude-plugin/plugin.json` on `main`. Not the tag, not
# the release title. A tag reading v0.2.2 over a plugin.json still reading 0.1.0
# installs as 0.1.0 and the plugin manager reports no update available, so the
# release looks shipped from every angle except the only one that counts.
#
# That is not hypothetical: v0.2.0, v0.2.1 and v0.2.2 were all tagged without
# bumping the field. Three releases installed into a directory named 0.1.0, the
# manager could not tell them apart, and installs sat months behind with nothing
# reporting a problem.
#
# The guarded set is what a consumer actually receives: `skills/`, which is what
# gets zipped, and `.claude-plugin/`, which the manager reads. Docs, CI and the
# release scripts are exempt because none of them reach an install, and bumping
# the version for a README typo would train you to bump it without thinking,
# which is the same failure wearing a different hat.
#
# Usage: scripts/check-version-bump.sh <base-ref>

set -euo pipefail

base="${1:?usage: check-version-bump.sh <base-ref>}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

manifest=".claude-plugin/plugin.json"

# Reads the "version" field without a jq dependency, so this runs the same way
# on a runner and on a laptop that has never installed one.
read_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Three dots: compare against the merge base, so unrelated commits landing on
# main while the PR is open don't count as this PR's changes.
changed="$(git diff --name-only "$base...HEAD" -- skills/ .claude-plugin/ || true)"

if [ -z "$changed" ]; then
  echo "check-version-bump: no change under skills/ or .claude-plugin/, nothing to bump"
  exit 0
fi

new="$(read_version < "$manifest")"
old="$(git show "$base:$manifest" 2>/dev/null | read_version || true)"

if [ -z "$new" ]; then
  echo "check-version-bump: no version field in $manifest" >&2
  exit 1
fi

if [ -z "$old" ]; then
  echo "check-version-bump: $manifest is new in this branch, version $new"
  exit 0
fi

if [ "$old" = "$new" ]; then
  cat >&2 <<EOF
check-version-bump: the plugin changed but its version did not.

  version: $old (unchanged)
  changed:
$(echo "$changed" | sed 's/^/    /')

The marketplace serves plugin.json on the default branch, so shipping this as
$old means every existing install already believes it has these changes and no
update will ever be offered.

Bump "version" in $manifest. Merging that to main is also what cuts the release:
scripts/release.sh derives the tag from this field.
EOF
  exit 1
fi

# Catches a typo'd or accidentally reversed bump. `sort -V` orders versions
# rather than strings, so 0.10.0 sorts above 0.9.0 as it should.
if [ "$(printf '%s\n%s\n' "$old" "$new" | sort -V | head -1)" != "$old" ]; then
  echo "check-version-bump: version went backwards, $old -> $new" >&2
  exit 1
fi

echo "check-version-bump: $old -> $new"

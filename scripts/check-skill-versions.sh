#!/usr/bin/env bash
#
# Fails when a skill's description names a different version from plugin.json.
#
# Each skill's description ends "This copy is claude-phases <version>." so that
# asking Claude which version it has gets an answer from the skill listing, the
# one part of a skill that is always in context. The body is only read once the
# skill is invoked, and invoking phase-driver to answer a question would switch
# that turn to its model. The manifest is no help either: a claude.ai upload is
# the skill directory alone, and Claude Code doesn't show plugin.json to the
# model.
#
# plugin.json stays the one version anyone decides. This makes the copies in
# the descriptions impossible to forget when bumping it, because a description
# that answers with the previous version is worse than one that says nothing.
#
# Usage: scripts/check-skill-versions.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .claude-plugin/plugin.json | head -1)"
[ -n "$version" ] || { echo "check-skill-versions: no version field in .claude-plugin/plugin.json" >&2; exit 1; }

failed=0

for file in skills/*/SKILL.md; do
  description="$(sed -n 's/^description:[[:space:]]*//p' "$file" | head -1)"
  stated="$(printf '%s' "$description" | sed -n 's/.*This copy is claude-phases \([^ ]*\)\.$/\1/p')"

  if [ -z "$stated" ]; then
    echo "$file: description doesn't end \"This copy is claude-phases $version.\"" >&2
    failed=1
  elif [ "$stated" != "$version" ]; then
    echo "$file: description says $stated, plugin.json says $version" >&2
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "check-skill-versions: skill descriptions don't match plugin.json (see above)" >&2
  exit 1
fi

echo "check-skill-versions: every skill says $version"

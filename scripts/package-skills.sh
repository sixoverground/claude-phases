#!/usr/bin/env bash
#
# Builds one zip per skill for upload at claude.ai -> Settings -> Capabilities -> Skills.
#
# That uploader wants a zip whose root is the skill's own directory, so the
# archive must contain `phase-planner/SKILL.md`, not a bare `SKILL.md`. Zipping
# from inside the skill directory produces the latter and the upload is
# rejected, so this zips from `skills/` and names the directory instead.
#
# Usage: scripts/package-skills.sh [output-dir]   (default: dist/)

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v zip >/dev/null || { echo "package-skills: 'zip' is not installed" >&2; exit 1; }

# Resolved to an absolute path before the cd below, so a relative argument
# stays relative to where you ran the script rather than to skills/.
mkdir -p "${1:-$repo_root/dist}"
out_dir="$(cd "${1:-$repo_root/dist}" && pwd)"

cd "$repo_root/skills"

for skill in */; do
  skill="${skill%/}"
  [ -f "$skill/SKILL.md" ] || { echo "package-skills: $skill has no SKILL.md, skipping" >&2; continue; }

  rm -f "$out_dir/$skill.zip"
  # -X drops platform metadata, -r recurses, and the excludes keep editor and
  # Finder droppings out of an archive someone else's account will unpack.
  zip -qrX "$out_dir/$skill.zip" "$skill" -x '*.DS_Store' -x '*/.*'

  echo "$out_dir/$skill.zip"
done

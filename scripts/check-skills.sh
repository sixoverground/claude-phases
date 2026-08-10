#!/usr/bin/env bash
#
# Fails if a skill isn't self-contained.
#
# A skill is uploaded to claude.ai as a zip of its own directory, so anything
# outside that directory does not exist as far as the installed skill is
# concerned. A relative link that climbs out of the skill resolved fine in this
# repo and resolves to nothing once installed, which is the kind of breakage
# that shows up as a model quietly inventing the missing content.
#
# Link out with an absolute URL when it's further reading. Move the file into
# `references/` when the skill needs it to do its job.
#
# Usage: scripts/check-skills.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/skills"

failed=0

while IFS= read -r file; do
  skill="${file%%/*}"

  # Markdown link targets, minus URLs and same-file anchors.
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in
      http*|mailto:*|'#'*) continue ;;
    esac

    path="${target%%#*}"
    [ -n "$path" ] || continue

    resolved="$(cd "$(dirname "$file")" && printf '%s' "$(realpath -m "$path")")"

    case "$resolved" in
      "$repo_root/skills/$skill"/*) ;;
      *) echo "$file: link escapes the skill: $target" >&2; failed=1; continue ;;
    esac

    [ -e "$resolved" ] || { echo "$file: link points at nothing: $target" >&2; failed=1; }
  done < <(grep -o '](\([^)]*\))' "$file" | sed 's/^](//; s/)$//')
done < <(find . -name '*.md' -not -path '*/.*' | sed 's|^\./||')

if [ "$failed" -ne 0 ]; then
  echo "check-skills: skills are not self-contained (see above)" >&2
  exit 1
fi

echo "check-skills: every skill is self-contained"

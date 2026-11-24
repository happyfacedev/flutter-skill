#!/bin/bash
# Register the flutter-skill router + all migrated patterns at user level.
# Idempotent — rerun after adding a pattern to skills/.
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills"
mkdir -p "$DEST"

ln -sfn "$KIT" "$DEST/flutter-skill"
echo "linked flutter-skill"

if [ -d "$KIT/skills" ]; then
  for s in "$KIT"/skills/*/; do
    name="$(basename "$s")"
    # skills/flutter-skill only points the plugin at the root router, linked above.
    [ "$name" = flutter-skill ] && continue
    ln -sfn "${s%/}" "$DEST/$name"
    echo "linked $name"
  done
fi

# Prune user-level symlinks pointing at kit patterns that no longer exist
for link in "$DEST"/*; do
  [ -L "$link" ] || continue
  target="$(readlink "$link")"
  case "$target" in
    "$KIT"/skills/*) [ -d "$target" ] || { rm "$link"; echo "pruned $(basename "$link")"; } ;;
  esac
done

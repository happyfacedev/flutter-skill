#!/bin/bash
# Register the flutter-skill router + the user-run commands at user level.
# Patterns live inside the router's folder and are not registered.
# Idempotent — rerun after adding a skill to skills/.
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills"
mkdir -p "$DEST"

for s in "$KIT"/skills/*/; do
  name="$(basename "$s")"
  ln -sfn "${s%/}" "$DEST/$name"
  echo "linked $name"
done

# Prune user-level symlinks pointing at kit skills that no longer exist
for link in "$DEST"/*; do
  [ -L "$link" ] || continue
  target="$(readlink "$link")"
  case "$target" in
    "$KIT"/skills/*) [ -d "$target" ] || { rm "$link"; echo "pruned $(basename "$link")"; } ;;
  esac
done

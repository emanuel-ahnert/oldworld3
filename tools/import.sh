#!/usr/bin/env bash
# Imports new or changed game assets (Godot doesn't import when running the game). Normal maps
# (*_normal.png) get Godot's normal-map compression, then are imported again.
set -euo pipefail
game=$(cd "$(dirname "$0")/../game" && pwd)
stamp=$game/.godot/.last_import
if [ -f "$stamp" ] && [ -z "$(find "$game/assets" "$game/shaders" "$game/scripts" -newer "$stamp" -print -quit)" ]; then
  exit 0
fi
godot --headless --path "$game" --import >/dev/null 2>&1 || true
changed=0
for f in $(find "$game/assets" -name '*_normal.png.import'); do
  if grep -q '^compress/normal_map=0' "$f"; then
    sed -i 's/^compress\/normal_map=0/compress\/normal_map=1/' "$f"
    changed=1
  fi
done
[ $changed = 1 ] && godot --headless --path "$game" --import >/dev/null 2>&1 || true
mkdir -p "$game/.godot" && touch "$stamp"

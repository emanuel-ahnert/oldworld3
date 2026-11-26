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
# Textures loaded from scripts (terrain, outfits) are never seen in a 3D material by the
# importer, so they stay uncompressed without mipmaps (distant ground: the full 1024 px texture
# per pixel, slow and shimmering). All 3D textures (not the UI's): VRAM compressed, mipmaps.
for f in $(find "$game/assets" -name '*.png.import' -not -path '*/ui/*'); do
  if grep -q '^mipmaps/generate=false' "$f"; then
    sed -i -e 's/^mipmaps\/generate=false/mipmaps\/generate=true/' -e 's/^compress\/mode=[0-9]/compress\/mode=2/' "$f"
    changed=1
  fi
done
[ $changed = 1 ] && godot --headless --path "$game" --import >/dev/null 2>&1 || true
mkdir -p "$game/.godot" && touch "$stamp"

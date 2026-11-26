#!/usr/bin/env bash
# Cuts the generated models down to triangle budgets (tools/pipeline/reduce.py: voxel remesh,
# collapse, new UVs, the color baked over; matte). The generator gave a chest 4k triangles and a
# house up to 20k. In place: the originals are in git (and the generator's output).
# Usage: tools/reduce_models.sh [name ...]   (default: all listed below)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
A=game/assets
# Only the scattered nature (thousands per zone, seen from a distance). Not here: the props and
# the shield (seen up close, the stall's cloth awning got holes, chest and tent smeared); the
# palm's fronds and the dead tree's branches (the voxel rebuild loses thin
# parts); totems, notice board, open chest, the well (they split into shells that don't
# collapse: no smaller); the buildings (seen up close, the baked color showed flecks at the
# windows and corners, and in measurements they cost next to nothing).
# path  triangles  texture px  [voxel=N: grid size as a fraction of the model, finer for thin parts]
LIST="
nature/boulder 700 1024
nature/cactus 900 1024
nature/drybush 1000 1024
nature/shrub 2000 1024
nature/pine1 2500 1024
nature/pine2 2500 1024
nature/darkpine 2500 1024
nature/oak 3000 1024
"
want=("$@")
echo "$LIST" | while read -r path tris px extra; do
  [ -z "$path" ] && continue
  name=$(basename "$path")
  if [ ${#want[@]} -gt 0 ] && [[ ! " ${want[*]} " =~ " $name " ]]; then continue; fi
  f=$A/$path.glb
  [ -f "$f" ] || { echo "missing $f"; continue; }
  blender -b --python tools/pipeline/reduce.py -- "$f" "$f.tmp.glb" "$tris" "$px" $extra 2>&1 \
    | grep -E "REDUCE|Error|Traceback" || true
  [ -f "$f.tmp.glb" ] && mv "$f.tmp.glb" "$f"
done

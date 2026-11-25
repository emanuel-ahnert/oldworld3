#!/usr/bin/env bash
# Puts batch 9 (Ancient Desert) into the game: landmarks and buildings as generated, creatures
# through creature.py / prop.py, the two outfits baked onto the base body. Skips what's missing.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
R=game_src/raw/ancient
A=game/assets
mkdir -p $A/props/ancient
cp_if() { [ -f "$1" ] && cp "$1" "$2" && echo "copied $2"; }
cp_if $R/pyramid.glb $A/props/ancient/pyramid.glb
cp_if $R/obelisk.glb $A/props/ancient/obelisk.glb
cp_if $R/sphinx.glb $A/props/ancient/sphinx.glb
cp_if $R/statue.glb $A/props/ancient/statue.glb
cp_if $R/temple.glb $A/buildings/temple.glb
cp_if $R/house.glb $A/buildings/mudhouse.glb
[ -f $R/scarab.glb ] && blender -b --python tools/pipeline/creature.py -- $R/scarab.glb $A/creatures/scarab.glb 1.3 2>&1 | grep REPORT
# The cobra rears up: it stays upright.
[ -f $R/cobra.glb ] && blender -b --python tools/pipeline/prop.py -- $R/cobra.glb $A/creatures/cobra.glb 1.5 2>&1 | grep REPORT
for n in mummy guardian; do
  [ -f $R/$n.glb ] || continue
  blender -b --python tools/pipeline/outfit.py -- spike/body $R/$n.glb $n 1.85 2>&1 | grep -E "Error|Traceback" || true
  mkdir -p $A/characters/$n
  for k in color mr normal; do cp spike/body/${n}_$k.png $A/characters/$n/${n}_$k.png; done
  echo "baked $n"
done

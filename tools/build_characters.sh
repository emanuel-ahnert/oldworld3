#!/usr/bin/env bash
# Rebuilds the base body (rig, animations, bakes) and bakes every outfit onto it, then copies
# everything into the game (see game_src/manifest.json and design/asset-pipeline.md).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
blender -b --python tools/pipeline/body.py -- spike/models/body_s11.glb spike/body 1.85 2>&1 | grep -E "Error|Traceback" || true
W=game/assets/characters/warrior
cp spike/body/body.glb spike/body/body_color.png spike/body/body_mr.png spike/body/body_normal.png $W/
# Armor layers worn over the body (design/asset-pipeline.md 3.4).
for set in plate_legs plate_shoulders; do
  blender -b --python tools/pipeline/armor.py -- spike/body $set spike/body/$set.glb 2>&1 | grep -E "Error|Traceback" || true
  cp spike/body/$set.glb $W/
done
# The cloth hood with its cape, fitted to the body (worn as the "head" layer).
blender -b --python tools/pipeline/hood_layer.py -- spike/body game_src/raw/gear/hood.glb spike/body/hood_layer.glb 2>&1 | grep -E "Error|Traceback" || true
cp spike/body/hood_layer.glb game/assets/gear/
# outfit name : source model : game folder
for spec in "plate:spike/ctl/knight2_s32.glb:warrior" "bandit:game_src/raw/outfits/bandit.glb:bandit" \
            "goblin:game_src/raw/outfits/goblin.glb:goblin" "mage:game_src/raw/outfits/mage.glb:mage" \
            "troll:game_src/raw/north/troll.glb:troll" "berserker:game_src/raw/north/berserker.glb:berserker" \
            "nomad:game_src/raw/desert/nomad.glb:nomad" "rogue:game_src/raw/desert/rogue.glb:rogue" \
            "priest:game_src/raw/classes/priest.glb:priest" "paladin:game_src/raw/classes/paladin.glb:paladin" \
            "warlock:game_src/raw/classes/warlock.glb:warlock" "hunter:game_src/raw/classes/hunter.glb:hunter" \
            "shaman:game_src/raw/classes/shaman.glb:shaman" "druid:game_src/raw/classes/druid.glb:druid" \
            "corsair:game_src/raw/med/corsair.glb:corsair" "hoplite:game_src/raw/med/hoplite.glb:hoplite" \
            "cultist:game_src/raw/unholy/cultist.glb:cultist" "vampire:game_src/raw/unholy/vampire.glb:vampire" \
            "mummy:game_src/raw/ancient/mummy.glb:mummy" "guardian:game_src/raw/ancient/guardian.glb:guardian" \
            "merchant:game_src/raw/npc/merchant.glb:merchant" "villager:game_src/raw/npc/villager.glb:villager" \
            "villager2:game_src/raw/npc/villager2.glb:villager2"; do
  IFS=: read -r name src dir <<< "$spec"
  [ -f "$src" ] || continue
  # Full plate: misses get a second, longer-reaching bake instead of the body's skin.
  reach=0; [ "$name" = plate ] && reach=0.4
  blender -b --python tools/pipeline/outfit.py -- spike/body "$src" "$name" 1.85 $reach 2>&1 | grep -E "Error|Traceback" || true
  mkdir -p game/assets/characters/$dir
  for k in color mr normal; do cp spike/body/${name}_$k.png game/assets/characters/$dir/${name}_$k.png; done
  if [ "$name" = plate ]; then   # a bake miss on the back plate (design/nightlog.md 61)
    blender -b --python tools/pipeline/fix_plate_back.py -- game/assets/characters/$dir/plate_color.png 2>&1 | grep -E "Error|Traceback" || true
  fi
  echo "baked $name"
done
echo "characters rebuilt"

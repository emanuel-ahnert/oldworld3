#!/usr/bin/env bash
# Night batch 5: outfits for priest, paladin and warlock; a shield.
cd "$(dirname "$0")/raw/classes"
D=../../../spike/control/depth.png
SC="front view, stylized fantasy game character, hand-painted texture style"
N3="flat, 2D, painting, illustration, drawing, sketch, multiple, group, ground, base, pedestal, cropped"
out(){ name=$1; seed=$2; prompt=$3
  gen3d image "$prompt, $SC" --object --control $D --control-scale 0.6 --control-end 0.75 --seed $seed -o ${name}.png -q >/dev/null 2>&1 \
  && gen3d model --image ${name}.png -o ${name}.glb --seed 7 --faces 60000 --texture 2048 -q > ${name}.json 2>&1 && echo "ok $name" || echo "FAIL $name"; }
out priest 1001 "full body human priest in white and gold cloth vestments with a golden sun emblem on the chest, a gold-trimmed sash, white sleeves, soft white boots, short brown hair, no weapon"
out paladin 1011 "full body human paladin in shining silver plate armor with gold trim and a white tabard with a golden sun emblem, steel gauntlets and boots, no helmet, short brown hair, no weapon"
out warlock 1021 "full body human warlock in dark purple and black robes-like tunic with glowing green runes, a hooded cowl thrown back, black leather gloves, dark boots, pale skin, short black hair, no weapon"
gen3d model "3D render of a round wooden shield with an iron rim and a golden sun emblem in the center, front view, game asset, soft studio light" --negative "$N3, sword, person" --seed 1031 --faces 4000 --texture 1024 -o shield.glb -q > shield.json 2>&1 && echo "ok shield" || echo "FAIL shield"
echo BATCH5 DONE

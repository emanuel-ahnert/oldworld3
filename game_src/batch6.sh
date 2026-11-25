#!/usr/bin/env bash
# Night batch 6: hunter, shaman, druid outfits; bear (druid form); totems.
cd "$(dirname "$0")/raw/classes"
D=../../../spike/control/depth.png
SC="front view, stylized fantasy game character, hand-painted texture style"
N3="flat, 2D, painting, illustration, drawing, sketch, multiple, group, ground, base, pedestal, cropped"
S3="three-quarter view, game asset, soft studio light"
out(){ name=$1; seed=$2; prompt=$3
  gen3d image "$prompt, $SC" --object --control $D --control-scale 0.6 --control-end 0.75 --seed $seed -o ${name}.png -q >/dev/null 2>&1 \
  && gen3d model --image ${name}.png -o ${name}.glb --seed 7 --faces 60000 --texture 2048 -q > ${name}.json 2>&1 && echo "ok $name" || echo "FAIL $name"; }
mdl(){ gen3d model "$2" --negative "$N3" --seed $3 --faces $4 --texture 1024 -o $1.glb -q > $1.json 2>&1 && echo "ok $1" || echo "FAIL $1"; }
out hunter 1101 "full body human hunter ranger in green and brown leather armor with a mail shirt underneath, a quiver strap across the chest, leather bracers, a brown cloak on the shoulders, tall leather boots, short brown hair, no weapon"
out shaman 1111 "full body human shaman in blue and brown mail and leather armor with bone and feather ornaments, a wolf pelt on the shoulders, tribal tattoos on the arms, leather boots, braided dark hair, no weapon"
out druid 1121 "full body human druid in green and brown leaf-patterned leather robes-like tunic with a cloak of leaves on the shoulders, wooden antler ornaments, bare forearms, soft leather boots, long brown hair, no weapon"
mdl bear "3D render of a big brown grizzly bear standing on all four legs, side three-quarter view, full body, stylized fantasy game creature, $S3" 1131 8000
mdl totem_wrath "3D render of a carved wooden tribal totem pole with a fierce red painted face and feathers on top, $S3" 1141 4000
mdl totem_healing "3D render of a carved wooden tribal totem pole with a calm blue painted face and a water drop symbol, $S3" 1142 4000
echo BATCH6 DONE

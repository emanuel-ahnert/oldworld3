#!/usr/bin/env bash
# Night batch 10: village people (merchant, villagers).
cd "$(dirname "$0")/raw"
T="seen from directly above, top down, flat even lighting, no shadows, stylized game texture, seamless tileable"
N3="flat, 2D, painting, illustration, drawing, sketch, multiple, group, ground, base, pedestal, cropped"
S3="three-quarter view, game asset, soft studio light"
D=../../spike/control/depth.png
SC="front view, stylized fantasy game character, hand-painted texture style"
img(){ gen3d image "$2" --negative "${3:-}" --seed $4 -o $1.png -q >/dev/null 2>&1 && echo "ok $1" || echo "FAIL $1"; }
mdl(){ gen3d model "$2" --negative "$N3" --seed $3 --faces $4 --texture 1024 -o $1.glb -q > $1.json 2>&1 && echo "ok $1" || echo "FAIL $1"; }
out(){ name=$1; seed=$2; prompt=$3
  gen3d image "$prompt, $SC" --object --control $D --control-scale 0.6 --control-end 0.75 --seed $seed -o ${name}.png -q >/dev/null 2>&1 \
  && gen3d model --image ${name}.png -o ${name}.glb --seed 7 --faces 60000 --texture 2048 -q > ${name}.json 2>&1 && echo "ok $name" || echo "FAIL $name"; }
out npc/merchant 1601 "full body medieval merchant with a green wool tunic, a brown leather apron, a belt with a coin purse, brown trousers and leather shoes, short brown beard, no hat, no weapon"
out npc/villager 1602 "full body medieval peasant farmer with a loose undyed linen shirt, a brown wool vest, rope belt, patched grey trousers and simple leather boots, no hat, no weapon"
out npc/villager2 1603 "full body medieval townsman with a blue wool tunic with a hood down, a brown belt, dark green trousers and brown boots, short blond hair, no weapon"
mdl ancient/statue "3D render of a seated pharaoh statue of sandstone on a block throne, hands on the knees, nemes headdress, compact, whole statue visible, $S3" 1507 8000
echo BATCH10 DONE

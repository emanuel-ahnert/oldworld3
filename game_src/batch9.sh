#!/usr/bin/env bash
# Night batch 9: the Ancient Desert (Egyptian; Oldworld2 design/world.md 2.3.4).
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
mdl ancient/pyramid "3D render of an ancient egyptian sandstone pyramid with smooth sloped sides and a dark entrance at the base, $S3" 1501 6000
mdl ancient/obelisk "3D render of a single tall ancient egyptian sandstone obelisk with carved hieroglyphs, $S3" 1502 3000
mdl ancient/sphinx "3D render of an ancient egyptian sandstone sphinx statue lying on its belly, $S3" 1503 10000
mdl ancient/temple "3D render of a small ancient egyptian sandstone temple with massive painted columns and a flat roof, $S3" 1504 12000
mdl ancient/house "3D render of a small flat-roofed egyptian mud brick house with a doorway and small windows, $S3" 1505 8000
mdl ancient/statue "3D render of a tall standing pharaoh statue of sandstone with a nemes headdress, arms crossed, $S3" 1506 8000
mdl ancient/scarab "3D render of a giant golden-green scarab beetle standing on six legs, side three-quarter view, full body, stylized fantasy game creature, $S3" 1511 6000
mdl ancient/cobra "3D render of a giant cobra snake rearing up with an open hood, full body, stylized fantasy game creature, $S3" 1512 6000
out ancient/mummy 1521 "full body egyptian mummy wrapped completely in dirty yellowed linen bandages, bandaged head, dark eye sockets, no weapon"
out ancient/guardian 1522 "full body egyptian tomb guardian warrior with bronze skin, a broad golden collar, a white linen kilt with a golden belt, golden arm bands, a blue and gold striped nemes headdress, no weapon"
echo BATCH9 DONE

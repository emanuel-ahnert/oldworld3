#!/usr/bin/env bash
# Night batch 7: Mediterranean and Unholy zones.
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
# Mediterranean
img med/grass "close-up texture of dry golden summer grass with a few small wildflowers, $T" "stones, rocks, objects, text" 1201
img med/path "close-up texture of a pale limestone dirt path with small white pebbles, $T" "objects, text, cobblestones" 1202
mdl med/olive "3D render of a gnarled old olive tree with a twisted silver-grey trunk and a round silvery-green crown, $S3" 1211 9000
mdl med/cypress "3D render of a tall slender dark green italian cypress tree, $S3" 1212 6000
mdl med/lavender "3D render of a small round lavender bush with purple flowers, $S3" 1213 3000
mdl med/crab "3D render of a giant red crab with big claws, side three-quarter view, full body, stylized fantasy game creature, $S3" 1221 8000
mdl med/windspirit "3D render of a floating swirling air spirit made of pale blue wind and clouds, stylized fantasy game creature, $S3" 1222 4000
mdl med/whitehouse "3D render of a small whitewashed greek island house with a blue dome and blue door and shutters, $S3" 1231 10000
mdl med/villa "3D render of a mediterranean villa with terracotta tiled roof and a columned porch, $S3" 1232 14000
out med/corsair 1241 "full body pirate corsair with a red bandana, a white loose shirt, a brown leather vest, a wide sash belt, dark trousers and tall boots, no weapon"
out med/hoplite 1242 "full body greek hoplite soldier in bronze cuirass and bronze greaves over a red tunic, leather pteruges skirt strips, no helmet, short dark curly hair, no weapon"
# Unholy
img unholy/grass "close-up texture of dead withered grey-brown grass and dark soil, $T" "stones, objects, text" 1301
img unholy/path "close-up texture of dark wet muddy path with small black stones, $T" "objects, text" 1302
mdl unholy/deadtree "3D render of a dead twisted leafless tree with black bark and gnarled branches, $S3" 1311 7000
mdl unholy/darkpine "3D render of a tall dark gloomy pine tree with nearly black needles, conical shape, $S3" 1312 8000
mdl unholy/gravestone "3D render of an old weathered mossy stone gravestone with a rounded top, $S3" 1313 2000
mdl unholy/direwolf "3D render of a black dire wolf with glowing red eyes standing on all four legs, side three-quarter view, full body, stylized fantasy game creature, $S3" 1321 8000
mdl unholy/bats "3D render of a swarm of black bats flying together in a cluster, stylized fantasy game creature, $S3" 1322 5000
mdl unholy/gothichouse "3D render of a small gothic house of dark stone with a steep slate roof and a corner turret, warm lit windows, $S3" 1331 12000
mdl unholy/crypt "3D render of a small stone crypt mausoleum with a pointed arch door, $S3" 1332 8000
out unholy/cultist 1341 "full body dark cultist in long black and blood red robes-like tunic with occult symbols, a hood thrown back, pale skin, bald head, bare hands, no weapon"
out unholy/vampire 1342 "full body vampire noble in an elegant black and crimson coat with a high collar, a dark waistcoat, black trousers and boots, pale skin, slicked black hair, no weapon"
echo BATCH7 DONE

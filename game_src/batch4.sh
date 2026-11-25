#!/usr/bin/env bash
# Night batch 4: the Desert zone and the rogue outfit.
cd "$(dirname "$0")/raw/desert"
T="seen from directly above, top down, flat even lighting, no shadows, stylized game texture, seamless tileable"
N3="flat, 2D, painting, illustration, drawing, sketch, multiple, group, ground, base, pedestal, cropped"
S3="three-quarter view, game asset, soft studio light"
D=../../../spike/control/depth.png
SC="front view, stylized fantasy game character, hand-painted texture style"
img(){ gen3d image "$2" --negative "${3:-}" --seed $4 -o $1.png -q >/dev/null 2>&1 && echo "ok $1" || echo "FAIL $1"; }
mdl(){ gen3d model "$2" --negative "$N3" --seed $3 --faces $4 --texture 1024 -o $1.glb -q > $1.json 2>&1 && echo "ok $1" || echo "FAIL $1"; }
img sand "close-up texture of fine golden desert sand with soft wind ripples, $T" "rocks, plants, footprints, objects, text" 901
img sandpath "close-up texture of a packed pale sandstone path with small flat stones and fine sand, $T" "plants, objects, text" 902
img desertrock "close-up texture of red-orange layered sandstone rock with cracks, $T" "plants, objects, text" 903
mdl palm "3D render of a tall date palm tree with a curved trunk and a crown of green fronds, $S3" 911 8000
mdl cactus "3D render of a tall green saguaro cactus with two arms, $S3" 912 3000
mdl drybush "3D render of a small dry desert shrub with thin brown branches, $S3" 913 3000
mdl scorpion "3D render of a giant desert scorpion with raised tail and pincers, side three-quarter view, full body, stylized fantasy game creature, $S3" 921 8000
mdl sandsnake "3D render of a coiled sand-colored desert snake raising its head, stylized fantasy game creature, $S3" 922 6000
mdl ember "3D render of a floating fire spirit made of glowing embers and flames, stylized fantasy game creature, $S3" 923 4000
mdl domehouse "3D render of a small desert mud-brick house with a white dome roof and a wooden door, $S3" 931 10000
mdl sandinn "3D render of a two-story sandstone desert inn with arched windows, wooden balconies and a flat roof with a cloth awning, $S3" 932 16000
for s in 941 942; do gen3d image "full body desert nomad raider in flowing sand-colored robes over leather armor, a red sash, a desert head wrap around the head and lower face, cloth wrapped arms, leather boots, no weapon, $SC" --object --control $D --control-scale 0.6 --control-end 0.75 --seed $s -o nomad_s$s.png -q >/dev/null 2>&1 && echo "ok nomad $s"; done
for s in 951 952; do gen3d image "full body rogue assassin in dark grey and black fitted leather armor with many straps and buckles, a dark hood thrown back, a short dark cape on the shoulders, leather gloves, soft boots, short dark hair, no weapon, $SC" --object --control $D --seed $s -o rogue_s$s.png -q >/dev/null 2>&1 && echo "ok rogue $s"; done
echo BATCH4 DONE

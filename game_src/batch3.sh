#!/usr/bin/env bash
# Night batch 3: the North zone (snow, pines, snow wolf, longhouse, troll and berserker outfits).
cd "$(dirname "$0")/raw/north"
T="seen from directly above, top down, flat even lighting, no shadows, stylized game texture, seamless tileable"
N3="flat, 2D, painting, illustration, drawing, sketch, multiple, group, ground, base, pedestal, cropped"
S3="three-quarter view, game asset, soft studio light"
D=../../../spike/control/depth.png
SC="front view, stylized fantasy game character, hand-painted texture style"
img(){ gen3d image "$2" --negative "${3:-}" --seed $4 -o $1.png -q >/dev/null 2>&1 && echo "ok $1" || echo "FAIL $1"; }
mdl(){ gen3d model "$2" --negative "$N3" --seed $3 --faces $4 --texture 1024 -o $1.glb -q > $1.json 2>&1 && echo "ok $1" || echo "FAIL $1"; }
img snow1 "close-up texture of fresh white snow with soft drifts and a few footprints-free sparkles, $T" "rocks, grass, footprints, objects, text" 801
img snow2 "close-up texture of packed white snow with small icy crystals and subtle blue shadows, $T" "rocks, grass, footprints, objects, text" 802
img ice "close-up texture of a frozen lake surface, blue-white ice with cracks and frost, $T" "objects, text" 803
mdl pine1 "3D render of a tall straight snowy pine tree with dark green needles and snow on the branches, conical shape, $S3" 811 9000
mdl pine2 "3D render of a slender young fir tree covered in snow, conical shape, $S3" 812 7000
mdl snowwolf "3D render of a white snow wolf standing on all four legs, side three-quarter view, full body, stylized fantasy game creature, $S3" 821 8000
mdl longhouse "3D render of a nordic viking timber longhouse with a steep snowy roof and carved dragon gable ends, $S3" 831 16000
mdl wisp "3D render of a floating icy blue glowing frost spirit wisp made of ice crystals, $S3" 841 4000
for s in 851 852; do gen3d image "full body huge ice troll with pale blue skin, tusks, long white hair, wearing a fur loincloth and bone necklace, bare chest, $SC" --object --control $D --control-scale 0.55 --control-end 0.7 --seed $s -o troll_s$s.png -q >/dev/null 2>&1 && echo "ok troll $s"; done
for s in 861 862; do gen3d image "full body nordic berserker warrior with a bare muscular chest painted with blue runes, wearing a bear fur cloak on the shoulders, fur trousers, leather bracers, fur boots, wild red braided beard and hair, $SC" --object --control $D --control-scale 0.6 --control-end 0.75 --seed $s -o berserker_s$s.png -q >/dev/null 2>&1 && echo "ok berserker $s"; done
echo BATCH3 DONE

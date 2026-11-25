#!/usr/bin/env bash
# Batch 14: leather cowl (replaces the open cap, which showed the hair).
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
mdl gear/cowl "medieval brown leather cowl hood covering the head and neck with an open face, stitched leather panels, empty, stylized fantasy game asset, hand-painted texture style" 1904 7000
echo BATCH14 DONE

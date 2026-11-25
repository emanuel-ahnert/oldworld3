#!/usr/bin/env bash
# Night batch 8: fixes (cypress, lavender) and inn props (notice board, market stall).
cd "$(dirname "$0")/raw"
T="seen from directly above, top down, flat even lighting, no shadows, stylized game texture, seamless tileable"
N3="flat, 2D, painting, illustration, drawing, sketch, multiple, group, ground, base, pedestal, cropped"
S3="three-quarter view, game asset, soft studio light"
D=../../spike/control/depth.png
SC="front view, stylized fantasy game character, hand-painted texture style"
img(){ gen3d image "$2" --negative "${3:-}" --seed $4 -o $1.png -q >/dev/null 2>&1 && echo "ok $1" || echo "FAIL $1"; }
mdl(){ gen3d model "$2" --negative "$N3" --seed $3 --faces $4 --texture 1024 -o $1.glb -q > $1.json 2>&1 && echo "ok $1" || echo "FAIL $1"; }
mdl med/cypress2 "3D render of a single very tall and very narrow columnar italian cypress tree shaped like a slim dark green flame, dense foliage from bottom to top, $S3" 1214 6000
mdl med/lavender2 "3D render of a low round lavender shrub with many purple flower spikes growing directly from the soil, no pot, no planter, $S3" 1215 3000
mdl props/noticeboard "3D render of a medieval wooden village notice board on two posts with a small shingle roof and pinned paper notes, $S3" 1401 5000
mdl props/stall "3D render of a medieval market stall with a wooden counter, a striped red and white cloth awning and crates of goods, $S3" 1402 8000
mdl unholy/bats "3D render of a single giant black vampire bat with leathery wings spread wide, small compact body, stylized fantasy game creature, $S3" 1323 5000
echo BATCH8 DONE

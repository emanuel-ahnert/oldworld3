#!/usr/bin/env bash
# Night batch 1: enemies, buildings, props (see design/nightlog.md).
cd "$(dirname "$0")/raw"
N3="flat, 2D, painting, illustration, drawing, sketch, multiple, group, ground, grass, base, pedestal, cropped"
m(){ out=$1; shift; gen3d model "$@" -q > ${out%.glb}.json 2>&1 && echo "ok $out" || echo "FAIL $out"; }
m enemies/wolf.glb "3D render of a grey wolf standing on all four legs, side three-quarter view, full body, stylized fantasy game creature, game asset, soft studio light" --negative "$N3, sitting, lying, howling" --seed 601 --faces 8000 --texture 1024 -o enemies/wolf.glb
m enemies/boar.glb "3D render of a wild boar with tusks standing on all four legs, side three-quarter view, full body, stylized fantasy game creature, game asset, soft studio light" --negative "$N3, lying" --seed 611 --faces 8000 --texture 1024 -o enemies/boar.glb
m buildings/inn.glb "3D render of a medieval two-story timber-framed inn with white plaster walls, dark wooden beams, a steep thatched roof and a stone chimney, three-quarter view, stylized fantasy game asset, soft studio light" --negative "$N3, town, street, people" --seed 701 --faces 20000 --texture 2048 -o buildings/inn.glb
m buildings/house1.glb "3D render of a small medieval cottage with stone walls, a wooden door and a red tiled roof, three-quarter view, stylized fantasy game asset, soft studio light" --negative "$N3, town, street, people" --seed 711 --faces 12000 --texture 1024 -o buildings/house1.glb
m buildings/house2.glb "3D render of a small medieval timber-framed house with white plaster walls, dark beams and a thatched roof, three-quarter view, stylized fantasy game asset, soft studio light" --negative "$N3, town, street, people" --seed 721 --faces 12000 --texture 1024 -o buildings/house2.glb
m buildings/shrine.glb "3D render of a small stone wayside shrine with a glowing blue crystal on top, mossy stones, three-quarter view, stylized fantasy game asset, soft studio light" --negative "$N3, people" --seed 731 --faces 6000 --texture 1024 -o buildings/shrine.glb
m buildings/tent.glb "3D render of a small brown canvas camping tent, three-quarter view, stylized fantasy game asset, soft studio light" --negative "$N3, people, campfire" --seed 741 --faces 4000 --texture 1024 -o buildings/tent.glb
m buildings/campfire.glb "3D render of a campfire with logs arranged in a ring of stones, unlit, three-quarter view, stylized fantasy game asset, soft studio light" --negative "$N3, people, flames, smoke" --seed 751 --faces 3000 --texture 1024 -o buildings/campfire.glb
m buildings/crate.glb "3D render of a wooden crate with iron corners, three-quarter view, stylized fantasy game asset, soft studio light" --negative "$N3" --seed 761 --faces 1500 --texture 512 -o buildings/crate.glb
m buildings/well.glb "3D render of a medieval stone well with a small wooden roof and a bucket, three-quarter view, stylized fantasy game asset, soft studio light" --negative "$N3, people" --seed 771 --faces 6000 --texture 1024 -o buildings/well.glb
echo BATCH1 DONE

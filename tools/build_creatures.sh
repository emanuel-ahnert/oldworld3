#!/bin/bash
# Rigs and animates the creatures (tools/pipeline/creature_rig.py): game/assets/creatures/<name>.glb
# (static, from creature.py) -> <name>_rig.glb + <name>_rig.json (walk/run speeds).
# The game prefers the _rig model (scripts/enemies/enemy.gd). Floating creatures (wisp, ember,
# wind spirit, bats) stay procedural.
# Usage: tools/build_creatures.sh [name ...]   (default: all)
set -e
cd "$(dirname "$0")/.."
D=game/assets/creatures
declare -A ARGS=(
  [wolf]="quad style=bite"
  [direwolf]="quad style=bite"
  [snowwolf]="quad style=bite"
  [boar]="quad style=gore"
  [bear]="quad style=swipe lie=side"
  [crab]="bug limbs=10 claws=2 turn=90 core=0.42 spread=50"
  [spider]="bug limbs=8 turn=90"
  [scorpion]="bug limbs=11 claws=2 tail=1"
  [scarab]="bug limbs=6"
  [cobra]="snake"
  [sandsnake]="snake"
)
names=("$@")
[ ${#names[@]} -eq 0 ] && names=("${!ARGS[@]}")
for n in "${names[@]}"; do
  echo "== $n: ${ARGS[$n]}"
  blender -b --python tools/pipeline/creature_rig.py -- $D/$n.glb $D/${n}_rig.glb ${ARGS[$n]} 2>&1 \
    | grep -E "QUAD|BUG|SNAKE|SPEEDS|Traceback|Error" || true
done

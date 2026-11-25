#!/usr/bin/env bash
# Builds the procedural trees (tools/pipeline/tree.py) into the game: the grassland's beech,
# linden and birch, the Mediterranean's olive and cypress. Generated tree models had leaves
# floating without twigs (the old ones: git history at v0.2.0).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
for sp in beech linden birch olive cypress bush; do
  blender -b --python tools/pipeline/tree.py -- $sp game/assets/nature/$sp.glb 2>&1 | grep -E "Error|Traceback|TREE" || true
done

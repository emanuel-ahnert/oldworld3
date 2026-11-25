#!/usr/bin/env bash
# Retakes the README's screenshots (docs/screenshots/*.jpg): every class, every zone, most of
# them in a fight. Each shot is a scripted test run (tools/shot.sh: a hidden workspace, High
# quality at native resolution), saved as a 1280 px JPEG. Needs ImageMagick.
#   tools/screenshots.sh            all of them
#   tools/screenshots.sh NAME...    only these
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/docs/screenshots
raw=${TMPDIR:-/tmp}/oldworld3-shots
mkdir -p "$out" "$raw"

# name | frame | game arguments (the caption lives in README.md)
SHOTS=$(cat <<'EOF'
warrior-whirlwind|325|--class warrior --level 12 --start grassland --fight wolf --whirl --press-at 300 --cam-yaw 30 --zoom 5
mage-blizzard|235|--class mage --level 8 --start desert --fight scorpion --hold 14 --nobot --slot6 blizzard --press 6 --press-at 150 --cam-yaw 320 --zoom 9
warlock-hellfire|208|--class warlock --level 8 --start grassland --fight wolf --hold 16 --nobot --press 4 --press-at 150 --cam-yaw 300 --zoom 12
hunter-crabs|170|--class hunter --level 6 --start mediterranean --fight crab --hold 12 --cam-yaw 20 --zoom 5
paladin-hoplites|300|--class paladin --level 8 --start mediterranean --fight hoplite --cam-yaw 40 --zoom 6.5
rogue-bandits|300|--class rogue --level 6 --start grassland --fight bandit --cam-yaw 40 --zoom 6
priest-ancient|185|--class priest --level 5 --start ancient --fight mummy --hold 12 --nobot --press 1 --press-at 150 --cam-yaw 60 --zoom 5
shaman-north|150|--class shaman --level 4 --start north --fight ice_troll --cam-yaw 35 --zoom 6
druid-moonbeam|204|--class druid --level 8 --start mediterranean --fight crab --hold 10 --nobot --press 5 --press-at 150 --cam-yaw 330 --zoom 6
hunter-nomads|150|--class hunter --level 6 --start desert --fight nomad --hold 16 --cam-yaw 15 --zoom 6
mage-fireball|213|--class mage --level 10 --start ancient --fight scarab --hold 15 --nobot --slot6 fireball --press 6 --press-at 150 --cam-yaw 70 --zoom 5.5
druid-bear|320|--class druid --level 8 --start grassland --fight boar --cam-yaw 40 --zoom 6.5
warlock-unholy|240|--class warlock --level 8 --start unholy --fight bat_swarm --hold 10 --cam-yaw 20 --zoom 5 --time 0.5
camp-grassland|200|--class paladin --level 4 --start grassland --camp --no-enemies --time 0.72 --cam-yaw 120 --zoom 4
graveyard-unholy|150|--class priest --level 4 --start unholy --no-enemies --time 0.5 --pos 505,-75 --cam-yaw 180 --zoom 4
village-mediterranean|150|--class priest --level 3 --start mediterranean --no-enemies --cam-yaw 200 --zoom 9 --time 0.35
north-road|150|--class rogue --level 3 --start north --no-enemies --autowalk --cam-yaw 160 --zoom 8 --time 0.3
world-map|150|--class mage --level 8 --start grassland --no-enemies --map
EOF
)

want=" $* "
while IFS='|' read -r name frame args; do
  [ -z "$name" ] && continue
  if [ $# -gt 0 ] && [[ "$want" != *" $name "* ]]; then continue; fi
  echo "== $name"
  # shellcheck disable=SC2086
  "$root/tools/shot.sh" "$raw/$name.png" "$frame" --mute --quality High --scale 1.0 --gear rare --nohelp $args \
    | grep -E '^(ok|STATE|FIGHT)|SCRIPT ERROR' || true
  [ -f "$raw/$name.png" ] && magick "$raw/$name.png" -resize 1280x -quality 85 "$out/$name.jpg" && echo "-> docs/screenshots/$name.jpg"
done <<< "$SHOTS"

#!/usr/bin/env bash
# Scripted test run: the game opens on a hidden Hyprland workspace (never takes focus), waits
# N frames, saves a screenshot and quits.
#   tools/shot.sh out.png [frames] [game args...]
#   tools/shot.sh /tmp/a.png 200 --autowalk --cam-yaw 40
set -euo pipefail
out=$(realpath -m "${1:?usage: shot.sh out.png [frames] [game args...]}")
frame=${2:-120}
shift $(( $# < 2 ? $# : 2 ))
root=$(cd "$(dirname "$0")/.." && pwd)
game=$root/game

tools_dir=$(dirname "$0")
"$tools_dir/import.sh"

# Test runs get their own window class (through override.cfg), so the run rule for
# workspace 9 never matches them.
printf '[application]\nconfig/name="Oldworld3 test"\n[display]\nwindow/size/mode=0\n' > "$game/override.cfg"
trap 'rm -f "$game/override.cfg"' EXIT
if command -v hyprctl >/dev/null; then
  hyprctl eval 'hl.window_rule({ name = "oldworld3-test", match = { class = "^Oldworld3 test$" }, workspace = "special:oldworld silent", no_initial_focus = true })' >/dev/null
fi
rm -f "$out"
# A run from the source defaults to Low (GameMenu.default_quality); tests render at Medium
# unless they ask for a quality (--quality Low|Medium|High).
case " $* " in *" --quality "*) ;; *) set -- "$@" --quality Medium ;; esac
timeout ${SHOT_TIMEOUT:-180} godot --path "$game" -- --shot "$out" --frame "$frame" "$@" 2>&1 | grep -vE '^(Godot Engine|Vulkan|$)' || true
[ -f "$out" ] && echo "ok: $out"

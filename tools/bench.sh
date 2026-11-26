#!/usr/bin/env bash
# Frame rate benchmark on the hidden workspace: the hero runs forward for N seconds with vsync
# off, the game prints the average FPS.
#   tools/bench.sh [seconds] [forward_plus|mobile] [game args...]
#   tools/bench.sh 15 mobile --scale 1.0
set -euo pipefail
secs=${1:-15}; renderer=${2:-}
shift $(( $# < 2 ? $# : 2 ))
root=$(cd "$(dirname "$0")/.." && pwd)
game=$root/game
{
  printf '[application]\nconfig/name="Oldworld3 test"\n[display]\nwindow/size/mode=0\n'
  [ -n "${FXAA:-}" ] && printf "[rendering]\nanti_aliasing/quality/screen_space_aa=1\n"
  [ -n "${MSAA:-}" ] && printf "[rendering]\nanti_aliasing/quality/msaa_3d=%s\n" "$MSAA"
  [ -n "$renderer" ] && printf '[rendering]\nrenderer/rendering_method="%s"\n' "$renderer"
} > "$game/override.cfg"
trap 'rm -f "$game/override.cfg"' EXIT
hyprctl eval 'hl.window_rule({ name = "oldworld3-test", match = { class = "^Oldworld3 test$" }, workspace = "special:oldworld silent", no_initial_focus = true })' >/dev/null
timeout $((secs + 60)) godot --path "$game" -- --bench "$secs" "$@" 2>&1 | grep -E "BENCH|ERROR" || true

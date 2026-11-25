#!/usr/bin/env bash
# Starts Oldworld3 fullscreen on workspace 9 (Hyprland). Used by the VS Code launch
# configuration "Oldworld3 (desktop 9, fullscreen)". Extra arguments go to the game,
# e.g. tools/run.sh --seed 2 (see game/scripts/main.gd).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
game=$root/game

tools_dir=$(dirname "$0")
"$tools_dir/import.sh"

if command -v hyprctl >/dev/null; then
  # Godot on Wayland uses the project name as the window class. A named rule replaces
  # itself on every start instead of piling up.
  # OLDWORLD3_WORKSPACE overrides the target (e.g. "special:oldworld silent" for tests).
  ws=${OLDWORLD3_WORKSPACE:-9}
  hyprctl eval "hl.window_rule({ name = \"oldworld3-run\", match = { class = \"^Oldworld3\$\" }, workspace = \"$ws\", fullscreen = true })" >/dev/null
fi
exec godot --path "$game" --fullscreen -- "$@"

#!/usr/bin/env bash
# Builds the release: one self-contained executable per platform, the game data embedded
# (Godot export, game/export_presets.cfg): dist/oldworld3-<version>-windows-x86_64.exe and
# dist/oldworld3-<version>-linux-x86_64. Download and run; nothing to unpack. Needs the Godot 4.7.2 export templates
# (Editor → Manage Export Templates, or the official templates .tpz unpacked into
# ~/.local/share/godot/export_templates/4.7.2.stable/).
#   tools/release.sh            # version from game/project.godot (config/version)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
version=$(sed -nE 's/^config\/version="([^"]+)"/\1/p' game/project.godot)
[ -n "$version" ] || { echo "no config/version in game/project.godot" >&2; exit 1; }
"$root/tools/import.sh"
rm -rf dist
mkdir -p dist
godot --headless --path game --export-release "Linux" "../dist/oldworld3-$version-linux-x86_64"
godot --headless --path game --export-release "Windows" "../dist/oldworld3-$version-windows-x86_64.exe"
chmod +x "dist/oldworld3-$version-linux-x86_64"
ls -lh dist/oldworld3-*

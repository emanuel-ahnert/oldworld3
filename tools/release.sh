#!/usr/bin/env bash
# Builds the release: one executable per platform with the game data inside (Godot export,
# game/export_presets.cfg), packed as dist/oldworld3-<version>-linux-x86_64.tar.gz and
# dist/oldworld3-<version>-windows-x86_64.zip. Needs the Godot 4.7.2 export templates
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
mkdir -p dist/oldworld3-linux-x86_64 dist/oldworld3-windows-x86_64
godot --headless --path game --export-release "Linux" ../dist/oldworld3-linux-x86_64/oldworld3.x86_64
godot --headless --path game --export-release "Windows" ../dist/oldworld3-windows-x86_64/oldworld3.exe
for d in linux windows; do cp README.md "dist/oldworld3-$d-x86_64/"; done
tar -C dist -czf "dist/oldworld3-$version-linux-x86_64.tar.gz" oldworld3-linux-x86_64
(cd dist && zip -qr "oldworld3-$version-windows-x86_64.zip" oldworld3-windows-x86_64)
ls -lh dist/*.tar.gz dist/*.zip

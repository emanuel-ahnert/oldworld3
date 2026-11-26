#!/usr/bin/env bash
# Generated music takes (ACE-Step, tools/audio/prompts) into the game: each chosen take
# leveled to the same loudness (-18 LUFS, peaks under -1 dB), a short fade-in and a longer
# fade-out (the game plays another take of the same track after one ends, scripts/audio.gd),
# as game/assets/audio/music/<track>.ogg, <track>_2.ogg, ... in the order given.
#   tools/audio/master_music.sh <takes_dir> <track>:<take>[,<take>...] ...
#   tools/audio/master_music.sh /tmp/music1 grassland:1,2,3 fight:1,2
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
src=$1; shift
out=$root/game/assets/audio/music
for spec in "$@"; do
  track=${spec%%:*}
  takes=${spec#*:}
  i=0
  # Earlier variants of this track go (fewer takes chosen now).
  rm -f "$out/${track}_"[0-9].ogg "$out/${track}_"[0-9].ogg.import
  for t in ${takes//,/ }; do
    i=$((i + 1))
    f=$(ls "$src/${track}_$t".flac "$src/${track}_$t".wav 2>/dev/null | head -1 || true)
    [ -n "$f" ] || { echo "missing $src/${track}_$t"; continue; }
    name=$track; [ $i -gt 1 ] && name=${track}_$i
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
    fo=$(python3 -c "print(max(0.0, $dur - 4.0))")
    ffmpeg -loglevel error -y -i "$f" \
      -af "loudnorm=I=-18:TP=-1.5:LRA=14,afade=t=in:d=1.5,afade=t=out:st=$fo:d=4,aresample=48000" \
      -c:a libvorbis -q:a 5 "$out/$name.ogg"
    echo "$name.ogg <- $(basename "$f")"
  done
done

#!/usr/bin/env bash
# Generates the ability, passive and effect icons with SDXL on the GPU box (gen3d image) from
# tools/icons/prompts.txt, three jobs at a time, into game/assets/ui/icons/<id>.png (128 px).
# The full-size images stay in tools/icons/out/ (not in git) for picking and redoing.
# Usage: tools/icons/make_icons.sh [id ...]   (default: all; existing ones are skipped unless named)
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=tools/icons/out
dst=game/assets/ui/icons
mkdir -p "$out" "$dst"
# The subject comes first ("game icon of ...") and the style after, kept short: with the long
# style first SDXL drew the style and lost the subject (Battle Horn without a horn).
STYLE="hand-painted fantasy game icon, comic-book style with thick dark outlines, vivid saturated colors, soft radial glow behind the subject, high contrast"
NEG="person, people, character, man, woman, figure, face, body, hands, armor, ornament, ornate frame, medallion, emblem, circular frame, border, frame, text, letters, words, watermark, signature, multiple icons, grid, collage, photo, photorealistic, blurry, plain grey background, white background, low quality"
want=("$@")
jobs_running=0
grep -v '^#' tools/icons/prompts.txt | grep '|' | while IFS='|' read -r id motif; do
  # Trimmed with bash (xargs choked on the apostrophe in "hunter's").
  id="${id#"${id%%[![:space:]]*}"}"; id="${id%"${id##*[![:space:]]}"}"
  motif="${motif#"${motif%%[![:space:]]*}"}"; motif="${motif%"${motif##*[![:space:]]}"}"
  if [ ${#want[@]} -gt 0 ]; then
    [[ " ${want[*]} " =~ " $id " ]] || continue
  elif [ -f "$dst/$id.png" ]; then
    continue
  fi
  (
    seed=$(( ($(echo -n "$id" | cksum | cut -d' ' -f1) + ${SEED_SHIFT:-0}) % 100000 ))
    if [ -n "${VARIANT:-}" ]; then
      # A variant to compare (VARIANT=b SEED_SHIFT=…): only the full-size image, nothing installed.
      gen3d image "game icon of $motif, $STYLE" --negative "$NEG" --seed "$seed" -o "$out/${id}_$VARIANT.png" > "$out/${id}_$VARIANT.log" 2>&1 \
        && echo "VARIANT $id $VARIANT" || echo "FAIL $id"
    else
      gen3d image "game icon of $motif, $STYLE" --negative "$NEG" --seed "$seed" -o "$out/$id.png" > "$out/$id.log" 2>&1 \
        && magick "$out/$id.png" -resize 128x128 "$dst/$id.png" && echo "ICON $id" || echo "FAIL $id"
    fi
  ) &
  jobs_running=$((jobs_running + 1))
  if [ $jobs_running -ge 3 ]; then wait -n; jobs_running=$((jobs_running - 1)); fi
done
wait

#!/usr/bin/env bash
# Night batch 2: bandit and goblin outfits (ControlNet on the base body's depth map).
cd "$(dirname "$0")/raw/outfits"
D=../../../spike/control/depth.png
S="front view, stylized fantasy game character, hand-painted texture style"
for s in 41 42; do gen3d image "full body adult human bandit rogue in dark brown leather armor, leather jerkin with straps and buckles, hood thrown back on the shoulders, dark scarf over the lower face, leather bracers, dark trousers, tall leather boots, belt with pouches, no weapon, $S" --object --control $D --seed $s -o bandit_s$s.png -q >/dev/null 2>&1 && echo "ok bandit $s" || echo "FAIL bandit $s"; done
for s in 51 52; do gen3d image "full body goblin with green skin, pointed ears, sharp teeth, wearing torn brown leather rags, a crude belt with a bone, wrapped cloth on the feet, no weapon, $S" --object --control $D --seed $s -o goblin_s$s.png -q >/dev/null 2>&1 && echo "ok goblin $s" || echo "FAIL goblin $s"; done
echo BATCH2 DONE

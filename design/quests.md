# Quests (v1)

> Implemented in `game/scripts/items/quests.gd`, `player/player.gd` (`visit_inn`) and the
> tracker in `ui/hud.gd`. A first, simple version of the "quests" item in game-design.md, 10.

- Every inn has a **notice board** with three hunting quests for the enemies of its zone
  ("Thin out the Wolves 0/8", "Bounty: Bandits 0/4"). Arriving at the inn takes them on, so
  there are no dialogs; the tracker under the minimap shows them.
- Kills count anywhere. A finished quest says "complete! Return to the inn".
- Arriving at the inn of that zone hands in the finished quests. Reward: XP like five kills of
  the quest's level (at most half a level), `25 × quest level` bronze, and an uncommon item
  (15% rare) for the hero's class. When all three are handed in, the board posts the next round
  (quest level +1 per round).
- Quest level = the zone's lowest enemy level + 2 + round. Elites: 3–5 kills, others 6–10.
- Saved with the hero (`quests`: active quests and rounds per zone).

Later: story quests with an NPC and text (Oldworld2's plots), delivery and exploration quests,
quest markers on the minimap.

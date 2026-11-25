# World, Zones and Enemies

> Part of the [Oldworld3 design docs](game-design.md). Based on Oldworld2's `world.md`, moved
> from a tile grid to 3D terrain. Distances in meters.

## 1. World Structure

- **Endless and seeded:** the same seed always gives the same world. Zones are generated when
  the hero gets near them.
- **Zone grid** (from Oldworld2): each zone is a roughly square cell. The Grassland is in the
  middle; north leads to the North, east to the Unholy lands, west to the Mediterranean, south
  to the Mediterranean or the Desert, with a chance to stay the same type. Difficulty is
  1 + the zone's ring around the start; enemy levels at difficulty d are 5d−4 to 5d.
- **Zone size:** a cell is **512 × 512 m** (starting guess; Oldworld2 used 512 tiles of 1 m).
  At 7 m/s that is about 75 s to cross, a bit less than a small WoW zone. TODO: tune.
- **Borders** (from Oldworld2): zones are separated by natural barriers (dense forest, cliffs,
  steep mountains, deep water) and connected by 1–3 crossings where a road leads through
  (pass, bridge, gap in the forest).
- v1: one Grassland zone; the land beyond the crossings is blocked off.

## 2. Terrain

- A **heightmap** per zone, 1 sample per 2 m (TODO: check detail vs. performance), from layered
  noise (FastNoiseLite, seeded):
  - low rolling hills everywhere (amplitude ~8 m, wavelength ~150 m)
  - a few larger hills (up to ~25 m) away from the center
  - flattened areas for the settlement, roads and camps
  - steep rims at the zone border (cliffs / mountains) where there is no crossing
- **Water:** a river or lakes where the terrain is carved below the water level.
- **Ground materials** blended in the terrain shader: grass, dirt (roads, camp grounds), rock
  (slopes steeper than ~35°), sand/mud by water. Textures are generated
  ([asset-pipeline.md](asset-pipeline.md)), made seamless, tiled every few meters.
- Walkable: slopes up to 45°; steeper is a wall.
- Collision: Godot `HeightMapShape3D` per chunk.

## 3. The Grassland (v1)

- Meadows, farmland at the edges, small forests of oaks and birches, a river or lakes, bushes,
  rocks and flowers.
- **Forests:** clusters from a noise mask, 40–75% tree density inside; dense forest bands form
  the zone border where there is no cliff.
- **Roads:** about 4 m wide, from each crossing to the settlement, winding (midpoint-displaced
  curves, from Oldworld2), flattened into the terrain and painted with the dirt material.
- **Settlement:** one per zone, near the center: a plaza, an **inn** (checkpoint, heals) and
  3–5 houses. No enemies within 60 m; no elite groups within 170 m and the champion beyond 190 m, so the ring around the settlement (about 10–20 groups of normal enemies, levels 5d-4 to 5d-2) is for levelling first.
- **Shrines:** a checkpoint shrine halfway along roads longer than 180 m, 6–8 m beside the road.
- Zone name generated in the style of English place names, shown on entering (from Oldworld2).

## 4. Enemies

Enemies are a creature plus an optional class, as in Oldworld2. Tiers:

| Tier | HP vs. hero | Damage vs. hero | XP | Notes |
|------|-----:|-----:|---:|-------|
| Trash | ~40% | ~50% | 1× | Beasts, goblins; fight in packs |
| Elite | ~70% | ~100% | 2× | Humanoids with a class; the main source of gear later |
| Champion | ~100% | ~110% | 3× | Random modifier (Swift, Thorned, …); later |
| Boss | 200%+ | ~120% | 5× | Later |

### 4.1 Grassland Enemies (v1)

Level-1 values; health is Oldworld2's × 4. Abilities in real time (cooldowns in seconds).

| Enemy | Tier | Types | HP | Atk | Def | Res | Behavior | Speed | Group | Habitat |
|-------|------|-------|---:|----:|----:|----:|----------|-------|-------|---------|
| Wolf | Trash | Physical | 200 | 8 | 10 | 8 | Aggressive | Fast | Packs of 2–4 | Forests and forest edges |
| Boar | Trash | Physical, Nature | 240 | 9 | 12 | 6 | Defensive | Normal | Alone or pairs | Meadows, farmland edges |
| Goblin | Trash | Physical, Dark | 180 | 9 | 8 | 7 | Normal | Fast | Groups of 2–3 | Camps by water |
| Bandit (Rogue) | Elite | Physical, Dark | 320 | 13 | 9 | 8 | Normal | Normal | 2–3 | Camps within 40 m of a road |

| Enemy | Attacks and abilities |
|-------|----------------------|
| Wolf | Bite (auto-attack, 2.0 s); **Howl** once when the fight starts: Attack +25% for 15 s for the whole pack |
| Boar | Gore (auto-attack, 2.4 s); **Tusk Charge** when the hero is 8–20 m away: rushes in, power 55, knocks back 3 m; 12 s cooldown |
| Goblin | Club (auto-attack, 2.0 s); **Sling Stone** from 10–25 m before closing in: power 30, slow 30% for 4 s; 8 s cooldown |
| Bandit | Quick Stab (auto-attack 1.8 s, 20% crit); **Poisoned Blade** (Poison 15 s, 12 s cooldown); **Smoke Screen** once per fight at 70% health: a 5 m cloud for 9 s; the hero's attacks from inside it miss 50% (Overwhelm answers that) |

- Auto-attack power for enemies follows the same rule as the hero's (speed × 12) before tier
  damage scaling.
- Levels in v1: difficulty 1 → levels 1–5; trash at the low end near the settlement, elites at
  the high end, rising with distance from the settlement.

## 5. Placement

From Oldworld2, scaled to meters:
- **Habitats** decide where each creature spawns (table above).
- **Groups** keep at least 30 m from each other (Poisson disc); group sizes are rolled.
- **Safe areas:** no spawns within 60 m of the settlement and 20 m of shrines; roads are
  quieter (no groups within 10 m) except bandit camps near them.
- **Density** grows with distance from roads and the settlement, highest near the zone border.
- A few enemies wander within 15 m of their spawn point.
- **Respawn:** 5 minutes after death, if the hero is more than 60 m away. TODO: confirm.

## 6. Points of Interest (later)

Bandit camps (tents, fire, crates) are in v1. Later: goblin caves, ruins, towers (hedge wizards),
dungeons, treasure.

## 7. Implemented (2026-11-13)

- **Zone grid** (`game/scripts/world/zones.gd`, `zone.gd`, `zone_types.gd`): 512 m zones, the
  start zone at (0, 0). North of the start lies the **North**, south the **Desert**, west the
  **Mediterranean**, east the **Unholy lands** (the first ring stays Grassland with 30% chance,
  as in Oldworld2). Difficulty = 1 + ring; enemy levels 5d−4 to 5d.
- **Crossings:** one per border, placed along the border from `hash(seed, zone A, zone B)`, so
  both zones agree. Every crossing has a road to the settlement; the rim is lowered along roads,
  and near a crossing both zones meet at the same height (`Terrain.CROSS_H`).
- **Hills** come from world-space noise (continuous across zones); lakes and roads per zone.
- **Loading:** a neighbor zone is built on a worker thread when the hero comes within 140 m of
  its border, then attached; zones two cells away are unloaded.
- **Lakes:** 2–3 per zone, irregular shores, shallow (wade through); frozen and walkable in the
  North. Goblin camps sit by the water.
- **Settlement:** inn (checkpoint) north of the plaza, houses around it, a well; shrines halfway
  along long roads. The North uses longhouses.
- **North enemies** (`EnemyData.NORTH`): Snow Wolf (packs, Howl), Frost Wisp (floats, shoots ice
  from 14 m), Ice Troll (big, slow, Troll Smash), Berserker (elite, goes berserk at half health,
  Cleave). Fallback models are used until a generated one exists.
- **Zone names** from Oldworld2's lists (English for Grassland, Norse for the North).
- **Desert, Mediterranean, Unholy lands:** their own ground, trees, houses, music, light and
  enemies (`zone_types.gd`, `EnemyData.DESERT`, `WEST_EAST`).
- **Champions:** every zone has one named champion ("Vessa Two-Scars") of its elite kind, far
  from the settlement: level 5d + 1, 2.5× health, +15% stats, 1.2× size, an orange nameplate
  and an orange dot on the minimap. Always drops gear (uncommon or better), 40 × level bronze,
  3× XP. Respawns like everything else (5 min).
- **Inn:** merchant (design/items.md) and notice board with quests (design/quests.md).
- **Ancient Desert** (Oldworld2 world.md 2.3.4): a desert zone is Middle Eastern or Ancient by
  smooth noise over the grid (`ZoneTypes.type_at`), so neighbors usually share the theme. Same
  sand as the desert, fewer trees; two pyramid groups per zone 70–180 m from the settlement
  (`Settlement.landmark_spots`, computed before vegetation: trees keep 45 m away, other enemies
  30 m): a big pyramid facing the settlement, two small ones beside it, a sphinx or a pharaoh
  statue in front. Obelisks before the temple (inn), mud-brick houses. Enemies
  (`EnemyData.ANCIENT`): Scarab (swarms of 2–3, aggressive, Hard Shell), Cobra (spits venom
  from 12 m, Venom Bite), Mummy (slow; Wrap: 30% slow for 5 s; Ancient Curse: −25% Attack for
  10 s), Tomb Guardian (elite, 32–55 m from a pyramid; Sun Strike: Holy blow; Sacred Ward).
- **Sky** colors are part of the zone type (murky grey-green in the Unholy lands, pale gold over
  the deserts); so is the fog density (`fog_density`, default 0.002).
- **Unholy lands as a haunted forest:** dark pines and dead trees grow denser and over more of
  the zone (`tree_density` 1.5, `forest_min` 0.52, the forest-noise threshold), dark bushes
  (`deadbush`, the bush model tinted) mix with gravestones, the grass is pulled toward a dull
  olive (`grass_tint`, alpha = amount, in the terrain shader), the light is pale green
  and a thick green mist (0.016; at night a dark green one, `night_fog`, `night_sky`) hides everything past ~100 m (vegetation is culled at 105 m,
  `view_range`, which keeps the frame rate near the other zones'). **Eyes in the bushes**
  (`world/bush_eyes.gd`): every 1.5–5 s a pair of faint yellow-green eyes (dimmed by the mist) may flare up in a
  bush 15–55 m ahead of the camera, stare for under a second (sometimes blinking) and close;
  at most two at a time; never in a bush within 13 m of the hero, and open ones close at once
  when the hero comes that close. `--eyes` shows many, often (screenshots).
- **Ground:** the terrain shader adds drier and darker grass patches, bare-soil spots and soil
  grit (zone key `bare`); **ground clutter** (`world/clutter.gd`) puts grass tufts, flowers and
  pebbles near the hero, more on High graphics quality.
- **Village people:** a merchant at the stall and two villagers walking over the plaza
  (`world/villager.gd`); they turn to face the hero.
- **World map** (M, `ui/world_map.gd`): visited zones with name, type and difficulty; their
  neighbors by type color only.

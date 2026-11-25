# Game Design Document — Oldworld3

> Status: first version of the design. Items marked `TODO` need a decision; items marked `IDEA`
> are suggestions, not commitments. Numbers are starting values, to be tuned by playtesting.

Oldworld3 is a **third-person 3D fantasy RPG with real-time combat** in the spirit of World of
Warcraft Classic, in a **procedurally generated, seeded world**. It is the successor of
Oldworld2 (`../oldworld2`), a top-down game with Pokemon-style turn-based battles. The world,
class and ability design come from Oldworld2 and are adapted to real time here.

| Document | Contents |
|----------|----------|
| [mechanics.md](mechanics.md) | Combat in real time, stats, damage, resources, status effects, aggro, death, XP |
| [classes.md](classes.md) | Classes, the Warrior and its abilities |
| [world.md](world.md) | World generation, zones, the Grassland, settlements, enemies, placement |
| [tech-stack.md](tech-stack.md) | Godot, project layout, running, testing, saving |
| [asset-pipeline.md](asset-pipeline.md) | How characters, gear and other 3D assets are made |
| [gen3D-server.md](gen3D-server.md) | The generation server (SDXL, ControlNet, TRELLIS.2) |
| [prompt-v1.md](prompt-v1.md) | The brief for the first version |

## 1. Vision

- **Pitch:** explore an endless generated fantasy world from behind your hero's shoulder, fight
  visible enemies in real time with WoW-Classic-style abilities, level up, and push into harder
  zones.
- **Inspirations:** World of Warcraft Classic (classes, abilities, combat feel, itemization),
  roguelikes and procedural exploration games (endless seeded world), Oldworld2.
- **Target player:** a fairly experienced player; the game starts easy and gets harder outward.
- **Platform:** Linux desktop first, Windows later. Must run at 60 FPS on integrated graphics
  (the development laptop's Vega 8).
- **Playtime:** endless; the world grows as you explore.
- **One hero**, no party or companions. Single player.

## 2. Core Loop

1. Explore the generated world on foot (zones, roads, settlements, points of interest).
2. Spot enemies and choose fights; aggressive enemies notice you and attack.
3. Fight in real time: auto-attack, abilities on cooldowns, positioning, pulling one enemy
   from a pack instead of all of them.
4. Earn XP, money and (later) items; learn abilities with levels.
5. Push outward into zones of higher difficulty.

## 3. What changes from Oldworld2

| | Oldworld2 | Oldworld3 |
|---|---|---|
| Camera | Top-down, fixed | Third person behind the hero, orbit and zoom with the mouse |
| Movement | Tile-locked, 4 directions | Free movement, turning, strafing, jumping, slopes |
| Terrain | Flat tiles | 3D heightmap terrain: hills, valleys, rivers, lakes |
| Combat | Separate turn-based battle screen, always 1v1 | Real time, in the world; several enemies at once |
| Abilities | One action per turn, priority, rounds | Global cooldown, cooldowns, durations in seconds, auto-attack |
| Art | Blender-scripted low-poly, Quaternius packs | All generated with the gen3D server, no third-party assets |

## 4. The Hero

- One class chosen at the start (v1: only the Warrior, see [classes.md](classes.md)).
- Appearance: the base body of the chosen body type, wearing its gear (see
  [asset-pipeline.md](asset-pipeline.md)). Name and customization: TODO.

## 5. Camera and Controls

WoW Classic style, keyboard and mouse. Gamepad: later (IDEA).

| Input | Action |
|-------|--------|
| W / S | Move forward / backward (backward at half speed) |
| A / D | Turn left / right; strafe while the right mouse button is held |
| Q / E | Strafe left / right |
| Space | Jump |
| Left mouse drag | Orbit the camera around the hero |
| Right mouse drag | Orbit the camera and turn the hero with it |
| Left + right mouse | Run forward |
| Mouse wheel | Zoom (2–15 m) |
| Tab | Target the nearest enemy in front; repeat to cycle |
| Left click on enemy | Target it |
| 1–9 | Action bar |
| F | Toggle auto-attack on the target |
| Escape | Clear target, then open the menu |
| Shift (hold) | Sprint: 1.5× running speed (10.5 m/s) while stamina lasts (10 s, refills in 20 s, twice as fast standing still; from Oldworld2) |

- The camera never clips into terrain, trees or buildings: it pulls in toward the hero.
- Running speed 7 m/s, backward 3.5 m/s, turning 180°/s with the keys.

## 6. UI

- Hero frame (health, rage), target frame (name, level, health, elite marker), action bar with
  cooldown sweeps, cast bar, XP bar, money, floating combat text, zone name on entering.
- Main menu: Continue, New game (seed), Settings, Quit.
- Minimap (top right: roads, lakes, settlement, shrines, crossings, enemies, champion) and a
  world map (M) of the zones visited and seen.

## 7. Death and Checkpoints

From Oldworld2: on death the hero respawns at the last checkpoint (inn or road shrine), fully
healed, loses 10% of the money and the XP toward the next level (never the level itself).
Checkpoints are activated by interacting with them; they also heal fully.

## 8. Save System

From Oldworld2: one autosave, no slots. Saved parts (world seed, position, last checkpoint, hero,
money, defeated unique enemies, opened chests) are written only when they change: events save at
once (level-up, death, checkpoint, entering a zone), the position at most every 30 s, everything
on quit. Format: see [tech-stack.md](tech-stack.md).

## 9. Art and Audio

- **Look:** stylized fantasy, hand-painted textures, readable silhouettes, WoW Classic as the
  mood reference. All 3D models and textures are generated (see
  [asset-pipeline.md](asset-pipeline.md)); nothing third-party.
- **Lighting:** sun with shadows, sky, fog in the distance. **Day and night** (`world/day_night.gd`):
  a day lasts 40 minutes; the sun arcs east to west, sunrise and sunset tint sky and light
  orange, at night a bluish moon lights the world at a third of the strength (nights stay
  playable). The zone type sets the daytime colors. The menu switches it off (fixed morning).
- **Audio:** our own, synthesized like Oldworld2's (`tools/audio` there can be reused as code).
  One theme per zone, combat music, sound effects for abilities and hits (done:
  `tools/audio/makeaudio.py`).

## 10. Scope

- **v1:** Warrior levels 1–10, one Grassland zone with a settlement, roads, shrines, wolves,
  boars, goblins and bandits, XP and levels, death and respawn, autosave, title screen. See
  [prompt-v1.md](prompt-v1.md).
- **Built beyond v1 (2026-11-13, see nightlog.md):** all nine classes; six zone types (Grassland,
  North, Desert, Ancient Desert, Mediterranean, Unholy lands) on an endless grid; items,
  inventory, merchant; notice-board quests; champions; world map; day and night.
- **Later:** trainers, dungeons, story quests, visible armor, mounts.

## 11. Open Questions

- Enemy respawn: every enemy (champions too) respawns 5 min after death when the hero is more
  than 60 m away (implemented). Never for future bosses? TODO
- Long-term goals beyond exploring (from Oldworld2): TODO
- Mounts for long distances? IDEA

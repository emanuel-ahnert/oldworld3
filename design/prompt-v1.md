# Prompt: Oldworld3, first version (Warrior + Grassland)

> **Status (2026-11-12):** step 1 (design docs) done; step 2 (asset pipeline spike) done, see
> [asset-pipeline.md](asset-pipeline.md); step 3 started: `game/` has the Grassland terrain,
> vegetation and the warrior with third-person movement (run with `tools/run.sh`).
>
> This is the brief for the agent that builds the first playable version of Oldworld3.
> Read all of it before you start. Where it says **Decide**, write the decision into the
> design docs (with the reason) before writing code that depends on it.

## 1. What you are building

Oldworld3 is a **third-person 3D fantasy RPG with real-time combat**, in the spirit of
World of Warcraft Classic, set in a **procedurally generated, seeded world**. One hero, no
party. Explore, fight visible enemies, level up, push into harder zones.

It is the successor of **Oldworld2** (`../oldworld2`), a top-down game with turn-based,
Pokemon-style battles in a separate battle view. Oldworld3 keeps Oldworld2's world, class
and ability design as the starting point, and changes how the game is played and how it
looks.

The first version has **one class (Warrior)** and **one zone (Grassland)**.

## 2. What changes from Oldworld2

| | Oldworld2 | Oldworld3 |
|---|---|---|
| Camera | Top-down, about 55°, fixed | Third person behind the hero, orbit with the mouse, zoom with the wheel |
| Movement | Tile-locked, 4 directions | Free movement (WASD + mouse steering), jumping, slopes |
| Terrain | Flat tile grid, 1 tile = 1 m | Real 3D terrain: heightmap with hills, valleys, rivers and lakes |
| Combat | Separate battle screen, turn-based, always 1v1 | In the world, in real time. Several enemies can fight you at once |
| Abilities | One action per turn, priority, rounds | Global cooldown, cooldowns, cast times, auto-attack, durations in seconds |
| Art | Blender-scripted low-poly models, Quaternius bodies and animations, toon shading | **Everything generated with the gen3D server** (see section 6). Nothing from Oldworld2's asset folders is reused |

Oldworld2's models are too low quality for a close third-person camera. **Don't copy, convert
or reuse any model, texture or animation from `../oldworld2/assets` or `../oldworld2/art`.**
The Quaternius packs Oldworld2 still used are third-party assets and are not allowed here.

## 3. Read first

From Oldworld2 (reference only; Oldworld3 has its own docs):

- `../oldworld2/design/game-design.md`: vision, loop, death model, save system, UI
- `../oldworld2/design/classes.md`: classes, base stats, the Warrior's abilities and pools
- `../oldworld2/design/mechanics.md`: stats, damage formula, elements and types, status
  effects, aggro and leash, XP curve
- `../oldworld2/design/world.md`: zone grid, difficulty, borders and crossings, roads,
  settlements, shrines, enemies, enemy placement
- `../oldworld2/design/items.md`: rarity, item level, slots (items are out of scope for v1,
  but the data model must leave room for them)
- `../oldworld2/design/tech-stack.md` and `../oldworld2/internal/procgen`: how the world
  generation, determinism and save system were built

From Oldworld3:

- `design/game-design.md`: the (very short) start of the new design doc
- `design/gen3D-server.md`: how to use the asset generation server. It was written by
  another agent and **hasn't been fully checked by the user**. Treat it as a starting point:
  run `gen3d health` and one small test job before you rely on it, and correct the doc where
  it turns out to be wrong

## 4. Scope of the first version

### 4.1 In scope

- **Warrior** only, levels 1–10, all abilities Oldworld2's Warrior learns up to level 10,
  adapted to real time (section 5.3)
- **One Grassland zone**, difficulty 1, enemy levels 1–5, about 512 × 512 m (starting
  guess, tune by playtesting). Seeded: the same seed gives the same zone
  - terrain with hills, a river or lakes, meadows, small forests, farmland at the edges
  - a zone border of natural barriers (forest, cliffs, water) with 1–3 crossings. The land
    beyond can be blocked off for now
  - one settlement with an **inn** (checkpoint and full heal) and a few houses
  - roads from the crossings to the settlement, a **checkpoint shrine** halfway along long
    roads
- **Enemies:** wolf (trash, packs of 2–4, forest edges), boar (trash, defensive, meadows),
  goblin (trash, groups of 2–3, by water), bandit (elite, human Rogue, groups of 2–3 near
  roads, not within 100 m of the settlement). Stats, abilities, habitats and leash times
  from Oldworld2's `world.md`, adapted to real time
- XP and levels (Oldworld2's XP curve), death and respawn at the last checkpoint with the
  10% money loss, money drops
- HUD: health, rage, target frame with name, level and health, cast bar, action bar with
  cooldowns, XP bar, money, floating combat text, zone name on entry
- Out-of-combat regeneration, resting at a camp fire
- Autosave (Oldworld2's write strategy: partial updates, event saves, position at most every
  30 s)
- A title screen: continue, new game (seed), quit

### 4.2 Out of scope (but don't block it)

Other classes, other zones and zone streaming, items and inventory, shops, trainers, tomes,
dungeons, quests, multiplayer. Keep content data-driven (abilities, enemies, zones as data
files) so these can be added without rewriting the core.

## 5. Gameplay design

Write the real-time versions of Oldworld2's rules into Oldworld3's design docs
(`design/mechanics.md`, `design/classes.md`, `design/world.md`, …) before implementing them.
The numbers below are starting points to tune by playtesting.

### 5.1 Camera and controls (WoW Classic style)

- WASD move (A/D turn, or strafe while the right mouse button is held), Q/E strafe, Space
  jump, both mouse buttons together run forward
- Left mouse drag: orbit the camera. Right mouse drag: orbit and turn the hero. Wheel: zoom
- Tab: target the nearest enemy in front, cycle on repeat. Left click on an enemy: target it.
  Escape: clear the target, then open the menu
- 1–9: action bar. F (or right click on a target): start auto-attack
- Camera must not clip into terrain or trees: pull it in on collision
- Gamepad support is nice to have, not required for v1

### 5.2 Combat

- **Auto-attack** on a swing timer from the weapon speed (e.g. 2.6 s two-hander,
  1.8–2.0 s one-hander). Only in melee range and when roughly facing the target
- **Global cooldown** 1.5 s after most abilities. Some abilities have their own cooldown
- **Rage** (0–100) replaces MP for the Warrior, as in Oldworld2: starts at 0, gained by
  dealing and taking damage, decays slowly out of combat
- **Damage formula:** keep Oldworld2's formula (level, power, Attack vs. Defense, affinity,
  element chart, crit 1.5×, random 0.85–1.0), scaled so a fight against a same-level wolf
  takes about 10–15 s. Keep "no random misses" except from visible mechanics (Flying)
- **Turns become seconds:** stat stages become timed buffs and debuffs (e.g. +1 stage
  = +50% for 10 s, no stacking past ±3), DoTs tick every 3 s at about 1/16 of max HP per tick
  (re-check against fight length), "once per battle" becomes a cooldown, "first round only"
  becomes "only before the target is in combat", priority goes away
- **Enemies fight together:** several enemies can attack at once. Pulling a pack is the main
  risk, like in WoW. There is no grace period anymore
- **Aggro and leash:** Oldworld2's aggro ranges (defensive, passive, normal, aggressive),
  converted to meters. A pulled enemy calls nearby members of its group. Enemies leash back
  to their spot (and heal to full) when dragged too far from it or after Oldworld2's chase
  timeout without taking damage
- **Death:** respawn at the last checkpoint with full health, lose 10% money and the XP
  toward the next level (as in Oldworld2)

### 5.3 The Warrior

Start from Oldworld2's Warrior (`classes.md`): high HP, Attack and Defense, Physical
affinity, rage, 2× out-of-combat HP regeneration, plate, swords, axes, maces, shields.
**Decide** the exact real-time version of every ability. A starting proposal:

| Level | Oldworld2 | Oldworld3 proposal |
|---:|---|---|
| Start | Punch (free fallback, +10 rage) | Becomes the **auto-attack**; no button |
| Start | Heavy Strike (power 50, 15 rage) | Instant strong hit, 15 rage, on the global cooldown |
| Start | Battle Cry (Attack +1 stage, 20 rage) | Attack buff for 2 min, 10 rage, usable out of combat |
| 2 | Overwhelm (after a dodge or miss, can't be dodged) | Usable for 5 s after the target dodges (flying enemies), strong hit, 5 rage |
| 3 | Enrage (passive, on crit taken) | Passive: being crit (or 50% on any hit) gives +25% damage for 12 s |
| 6 | Charge (first round only, stuns, +15 rage) | Rush to the target from 8–25 m, short stun, +15 rage, only out of combat, 15 s cooldown |
| 8 | Second Wind (passive regen on hit) | Passive: 30% chance on taking damage (always on a crit) to heal 1/16 max HP over 6 s; refreshes, doesn't stack |
| 10 | Rend (bleed, 20 rage) | Bleed for 15 s, ticking every 3 s, 10 rage |

The warrior needs one more source of rage spending against packs. **Decide** whether to add
a level-4 area attack (e.g. Thunder Clap: small damage and attack-speed slow to enemies
around you), since real-time combat now has groups.

### 5.4 Enemies in real time

Give every enemy from section 4.1 its Oldworld2 abilities as real-time abilities with
cooldowns and simple rules (e.g. wolves Howl once at the start of a fight, goblins throw
Sling Stones from range then close in, bandits open with Smoke Screen, then Quick Stab and
Poisoned Blade). Bandits use the same ability system as the player.

Smoke (no ranged attacks or targeted spells on the bandit) barely matters to a melee
warrior. **Decide** a real-time replacement that does (e.g. Smoke Screen: the warrior's
attacks have a 50% chance to miss while inside the cloud, so stepping out of it is the
answer).

## 6. Art and assets

### 6.1 Rules

- **All graphics are made by us**: generated with the gen3D server (SDXL text → image,
  TRELLIS.2 image → textured 3D mesh), plus scripts (Blender, our own code) to rig, animate,
  optimize and assemble them. No downloaded or third-party models, textures, animations,
  HDRIs or icons, not even CC0
- Every generated asset is recorded in an **asset manifest** (prompt, negative prompt,
  seed, faces, texture size, resolution, job id, date, and the post-processing steps), so it
  can be reproduced. Generation and post-processing are scripts under `tools/`, not manual
  steps
- **Always look at `preview.png` and `image.png`** of every result before using it
  (see `gen3D-server.md`), and reject and regenerate bad ones
- Submit several jobs in the background and fetch the results; don't wait on each one

### 6.2 Look

**Decide** the look early and make one test scene before mass-producing assets. Suggested:
stylized fantasy (hand-painted, saturated but not garish, readable silhouettes), WoW
Classic as a mood reference. A consistent style prompt suffix is needed so all assets
match. Keep in mind that TRELLIS outputs PBR materials without normal maps; check how they
look under the game's lighting.

### 6.3 Asset list for v1

- Hero: warrior body in plate, with separate weapon models (two-handed sword, one-handed
  sword, shield) attached to hand/forearm bones
- Enemies: wolf, boar, goblin, bandit
- Nature: 3–4 tree types, bushes, rocks and boulders, grass and flower clumps, fences
- Buildings: inn, 2–3 house types, shrine, camp fire. **Decide** whether buildings are whole
  generated meshes or assembled from generated parts (walls, roofs, doors)
- Ground: seamless terrain textures (grass, dirt, road, rock, sand, riverbed) generated with
  `gen3d image`, made seamless by a script, blended on the terrain
- Sky: generated or procedural, our own
- UI: our own icons for the abilities (`gen3d image`), our own font (Oldworld2's bitmap font
  generator is fine to reuse, it's code)
- Audio: our own (Oldworld2's synthesizer code in `tools/audio` can be reused and extended;
  the generated sound files can't be used as they are)

### 6.4 Known problems to solve first

**The plan for bones and gear is in [asset-pipeline.md](asset-pipeline.md)** (one base body per
body type with a shared skeleton, armor as texture regions plus rigid pieces on bones). Read it
and its spike results first. The list below is the background.

These decide whether the pipeline works at all. Solve them in a **spike before building the
game**, and write the results into `design/` (e.g. `design/asset-pipeline.md`):

1. **Rigging and animation.** TRELLIS produces a static mesh (one piece, about 1 unit
   tall). Characters and creatures need a skeleton and animations: idle, walk, run, jump,
   auto-attack (2 variants), ability strike, hit reaction, death, and for enemies their
   special moves. The server only makes static meshes and has no img2img, ControlNet or
   pose conditioning (checked November 2026). Option to try first: get a clean A- or T-pose
   from the text prompt alone (try several seeds with `gen3d image --object`, pick the best,
   pass it to `gen3d model --image`). If that isn't reliable, ask the server-side Claude
   (section 6.5) to add pose conditioning (e.g. ControlNet OpenPose for SDXL), then a Blender script
   that fits a skeleton to the mesh, binds it with automatic weights, and keyframes the
   animations (Oldworld2's `tools/models/rigkit.py` shows how it scripted creature rigs and
   keyframed animation in Blender). Check the result in motion, not only in the bind pose:
   joint deformation (shoulders, knees), fused limbs (arms fused to the body, legs fused
   together) and the weapon hand are the likely problems
2. **Gear.** A single fused mesh can't swap armor pieces. For v1 the warrior wears one fixed
   armor set, and weapons and shields are separate models on bones. `gen3d model --image`
   uses the alpha channel of an RGBA PNG as the mask, so parts of one picture (a sword, a
   shield, a helmet) can be cut out and built as separate meshes in a matching style. **Decide** (and write
   down) a direction for later armor swapping: e.g. one generated model per armor set, or
   splitting meshes by region
3. **Performance.** Development happens on a ThinkPad T495 (Ryzen with Vega 8 integrated
   graphics). The game must run at a stable **60 FPS at 1080p on that laptop** with the
   v1 zone. That means polygon budgets (TRELLIS defaults to 50k faces), decimation in Blender,
   LODs and impostors for trees, instancing, texture sizes (1024² or less for most props),
   texture compression or atlasing, culling. Measure early with a scene of a few hundred
   trees and ten animated enemies
4. **Scale and orientation.** Outputs are about 1 unit tall and centered. Every asset needs a
   real-world size (hero ~1.85 m, wolf ~0.8 m at the shoulder, tree 6–12 m), a ground pivot
   and a forward direction, recorded in the manifest and applied by the pipeline
5. **Consistency.** Several assets must look like they belong to one world. Test the style
   suffix on 5 different assets side by side

If the gen3D server is unreachable, ask the user. Don't try to fix the server, and never
install or run AI models on the laptop (see `gen3D-server.md`).

### 6.5 Talking to the server-side Claude

A Claude Code instance on the GPU box knows the server code. Ask it questions over SSH, or ask it
to change the server (new endpoints, parameters, models):

```
ssh <user>@<gpu-box> 'cd <server dir> && claude -p "<question>"'
```
(The real address, login and paths are in `design/local/gen3d-access.md`, kept out of the
repository.)

- Add `-c` (`claude -c -p "…"`) to continue its last conversation
- Say in the prompt whether it is read-only ("don't change anything") or a change request.
  Ask the user before requesting server changes, since the box is also their gaming PC and
  a restart drops running jobs
- It runs non-interactively, so a tool it isn't allowed to use is denied, not asked for.
  Questions about what the server produces are often answered faster and more reliably by a
  small test job (`--faces 5000 --texture 512`) and inspecting the result here
- Answers can take a few minutes. Use a long timeout

## 7. Technology

**Engine: Godot 4** (decided by the user). Use the latest stable 4.x release, and write the
version and the reasons into `design/tech-stack.md`. It isn't installed on the laptop yet.
Ask the user before installing it.

- **Language: Decide** and confirm with the user. The recommendation is **typed GDScript**:
  it needs no extra toolchain, has the best documentation, and runs headless without setup.
  If the terrain or world generation is too slow in GDScript, move only that part to C#
  or a GDExtension later. Oldworld2's Go code (procgen, save, data) is a reference to port,
  not code to link
- **Renderer:** Forward+ if it holds 60 FPS on Vega 8. Otherwise use the Mobile renderer.
  Measure both in the spike (section 6.4)
- **Use what Godot brings** instead of writing it: `AnimationTree` for blending animation
  states, `CharacterBody3D` for movement on slopes, `SpringArm3D` for the camera collision,
  `NavigationRegion3D` for enemy pathing, `MultiMeshInstance3D` and visibility ranges
  (LOD/HLOD) for trees and grass, the built-in mesh LODs, directional shadows, and `Control`
  nodes for the HUD
- **Terrain: Decide** between a terrain addon written by someone else, such as Terrain3D, and our own
  heightmap mesh in chunks. Code addons are allowed. The no-third-party rule covers art
  assets, not code, but check the license (MIT or similar) and that it works with the chosen Godot version
- **Agent-friendly workflow:** scenes and resources as text (`.tscn`, `.tres`), project
  settings in `project.godot`, everything editable without the editor. Import generated
  `.glb` files with import scripts (`EditorScenePostImport`) or `.import` settings, not
  by hand. Run the game headless for tests (`godot --headless`) and with a window for
  scripted screenshot runs
- **Asset handoff:** the pipeline (gen3D → Blender rigging and decimation → `.glb`) writes
  into `assets/`, and Godot imports from there. Animations live in the `.glb` or in a shared
  animation library on one humanoid skeleton

Also:

- Game rules (combat, abilities, stats, XP, world generation) are plain, testable code,
  separate from rendering, deterministic with seeded RNG
- Content is data (abilities, enemies, zone parameters)
- An automated way to run the game with a scripted input and save a screenshot, without
  stealing focus (Oldworld2's `tools/testrun.sh` did this on Hyprland), so you can check
  your own visual work
- Unit tests for combat math, world generation determinism and saving (e.g. GUT or
  gdUnit4, run headless)
- Saving: Oldworld2 used SQLite. In Godot, **Decide** between a SQLite addon and Godot's own
  files (`ConfigFile`, JSON or binary `FileAccess`) that follow the same write strategy

## 8. Order of work

1. **Design docs.** Expand `design/game-design.md` and add `mechanics.md`, `classes.md`,
   `world.md` and `tech-stack.md` for Oldworld3, adapting Oldworld2's docs to real time and
   third person. Mark open points as `TODO` and suggestions as `IDEA`, as Oldworld2 did.
   Show the user the decisions marked **Decide** above
2. **Asset pipeline spike** (section 6.4): one warrior, one wolf, one tree, one ground
   texture, from prompt to rigged, animated, sized, optimized asset in the engine, at a
   measured frame rate on the laptop
3. **Engine skeleton:** terrain, hero with third-person camera and movement, animation
   states
4. **Combat:** targeting, auto-attack, Warrior abilities, rage, one enemy type with AI,
   aggro, leash, death and respawn
5. **World:** Grassland generation (terrain, water, forests, border and crossings, roads,
   settlement, shrines), enemy placement
6. **All v1 enemies, XP and levels, HUD, saving, title screen**
7. **Polish:** sound, music, effects, balance (fight lengths, time to level 10, how deadly
   packs are)

After each step, take screenshots, check them yourself, and show the user the result
before moving on.

## 9. Conventions

- Design docs in `design/`, written in plain, short English, kept up to date with what is
  actually built (mark what is implemented)
- Never commit secrets (the gen3D token)
- Keep generated binary assets out of git unless the user decides otherwise (**Decide**
  with the user: commit them, Git LFS, or regenerate from the manifest)

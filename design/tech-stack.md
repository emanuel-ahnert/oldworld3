# Tech Stack

> Part of the [Oldworld3 design docs](game-design.md).

## 1. Engine and Language

- **Godot 4.7.2** (stable, official build), on the PATH as `godot`. Chosen by the user over Go + raylib (Oldworld2's stack) because it brings
  terrain collision, shadows, animation blending, physics, navigation, LOD and a UI system.
- **Typed GDScript.** No extra toolchain, the best documentation, runs headless without setup.
  If generation or simulation code becomes too slow, only that part moves to C# or a
  GDExtension. Oldworld2's Go code (procgen, rules) is a reference to port, not code to link.
- **Renderer:** Forward+ for now. TODO: measure on the laptop's Vega 8 against the Mobile
  renderer once there is a full zone.

## 2. Project Layout

```
oldworld3/
├── design/              design docs (this folder)
├── game/                the Godot project (project.godot)
│   ├── assets/          imported game assets (characters, nature, textures), made by tools/
│   ├── scenes/          .tscn scenes
│   └── scripts/
│       ├── world/       terrain, zone generation, spawning
│       ├── player/      hero controller, camera
│       ├── combat/      rules: stats, abilities, damage (no rendering)
│       └── ui/          HUD, menus
├── tools/
│   ├── pipeline/        Blender scripts: base bodies, outfits, weapons, control images
│   ├── run.sh           start the game (desktop 9, fullscreen) — used by VS Code
│   └── shot.sh          scripted test run with a screenshot on a hidden workspace
├── game_src/            generated sources before processing (gen3d outputs, manifests)
└── spike/               experiments (not part of the game)
```

## 3. Conventions

- Scenes and resources as text (`.tscn`, `.tres`); everything editable without the editor.
- Gameplay rules (damage, abilities, XP, world generation) are plain GDScript classes without
  nodes where possible, deterministic with seeded RNG, testable headless.
- Content as data: abilities, enemies and zone parameters in `.tres` or JSON files.
- Generated assets keep a manifest entry (prompt, seed, job id, post-processing), see
  [asset-pipeline.md](asset-pipeline.md#5-asset-manifest).
- **Threads:** worker threads compute data only (arrays, noise, positions). Anything that makes
  rendering or physics objects (meshes, materials, multimeshes, shapes, `load()` of models)
  happens on the main thread. Doing that on a worker deadlocked against the renderer (night
  log 42). Zones: `Zone.compute` on a worker, then `Zone.build_step` once per frame.

## 4. Running

- **VS Code:** Run and Debug → **"Oldworld3 (desktop 9, fullscreen)"**. It runs
  `tools/launch.js` (Node, from mise), which starts `tools/run.sh` and exits when the game
  exits, so the debug session ends with the game; the stop button stops the game. `run.sh`
  imports changed assets, sets a Hyprland window rule (window class `Oldworld3`, the project
  name) so the game opens fullscreen on workspace 9 (`OLDWORLD3_WORKSPACE` overrides it), then
  starts Godot. The Godot boot splash is off; the game shows its own loading text while the
  world is generated.
- **Terminal:** `tools/run.sh` (same thing), or `godot --path game` for a plain window.
- **Test runs:** `tools/shot.sh out.png [frames] [-- game args]` runs the game on a hidden
  workspace (`special:oldworld`), waits the given number of frames, saves a screenshot and quits.
  It renames the window class to `Oldworld3 test` for the run (through `game/override.cfg`), so
  test runs never land on workspace 9 or take focus.
- Game command line arguments (after `--`): `--seed N`, `--shot <png>`, `--frame N`,
  `--autowalk`, `--sprint`, `--cam-yaw DEG`, `--zoom M`, `--pos X,Z`, `--bench SECONDS`, and
  the quality options in section 7.
- **Benchmark:** `tools/bench.sh [seconds] [forward_plus|mobile] [game args]`; `MSAA=1` or
  `FXAA=1` in the environment test those settings.

## 5. Testing

- Unit tests for rules and generation determinism: TODO (GUT or gdUnit4, run headless).
- Visual checks: `tools/shot.sh`, screenshots looked at after every visible change.

## 6. Saving

One autosave in `user://save/` (Godot's user data directory for the project).
Parts as small JSON files (world, hero, position, defeated enemies), each written only when it
changed (see [game-design.md](game-design.md#8-save-system)); writes go to a temp file that is
renamed over the old one, so a crash can't corrupt a save. SQLite (as in Oldworld2) isn't needed
at this size.

## 7. Performance (target: 60 FPS at 1080p on Vega 8)

Measured with `tools/bench.sh 12` (hidden window, vsync off, the hero runs through the start
area; 2026-11-13). The laptop is limited by pixels (fill rate), not by geometry or shadows.

| Setting | Avg FPS |
|---------|--------:|
| First version: native resolution, 2× MSAA, shadows 70 m, trees 220 m | 14.5 |
| Same, shadows 45 m, trees 160 m | 15.1 |
| Render scale 0.75 with FSR upscaling | 20.5 |
| … and no MSAA | 23.4 |
| … and a cheaper terrain shader (rock and dirt only sampled where they show) | 36.1 |
| … and FXAA (**current default**) | 34.3 |
| Render scale 0.6 (no MSAA, old shader) | 30.1 |
| Mobile renderer instead of Forward+ | 14.4 (slower here) |

- Defaults: Forward+, render scale 0.75 with FSR, FXAA, no MSAA, sun shadows to 45 m (2
  cascades), trees/bushes/rocks visible to 160 m. Command line: `--scale`, `--shadow-dist`,
  `--view` (see `game/scripts/main.gd`). TODO: a settings menu.
- Budgets: terrain ~130k triangles (2 m grid); trees 10k, bushes and rocks 3k triangles,
  `MultiMeshInstance3D` per 64 m chunk; hero ~24k triangles, 2048² textures.
- Next steps if needed: fewer texture reads in the body and terrain shaders, tree impostors
  for distant chunks, grass/terrain texture arrays.

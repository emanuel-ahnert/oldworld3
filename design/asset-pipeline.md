# Asset Pipeline: Characters, Bones and Gear

> Part of the Oldworld3 design docs. Status: spike done (section 6). The approach works with
> ControlNet-guided outfits.
> How to use the generation server: [gen3D-server.md](gen3D-server.md).

TRELLIS (on the gen3D server) makes **static meshes**: one fused piece, no skeleton, its own UV
layout per model. A third-person RPG needs animated characters and visible gear. This doc says
how we get from one to the other.

The approach follows WoW Classic: a character is **one fixed body** per body type. Most armor is
**texture** on that body, and only bulky, rigid pieces are separate meshes on bones.

## 1. Base bodies

One base body per body type (v1: human male; later human female, goblin, …). Each is made
**once**, carefully, and reused by every class, NPC and outfit of that body type.

1. Generate it in an **A-pose** (arms about 45° away from the body, legs apart) in plain
   clothes, so limbs don't fuse. `gen3d image --object` with several seeds, pick the cleanest,
   then `gen3d model --image`
2. Clean it in Blender (script):
   - scale to real size (human ~1.85 m), feet on the ground, facing −Y (glTF +Z)
   - **remesh** to a closed (manifold) mesh, then decimate to the polygon budget. Raw TRELLIS
     meshes aren't closed, and Blender's automatic weights fail on them
   - **re-unwrap with our own UV layout** and bake the TRELLIS colors onto it. The UV layout is
     fixed per body type and split into slot regions (section 3)
3. Fit the **skeleton** (section 2) and compute skin weights
4. Export as `.glb`; Godot imports it

## 2. Skeleton and animation

- **One skeleton per body family.** Humanoids use bone names from Godot's
  `SkeletonProfileHumanoid`, so one animation library can be retargeted onto every humanoid
  body (warrior, bandit, later all classes). Quadrupeds (wolf, boar) share a quadruped skeleton
- **Placing the joints:** the body is in a known A-pose, so a script finds the joints from
  horizontal slices through the mesh (crotch, knees, ankles, hips, waist, chest, neck, head)
  and from the arm direction (shoulders, elbows, wrists)
- **Weights:** Blender's automatic weights (bone heat) on the remeshed body, checked in motion
  (shoulders, hips, knees), not only in the bind pose
- **Animations:** keyframed by Blender scripts (as in Oldworld2's `tools/models/rigkit.py`), on
  the shared skeleton: idle, walk, run, jump, two auto-attacks, ability strike, hit, death.
  Godot adds procedural layers: foot IK on slopes, head look-at, an additive flinch on hits,
  blending through `AnimationTree`
- **Later options**, only if needed: an ML auto-rigger on the GPU box (e.g. UniRig, check the
  license) for many creature types. Text-to-motion models are not planned: their training data
  (AMASS/SMPL) usually comes with non-commercial terms

## 3. Gear

Slots are split by how they move:

| Slots | How | Why |
|---|---|---|
| Chest, legs, hands, feet, wrists, waist | **Texture regions** on the base body's UV layout. Equipping swaps that region's texture | Moves with the body perfectly, never clips, needs no extra rigging |
| Head, shoulders, main hand, off hand, belt buckle, knee guards | **Separate meshes**, each attached to one bone (`BoneAttachment3D` in Godot) | Rigid anyway; gives plate armor its bulk |
| Back (cloak) | Later: small mesh with 2–3 bones of its own | The only piece that needs its own motion |

### 3.1 Making an armor texture

1. Generate the whole outfit as a full-body model **in the same A-pose** as the base body
2. Align it to the base body: the same slicing as in section 2 finds its joints, then a
   per-region transform (legs, torso, arms) moves it onto the body
3. Bake its colors onto the base body's UV layout (Blender: selected-to-active, with a ray
   distance a few cm outward and inward)
4. Cut the result into the slot regions. One generated outfit gives a matching chest, legs,
   gloves and boots; slots from different outfits mix because they share the body and layout

### 3.2 Rigid pieces

- Generated on their own (`gen3d model "<helmet>"`), or cut out of an outfit picture: an
  RGBA PNG passed to `gen3d model --image` uses its alpha as the mask, so a helmet or pauldron
  can be masked out of the same picture the outfit came from, in the same style
- Each piece records its bone, offset and scale in the asset manifest

### 3.3 Trade-off

Armor on the deforming slots is only as bulky as the body under it. The rigid pieces make up for
most of that (as in WoW Classic).

### 3.4 Armor layers (2026-11-15)

A texture alone made plate legs look like painted pants. Plate now has **layers**: extra skinned
meshes on the shared skeleton, worn over the body and shown or hidden per gear (WoW's geosets).

- `tools/pipeline/armor.py <body_dir> <set> <out.glb>` builds a set from the base body itself:
  each piece is a shell cut out of the body surface between two heights (so it fits), smoothed
  sideways (the pants' folds go), rounded and pushed out from the bone axis, given thickness
  (Solidify) and hung **rigidly** on its bone, like real plates. Knee cops sit halfway
  between thigh and shin; the skirt is on the hips.
  - `plate_legs`: fauld (waist skirt, snug at the belt, lames), tassets, cuisses, knee cops,
    greaves, sabatons. `plate_shoulders`: pauldrons in lames.
  - `cut(..., arms=True)` allows arm vertices (pauldrons); otherwise vertices mostly weighted
    to the arms are left out (the hands rest against the thighs in the rest pose).
- Per-vertex data for `game/shaders/armor.gdshader`: UV.x = height above the piece's bottom
  edge, color = (inside, lame spacing, trim width, piece height). The shader draws crisp brass
  trim on the top and bottom edges, lames, polish noise and a dark inside. (Vertex colors alone
  gave torn-looking trims: the body mesh is too coarse for a sharp line.)
- Review: `anim_dev.py out --armor spike/body/plate_legs.blend --armor ... clip:view`.
- Game: `Humanoid.set_layer(key, path)` moves the glb's mesh onto the body's Skeleton3D;
  `Player._show_weapons` shows plate legs with plate leg items (or the warrior's default
  look) and pauldrons with a plate chest. The body's own legs slot stays underneath and shows
  only in the gaps (back of the knee).

## 4. Creatures

One rig per creature family (quadruped for wolf and boar, humanoid with other proportions for
the goblin), same steps as a base body: A-pose or standing pose, remesh, own UVs, slicing for
joints, automatic weights. A creature's look is fixed; variants come from new textures or new
generated models on the same rig.

**As built (2026-11-15):** `tools/pipeline/creature_rig.py` rigs a prepared static creature
(`creature.py` output) by geometry, without remesh or bakes; `tools/build_creatures.sh` holds
the settings per creature and writes `<name>_rig.glb` (skeleton, skin, clips) and
`<name>_rig.json` (walk/run speeds at rate 1). The game uses the `_rig` model when there is one.

- **quad** (`style=bite|swipe|gore`, `lie=side`): legs tracked up from the feet to the belly,
  spine from hip to shoulder, neck and head toward the snout, a two-bone tail. Leg bones only
  weigh their own quarter of the body.
- **bug** (`limbs=N`, `claws=N`, `tail=1`, `turn=deg`, `core=f`, `spread=deg`): limbs are the
  peaks of a direction histogram seen from above (mesh islands and thickness failed: spider
  legs touch each other); a limb that is its own piece goes wholly to one direction; above the
  shell counts as limb (raised claws). Three bones per limb, parameterized along the surface.
- **snake**: the raised neck (above ~0.38 H) as a four-bone chain from the coil.
- Weights: inverse distance to the bone segments (power 4, allowed bones only), smoothed over
  the welded surface (glTF splits vertices at UV seams), top 3 kept.
- Clips are keyed procedurally; deaths are grounded by the deformed mesh (quads: the torso
  only, so thick folded legs may sink into the ground instead of propping the body up), limbs
  are laid on the ground by a numeric angle search.
- Review: `preview=<dir> view=side|front|top` renders 6 frames per clip, `weights=1` colors
  vertices by their strongest bone. Previews have no ground: check lying poses in game
  (`--creatures death --creature-t 2`) or measure the lowest point.

## 5. Asset manifest

Every asset records: prompt, negative prompt, the seed passed (not `used_seed`), faces,
texture size, resolution, job id, date, the post-processing script and its settings, real-world
size, and for attachments the bone and offset. The pipeline must be able to rebuild every asset
from the manifest.

## 6. Spike

Goal: prove sections 1–3 before building the game.

1. One base body (human male, A-pose) with skeleton, weights and a walk cycle
2. Two outfits baked onto it, then mixed (outfit A's chest with outfit B's legs)
3. A helmet and a sword on bones
4. Shown in Godot, walking

Questions it answers:

1. Does the A-pose come out reliably from a text prompt? If not, the server needs pose
   conditioning (e.g. ControlNet OpenPose for SDXL)
2. Is a separately generated outfit close enough in shape to the body to bake cleanly?
3. Do the automatic weights deform well at shoulders and hips after remeshing?

### 6.1 Spike results (2026-11-12)

Scripts: `tools/pipeline/` (`body.py`, `outfit.py`, `skeleton.py`, `common.py`,
`debug_joints.py`). Godot test scene: `spike/godot/` (`shot.sh` takes screenshots on a hidden
workspace). Generated files: `spike/` (not meant to be kept).

**Works:**
- Base body from one generated A-pose image: weld, voxel remesh (8 mm), decimate to 24k
  triangles, smart UV, bake the TRELLIS colors (2048²). About 8 s in Blender on the laptop
- Joints by slicing (edge–plane intersections, 2D flood fill per slice): crotch from the
  central parts merging, shoulder top from the width jump below the neck, elbows where the
  arm separates from the torso, hand tips as the lowest outer point. Correct on the test body
- Automatic weights after remeshing: 0 unweighted vertices; the walk cycle deforms hips and
  knees cleanly. Imports into Godot 4.7 with animation and shadows
- Slots as a per-vertex attribute (`slot` color, R = slot / 8 + 1/16, from the dominant
  bone) and a Godot shader that picks each slot's texture from outfit A or B. Regions are
  clean; mixing outfits works
- Outfit bake: the outfit gets its own skeleton (same joint finder), the skeleton is posed
  onto the body's, then colors are baked into the body's UVs. Texels whose rays miss the
  outfit are filled with the body's own color (hit mask), so there are no black holes
- Rigid pieces on bones: placement given in character space relative to the bone's rest
  position (`assets/<piece>.json`: offset, rotation, scale), converted in code. The helmet
  fits after three tries
- Weapons: `weapon.py` aligns the long axis (PCA), finds the handle end by the pommel bump,
  puts the origin on the grip and scales to a real length; the sword then sits in the right
  hand and follows the walk

**Problems found:**
1. **Pose by prompt is unreliable.** 2 of 12 images were usable (body 1/4, plate 0/4, mail
   1/4). The plate prompts ignored "no helmet" and added swords and crops; others had hands
   on hips, arms down or four arms. Outfits generated separately also have other proportions
2. **Alignment limits the bake.** Only 55% of the body's texture was hit by the mail outfit;
   a tabard between the legs moved the outfit's crotch from about 0.83 m to 0.63 m, which
   smeared the legs. Loose parts (tabards, skirts, capes) are lost, as expected
3. **The single-object check passes overlapping objects** (two crossed swords became one
   broken mesh). Generate the image first, check it, then `gen3d model --image`
4. **TRELLIS fattens thin, flat shapes:** sword blades come out cone-like. Acceptable at game
   distance; if not, weapons could get a flattening step or be built from generated parts
5. **Hair pokes through helmets.** Needs a helmet-head variant or a vertex shrink of the
   head under a helmet
6. **Godot test windows** must be matched by window class (the project name), not title, to
   land on the hidden workspace

**Conclusion:** the approach works. Its quality is limited by how well generated outfits
match the base body in pose and proportions. The fix is pose/shape conditioning on the
server: render the base body's depth (or OpenPose skeleton) and use it as a ControlNet input
for SDXL, so every outfit is generated on exactly the body's silhouette (see 6.2).

### 6.2 ControlNet (done 2026-11-12)

The gen3D server now takes a control image (`gen3d image|model --control <png>`, see
[gen3D-server.md](gen3D-server.md#pose-and-shape-control-controlnet)), using
`xinsir/controlnet-union-sdxl-1.0` (Apache-2.0). Peak VRAM 8.3 GB, about 80 s per image.

1. `tools/pipeline/control.py` renders the base body's front depth map (orthographic, near =
   white, front 25 cm of depth mapped, background black) from `body.blend`
2. `gen3d image "<outfit prompt>" --object --control depth.png` gives outfits in exactly the
   body's pose and outline: 2 of 2 knight images usable, both without a helmet as asked
   (before: 0 of 4 plate images usable)
3. The joints of the generated knight match the body's within 2 cm (crotch 0.78 vs 0.80 m,
   shoulder top 1.53 vs 1.52 m); the mail outfit before was 17 cm off at the crotch

Fixes found on the way:
- The spine's depth now comes from the legs just below the crotch; a waist slice picked up a
  belt flap and moved the outfit's spine 14 cm back, which tilted the wrapped torso
- Cycles' diffuse color pass is base color × (1 − metallic), which baked steel as black.
  The color bake now switches metallic off on the source, and a second bake carries the
  metallic/roughness texture (`<name>_mr.png`, glTF layout). The Godot shader reads both per
  slot, so plate armor looks like steel

Result: the knight's plate covers the body front and back, the belt line matches, metal shines,
and chest and legs mix with other outfits. Remaining:
- Folds of the base body's shirt are part of its geometry and show through as streaks under
  plate. Make the base body from a tight, plain outfit (or a smoothed body) so armor reads clean
- Small gaps on the forearms where the armor is far from the body
- Armor follows the body's silhouette closely (control_scale 0.7, control_end 0.8); bulkier
  plate may need a lower scale or end, at the cost of alignment. To try
- An OpenPose control image (from the found joints) is not made yet; depth worked well enough

### 6.3 Normal maps (2026-11-13)

`body.py` and `outfit.py` also bake a tangent-space normal map (`body_normal.png`,
`<outfit>_normal.png`) from the generated high-detail surface onto the base body. The game's
body shader takes the normal map per slot, like color and metallic/roughness. This puts plate
edges, mail and straps into the shading, and it cancels the folds of the base body's shirt under
armor (the map reproduces the outfit's surface direction). Detail is limited by the source
outfit: a prompt asking for articulated plate, mail at the joints, straps and buckles gives
far more than "plate armor".

### 6.4 Built from shapes (2026-11-13)

Thin, flat objects come out thick from TRELLIS (the sword looked like an umbrella), so weapons
are built by Blender scripts: `tools/pipeline/sword.py` (sword, dagger, short sword by blade
length), `staff.py` (crystal color), `mace.py`, `axe.py` and `bow.py`. Outfits: every class,
every humanoid enemy and the village people; `tools/build_characters.sh` rebuilds the base body
and re-bakes all of them.

### 6.5 Preparing generated props (2026-11-13)

- `tools/pipeline/creature.py`: four-legged creatures (body along the forward axis, real length,
  feet on the ground; the head end is guessed, `flip` reverses it).
- `tools/pipeline/prop.py`: everything that stays upright (floating spirits, bushes, props),
  optionally cutting off the bottom part first: TRELLIS often adds a base, a soil mound or a
  flower pot (`prop.py in out height 0.3`).
- `tools/pipeline/seamless.py`: ground textures made tileable. Grass textures must show **very
  short** grass, or the blades look like they lie flat on the ground: "seamless texture of very
  short closely mown (dry / withered) lawn grass seen from directly above, dense tiny upright
  grass blades, ..." works ("short grass" alone still gives long blades). Old textures in
  `spike/img/v2/old_terrain/`.
- **Skin showing through armor:** where the bake ray (0.15 m) misses the generated outfit, the
  texel falls back to the base body, so a sleeve sitting a little off the arm showed a bare
  forearm. `outfit.py ... <height> <reach_m>` bakes those misses again with a longer ray
  (`reach` 0.4 for the plate, set in build_characters.sh; it filled 1.9% of the texture) and only
  then falls back to the body. Opt-in, because outfits with bare arms (berserker) would get
  torso colors on them. Backups of the old plate maps: `spike/body/plate_*.png.bak-reach`.
- `tools/pipeline/shrub.py`: SDXL draws a small tree for every "bush" prompt (even with a
  negative prompt; ControlNet would help but needs more VRAM than is free while the box is
  gaming). The shrub (`nature/shrub.glb`, the Unholy bushes) is built instead from the generated
  bush: its canopy cut off the stem, six copies turned, scaled and leaning outward, merged into a
  low mound whose leaves reach the ground.
- Colors that came out wrong (the "dark" pines were frosty) are fixed in the game with a per-kind
  `tint` in `scatter.gd` rather than regenerating.
- Prompts that fail: groups of things (a bat swarm) touch the image border; ask for one object.
  "No pot" in a prompt still gives a mound of soil; cut it off.

### 6.6 Animations (2026-11-13)

- All humanoids share the base body's skeleton and clips (idle, walk, run, jump, attacks, hit,
  cast, death), keyed in `tools/pipeline/skeleton.py`.
- Locomotion comes from per-joint curves over the gait cycle (`RUN_LEG`, `WALK_LEG`; degrees
  from human gait data) through `make_cycle`. The body is lowered so the standing foot touches
  the ground; flight phases follow an arc.
- Iterate with `tools/pipeline/anim_dev.py` (renders side/front/back/three-quarter strips in
  seconds, `--export` writes `spike/body/body.glb`; copy it to
  `game/assets/characters/warrior/body.glb`).
- `tools/pipeline/rerig.py` re-detects the joints and re-weights without changing the mesh or
  UVs (the outfits stay valid).
- **Whole-body poses (2026-11-14):** `_full(upper, twist, pitch, left, right, shift)` builds a
  pose where the pelvis turns (`twist`) and tips (`pitch`) over planted feet: the thighs carry
  the opposite rotation, so the legs keep their direction in the world. Legs are
  `(thigh, knee, ankle[, adduct])`. `make_clip` keys with `hips_drop` None lower the body until
  the lowest foot point is on the ground; `"body"` does the same for the whole body (falling,
  lying; bone lines widened by `_BODY_MARGIN`). Attacks, the combat stance (`_guard`, the
  "ready" loop), cast, hit, death and idle use them.
- **Pose experiments:** `ANIM_TEST=<dir>` makes anim_dev import `<dir>/anim_test.py` and call
  its `add(rig)`, which can add variant clips to render (or search a rotation numerically, e.g.
  the hand rotation that points the blade forward).
- `anim_dev.py --sword` holds the warrior's sword in the review renders.

### 6.7 Generated motion (MoMask, 2026-11-13)

- **Model:** MoMask (CVPR 2024, code MIT), text to motion, installed on the GPU box (own venv,
  outside the gen3d container; the path is in `design/local/gen3d-access.md`). It also runs on the box's CPU in about
  6 s per clip, so it doesn't need the GPU while the user games. HY-Motion 1.0 would be stronger,
  but its license excludes the EU.
- **Generate:** prompt files `game_src/motion/batchN.txt` (`name | prompt | seconds | repeats`),
  run the box's `gen.sh` on it over SSH (`design/local/gen3d-access.md`), copy the
  `.npy` joint arrays (frames × 22 × 3, SMPL joints, 20 fps) to `game_src/motion/batchN/`.
- **Retarget:** `tools/pipeline/motion_retarget.py` turns each bone toward its motion segment
  (swing in world space), with a calibration from a generated standing pose for the torso and
  feet (`spike/motion/calibration_idle.npy`). Loops are cut to one stride cycle from the steady
  part and kept in place; jumps keep only the airborne part. `STRIDE` lengthens the run's
  stride (generated sprints reach ~4 m/s, the game runs at 7) and `STANCE` narrows the idle.
- **Review:** `tools/pipeline/anim_dev.py out --motion game_src/motion/batchN run_1:side …`.
- **Use:** copy the chosen clip to `spike/motion/<clip>.npy` (run, walk, jump, idle so far);
  `anim_dev.py … --export` builds body.glb with them (hand-keyed clips remain for the rest:
  attacks, casts, hit, death). Set `CharAnimator.CLIP_SPEED` to the export's printed speeds.
- Prompts that worked: "a person sprints forward in a straight line as fast as possible",
  "a man walks straight ahead at a normal speed", "a person runs forward and jumps up high,
  then lands and keeps running". Plain "walks forward" often walks on the spot or in a circle.

### 6.8 Generated music and sounds (2026-11-26)
Until now every sound and track was synthesized in code (tools/audio/makeaudio.py). Generated
audio comes from models on the GPU box, set up like MoMask (own uv venv under `/data/audio`,
outside the gen3d container; `/data/audio/DOC.md` there).
- Music: ACE-Step 1.5 (MIT; outputs ours). `ssh <gpu box> 'cd /data/audio && ./gen_music.sh
  <prompts.txt> <out_dir>'`, prompt lines `name | caption | seconds | takes [| bpm]`
  (tools/audio/prompts/). Instrumental only; turbo model with the 0.6B planning LM (12 GB tier).
  ~35 s to load, then about 10-20 s per 30 s of music. Output 48 kHz stereo FLAC + .json (seed).
- Sound effects: generated ones didn't work. MOSS-SoundEffect v2.0, EzAudio (MIT) and Dasheng-
  AudioGen (Apache) were tried and removed: distorted, nothing like the prompt, or the prompt
  read aloud by a voice (trained on everyday recordings, not game sounds). Stable Audio was left
  out (gated, revenue-limited license). The effects are synthesized: tools/audio/makeaudio.py,
  hits by weapon and surface (hit_<weapon>_<surface>1..3: flesh, metal, bone, chitin, spirit).
- Picking: copy a batch to the laptop, `python3 tools/audio/listen.py <dir>` writes a listening
  page; the user picks takes (Claude can't hear them; it checks length, loudness, clipping).
- Into the game: trimmed, loudness-normalized, music looped, as the same file names in
  game/assets/audio (so no code changes).
- Not used: MusicGen, YuE2, MMAudio, Sony Woosh (non-commercial weights).

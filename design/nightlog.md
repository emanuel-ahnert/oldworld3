# Night log 2026-11-13

What was built overnight while the user slept, in order. Start the game from VS Code
("Oldworld3 (desktop 9, fullscreen)") as before; it now opens a title screen.

## How to play now

- **Title screen:** Continue (if a save exists), New game (world seed, empty = random), Quit.
  Esc in the game (with no target) saves and returns to the title.
- **Combat (WoW Classic style):** Tab targets the nearest enemy in front; left-click selects,
  right-click on an enemy attacks it; F toggles auto-attack; 1–6 are the warrior's abilities.
  Rage fills from hitting and being hit.
- **Abilities** (unlocked by level, see design/classes.md): 1 Heavy Strike, 2 Battle Cry,
  3 Overwhelm (lights up after a miss in a bandit's smoke), 4 Thunder Clap (level 4),
  5 Charge (level 6, from 8–25 m, out of combat), 6 Rend (level 10). Passives: Enrage (3),
  Second Wind (8).
- **Checkpoints:** walking up to the inn or a road shrine outside of combat sets the respawn
  point and heals fully. On death you wake up there and lose 10% money and the level's XP.
- Test arguments (VS Code "other seed" config passes `--seed`): `--level N` starts at a higher
  level, `--fight wolf|boar|goblin|bandit` starts next to a group and fights automatically.

## Done

1. **Trees:** beech, linden and birch generated ("3D render" prompts), weighted 35/30/25%;
   the gnarled oak is now the rare 10%.
2. **Sword:** built from shapes in Blender (`tools/pipeline/sword.py`) because TRELLIS makes
   blades cone-shaped. Also a dagger and a short sword for enemies.
3. **Helmet:** smaller and tighter; the head shrinks under it in the shader (WoW style), so
   hair doesn't clip.
4. **Run:** shins turned inward too, so the feet stay under the body.
5. **Animations:** three sword swings, a heavy strike, hit reaction, death, combat stance
   (`tools/pipeline/skeleton.py`, `make_attacks`). Played through an AnimationTree: on the
   whole body when standing, the legs keep running while the upper body swings when moving
   (`scripts/character/char_animator.gd`).
6. **Combat system:** `scripts/combat/` (formulas from design/mechanics.md, Combatant with
   health, rage, buffs, damage over time, regeneration), the warrior's abilities in
   `scripts/player/player.gd`, floating combat text, target ring.
7. **Enemies:** wolf and boar (generated, procedural trot/lunge/fall), goblin and bandit
   (humanoids on the base body, sharing all animations). AI: aggro by radius and level,
   group pulls, chasing, spreading around the hero, leash at 40 m, respawn after 5 minutes.
   Special abilities: Howl, Tusk Charge, Sling Stone, Poisoned Blade, Smoke Screen. About 90
   enemies in 38 groups, placed by habitat; bandit camps with tents near roads.
8. **Settlement:** inn north of the plaza, houses around it, checkpoint shrines halfway along
   the roads, all generated models with collision.
9. **HUD:** hero and target frames, rage, action bar with cooldowns and greyed-out abilities,
   XP bar, money, messages ("Out of range", "Not enough rage").
10. **Saving and title screen:** `user://save/hero.json` (in Godot's user data directory), written on level-up, checkpoint,
    death, every 30 s when moving, and on quit.
11. **Performance:** ~30 FPS in the benchmark with all enemies (34 without); idle enemies far
    away sleep.

12. **Lakes:** two or three shallow lakes per zone with irregular shores, sand, animated water
    (`shaders/water.gdshader`); the hero can wade through. Goblins camp by the water.
13. **Audio:** music and sound effects synthesized by Oldworld2's generator, copied to
    `tools/audio/makeaudio.py` (our own code). Music follows the situation (zone, village,
    combat, elite combat, death). Test runs are muted.
14. **Zone name:** "Commons of Willowshaw" etc. (Oldworld2's name lists), shown when entering.
15. **Bandit and goblin outfits** generated with ControlNet and baked; goblins are 72% scale.
    `tools/build_characters.sh` rebuilds the body and re-bakes every outfit.
16. **Second class: Mage.** Choose it on the title screen. Mana (regenerates 5 s after the last
    spell), cast times with a cast bar (moving interrupts), projectiles. Spells: 1 Fire Bolt
    (free filler), 2 Ice Bolt (slows), 3 Frost Ring (roots everything around, level 2),
    4 Mana Shield (half the damage goes to mana, level 3), 5 Ignite (burn, level 4),
    6 Blink (15 m teleport, level 6). Magic damage uses the element chart: fire hurts goblins
    and bandits (Dark) double, ice hurts boars (Nature) double. Outfit: blue embroidered tunic
    (the texture approach can't do long robes: they need their own geometry), staff with a
    glowing crystal (`tools/pipeline/staff.py`).

17. **Zones:** the world is a grid of 512 m zones now. North of the start lies the **North**
    (snow, pines, frozen lakes, longhouses, Nordic music, Norse names, difficulty 2). Run
    through the gap in the cliffs where a road leaves the zone; the neighbor zone is built in
    the background as you approach (no freeze). North enemies: snow wolves, frost wisps (ranged),
    ice trolls, berserkers (elite). See design/world.md, section 7.
18. Docs updated: design/world.md (7), design/classes.md (3, Mage), design/asset-pipeline.md (6.4).

19. **Third class: Rogue** (title screen): energy, Stealth, daggers in both hands, Knife Throw,
    Poisoned Blade, Cheap Shot, Gut Slash, Cheat Death. See design/classes.md, section 4.
20. **Third zone type: Desert** south of the start (the first ring stays Grassland with 30%
    chance, so for seed 1 the Desert begins two zones south): sand, sandstone paths, red rock,
    palms, cacti, dry shrubs, oases, domed houses; sand snakes, scorpions, ember spirits
    (ranged fire), nomad raiders (elite, Fire Brand burn, Sand Veil smoke). Arabic-style names.
21. **North outfits:** ice trolls (1.35× scale, blue skin) and berserkers (tattoos, fur).
22. **Minimap** (top right): the zone's roads, lakes, settlement, shrines, crossings, nearby
    enemies (red when fighting you) and your direction.
23. **Camera** no longer ends up inside tree crowns (canopies collide with the camera only).
24. Balance: trash enemies hit a bit harder (80% instead of 60%), after automated test fights
    showed a level-1 warrior finishing a wolf pack at full health.

25. **All nine classes playable:** Priest, Paladin, Warlock, Hunter, Shaman and Druid joined
    (design/classes.md, section 5). New mechanics: absorb shields, immunity, drain, silences,
    roots, elemental melee, a bow with Auto Shot, totems placed in the world, and the Druid's
    Bear Form (the model turns into a bear). Weapons built in Blender: mace, bow, a green-glow
    staff; a generated shield with a sun emblem. `shots/classes.png` shows all classes.

26. **Five zone types:** the Mediterranean (west: olive groves, cypresses, white houses; giant
    crabs by the water, wind spirits, corsairs with pistols, bronze hoplites) and the Unholy
    lands (east: dead trees, dark pines, gravestones, gothic houses and crypts, dim reddish
    light; dire wolves, bat swarms that dodge half of all melee hits, cultists casting dark
    bolts, vampires that drain life and mesmerize). Their assets were still generating at the
    time of writing; missing models fall back to similar ones.
27. **In-game menu (Esc):** Resume, Quality (Low / Medium / High: render scale and shadow
    distance, saved in user://settings.cfg), Save and back to the title, Save and quit.
28. Nameplates show health in percent during fights; level-ups announce new abilities.
29. `README.md` in the project root: how to play, controls, layout.

30. **Items:** loot drops (elites 60% gear, trash 7%), a 20-slot bag, nine equipment slots,
    rarities with suffixes ("Iron Gauntlets of the Boar"), armor types per class, Healing
    Potions (R; three to start), and a merchant at every inn (buy and sell in the bags window,
    B or I). Money in bronze/silver/gold. Equipped weapons and shields show in the hero's
    hands; armor changes the numbers only. See design/items.md.

31. **Quests:** each inn's notice board posts three hunting quests for its zone (taken on when
    arriving, tracked under the minimap, handed in at the inn for XP, money and a green item;
    then the next round). See design/quests.md.

32. **Champions:** one named, bigger, tougher elite per zone with guaranteed good loot and an
    orange map marker (design/world.md, 7). A level-6 warrior and a level-5 mage each beat the
    start zone's champion in a test fight.
33. **Mediterranean assets in:** dry golden grass, pale pebble paths, olive trees, white houses,
    a villa (inn), giant crabs, wind spirits, corsair and hoplite outfits. A first cypress came
    out as a common pine and the lavender stood in a flower pot (cut away); better ones are
    queued (batch 8). `tools/pipeline/prop.py` prepares upright props and floating spirits.
    Batch 8 delivered a proper slim cypress, lavender without the pot, and a giant bat for the
    bat swarms.

34. **Unholy assets in:** withered grass, dark cobbled paths, dead trees, dark pines (tinted
    darker in the game; they came out frosty), gravestones (mossy base cut away), gothic houses
    and crypts, dire wolves, cultist and vampire outfits. The zone has a dusky violet sky now
    (sky colors are part of the zone type). The bat swarm model failed (a swarm never fits the
    image); a single giant bat is queued.
35. **Sixth zone type: Ancient Desert** (Oldworld2's Egyptian desert): a desert zone is the
    Middle Eastern or the Ancient Desert by smooth noise over the grid, so neighbors share
    the theme. Two pyramid groups per zone (big pyramid, two small ones, a sphinx or a pharaoh
    statue; triangles on the minimap), obelisks before the temple (inn), mud-brick houses,
    Egyptian names ("Necropolis of Khepermose-Amenti"). Enemies: scarab swarms (Hard Shell),
    cobras (spit venom from 12 m), mummies (Wrap slows, Ancient Curse lowers Attack) and tomb
    guardians (elite, near the pyramids; Sun Strike, Sacred Ward). All models generated
    (batches 9 and 10): pyramid, obelisk, sphinx, a seated pharaoh, column temple, mud-brick
    house, scarab, cobra, mummy and tomb guardian outfits. Screenshot: `--zone 1,1 --landmark`.
36. Bag tooltips compare an item with the equipped one ("Instead of Iron Helm: +2 Defense").

37. **World map (M):** the 9×9 zones around the hero; visited zones show name, type and
    difficulty, their neighbors only the type's color, the rest is unknown. Pyramids mark the
    Ancient Desert. Visited zones are saved.

38. **Inn square:** a notice board (quests) and a market stall (merchant) in front of every inn;
    village people: a merchant at the stall, two villagers strolling over the plaza and
    turning to face the hero (outfits from batch 10).

39. **Axe** built in Blender (`tools/pipeline/axe.py`: ash haft, bearded crescent blade, back
    spike), shown when an axe is equipped.

40. **Day and night:** a 40-minute day; the sun moves east to west, sunrise and sunset glow
    orange, nights are moonlit blue (a third of the light, still playable). Saved with the hero;
    the Esc menu switches it off (fixed morning light). Test runs use the fixed light unless
    `--time 0..1` is given. The sky is only updated every ~1.2 s (updating it every frame
    re-rendered its radiance map and cost 3 FPS); nights get a bluish ambient fill.
41. Fix: leveling up in Bear Form no longer resets the bear's Attack.

42. **Freeze fixed (important):** the game could hang for good when a neighbor zone was being
    built in the background while the renderer compiled a new material (first Fire Bolt, first
    arrow near a zone border). The worker thread made meshes and loaded models while the main
    thread held the renderer lock and waited for a compile task: a deadlock (found with gdb:
    both threads blocked in the same lock). Zones are now built in two parts: the worker
    computes only data (heights, roads, lakes, where trees grow); the meshes, buildings, trees
    and enemies are made on the main thread, one step per frame (`Zone.compute` /
    `Zone.build_step`, `ZoneManager._process`). Found by a class sweep (all nine classes
    against hoplites at level 8): mage and hunter runs hung near the border.
43. Class sweep at level 8 against a hoplite group (2–3 elites, level 9–10): warrior, paladin,
    warlock, shaman and druid win; rogue, priest, mage and hunter die. Elite groups are meant
    for careful pulls or groups, as in WoW; trash and single elites are soloable.

44. **Champion modifiers** (Oldworld2): each champion is Burning (fire aura, orange glow),
    Swift (40% faster, swings faster), Shielded (absorbs a quarter of its health, renewed every
    30 s), Thorned (reflects 15% of melee damage) or Winged (dodges half of all melee hits),
    shown on the nameplate ("Thessa the Grim 11 (Shielded Champion)").
45. Fix: enemies no longer spawn inside pyramid groups (a champion was pushed through the
    ground by a pyramid's collision). Test runs print how many enemies are below the ground
    (0 in all six zone types).

46. **Spell book (P)** and **action bar tooltips:** every ability's level, cost, cooldown and
    what it does, and the class passives; abilities not learned yet are greyed out. The texts
    are generated from design/classes.md (`tools/docs/ability_text.py` writes
    `game/scripts/player/ability_text.gd`), so the doc stays the single source.
47. **Grassland creatures:** black bears (solitary, defensive, Savage Bite; the druid's bear
    model) and giant spiders (packs deep in the woods, Venom Bite, Web roots the hero for 3 s
    from up to 15 m).

48. **Title screen:** a picture from the game as backdrop (the pyramids at dusk, rendered with
    `--nohud --time 0.745`), the menu in a dark panel; subtitle "Nine classes · six lands · one
    endless world".

49. `game_src/manifest.json` lists every generated asset now (78): prompt, seed, faces, job id
    and server folder, filled from the batch scripts by `tools/docs/manifest.py`.

50. **Treasure chests:** three per zone (one by an elite camp, others hidden near the woods, one in
    front of a pyramid in the Ancient Desert). Walk up to one outside of combat: money, often a
    potion, often an item of the zone's level. Opened chests stay open (saved). The minimap
    shows chests within 40 m. Models from batch 12 (closed and open). Test: `--chest N`.
51. Soak test: a warrior fighting for 3 minutes, and mage, hunter and warlock crossing a zone
    border: no script errors or warnings.

52. **Visible headgear:** a head item shows on the hero by armor type: plate helm, chainmail
    coif, leather cap, cloth hood with a short cape (batch 13; per-model fit in
    `Humanoid.HEAD_FIT`); hair is hidden under it. Test: `--class mage --head cloth`.

## 2026-11-13, afternoon (feedback round 4)

53. **Title menu:** keyboard navigable (arrows, Enter; the focused button has a gold frame),
    world seed 42 by default (editable; empty = random), and a **start zone** choice like
    Oldworld2: Grassland, North, Desert, Ancient Desert, Mediterranean or Unholy lands. The
    game starts at the inn of the nearest zone of that type, which becomes difficulty 1;
    difficulty rises by ring around it (`ZoneTypes.home`, saved). Test: `--start north`.
54. **Sword, dagger and axe** turned 90° about the blade: the edges point up and down when held
    forward (the flat side faced up before).
55. **Helmets** fit tighter (scale 0.36 → 0.28) and the head shrinks fully under them, so no hair
    pokes through (WoW hides it). The leather cap (it showed the hair and squashed the face) is
    replaced by a leather cowl; coif, cowl and hood shadow the face.
56. **Walk and run rebuilt** (all humanoids share them: hero, enemies, villagers):
    - The hip joints sat 10 cm too low (the legs pivoted from mid-thigh: the waddle). Fixed in
      the joint detection; `tools/pipeline/rerig.py` re-rigs the body without touching its
      mesh or UVs, so every baked outfit stays valid.
    - Cycles from human gait data (`skeleton.make_cycle`, curves `RUN_LEG` / `WALK_LEG`): run
      with short stance (22%), flight phase and heel recovery, the pelvis tipping forward with
      the trunk instead of the backside sticking out, pelvis and shoulders counter-rotating,
      arms driving past the hips; walk with heel strike, roll-over, push-off and loose arms.
    - The thighs are pulled in and the knee hinge kept horizontal, so the feet land under the
      body and the heel comes straight up behind (it swung out sideways before).
    - Review strips: `tools/pipeline/anim_dev.py out run:side run:back walk:front …`;
      `--export` writes body.glb.
57. **Jump animation:** push-off, tuck, opening for the landing, held while falling; played
    whenever the hero is in the air (`--jump` test).

58. **Title screen in Oldworld2's style:** a cursor (◆) list instead of buttons. Main page:
    Continue, New game, Quit. New game: Class < … >, Zone < … >, Seed, Start, Back; Left/Right
    change a value, digits type the seed (Backspace deletes; the first digit replaces the
    default 42), Esc or B goes back; below, the class's description, affinities and starting
    abilities, and the class's hero stands in a frame on the right. Starting over a save asks
    first. W/A/S/D work like the arrows; the mouse still works (hover, click). The Esc menu in
    the game focuses its first entry, so arrows and Enter work there too.

59. **Generated animations:** MoMask (text to motion, MIT) installed on the GPU box
    (its own environment; runs on the CPU too). Run, walk, jump and idle are now
    generated motion retargeted onto our skeleton (`tools/pipeline/motion_retarget.py`), chosen
    from several variants each; the run's stride is lengthened to fit the game's 7 m/s, and the
    playback rates follow each clip's measured speed (`CharAnimator.CLIP_SPEED`). Attacks, casts,
    hit and death are still hand-keyed (next: generate those too). See asset-pipeline.md 6.7.

60. Fixes after playtesting: the generated clips no longer hover (the body is lowered until our
    own foot bones touch the ground) or lean to one side (each clip's average sideways lean and
    hip turn are removed; the calibration only corrects forward/back). Helmet a bit wider and
    further forward, head shrunk to 45%: the face no longer pokes out on the left. Zoom also
    with "-" (out) and "." (in), by the printed key, so it works on a German layout. The title
    background follows the chosen start zone (one picture per zone type, made with --nohud).

61. Helmet: the head shrink now starts below the chin and pulls toward the head's centre, so the
    chin no longer pokes out of the visor. The plate outfit had a bake miss on the back (a brown
    spot that looked like the body showing through): painted over with a smooth fill
    (`tools/pipeline/fix_plate_back.py`, run by build_characters.sh after the plate bake).
62. Generated locomotion parked (`spike/motion/parked/`): even with a twist fix in the
    retargeting (knees and elbows bend in their own plane) MoMask's run looked crippled in play.
    The hand-keyed gait cycles are back. Generated attacks were tried too (batch 3) but rarely
    read as sword work.
63. **Attacks re-keyed** with the sword visible in the review renders (`anim_dev.py --sword`, GIFs
    with `view+gif`): attack1 a diagonal slash (wind-up over the shoulder, down across the body,
    follow-through to the left hip), attack2 a horizontal slash from right to left, strike a heavy
    overhead chop. The chest and spine turn into each blow (the game plays attacks on the upper
    body only). The sword hand holds the blade down-forward in idle, walk and run (it stuck out
    horizontally). Review GIFs in `spike/anim_compare/`.

64. **Camp** (Oldworld2): C while standing still lights a camp fire in front of the hero (the
    camp-fire prop, a particle flame and a flickering orange light, the "light" sound and then
    crackling) and the hero sits down (new hand-keyed "sit" clip). HP regenerate 10% and mana 20%
    of the maximum per second. Moving, turning, jumping, an ability, a hit or C again breaks camp;
    enemies can still find a resting hero. Test: `--camp` (HP at a quarter, then camps).
65. Run and walk from behind: the lower legs no longer angle outward (shin splay -8° -> -1/-2°).
66. **Unholy lands as a haunted forest** (design/world.md): denser dark forest, tinted dark
    bushes among the gravestones, olive grass, pale green light and thick green mist; glowing
    eyes flare up in bushes ahead and are gone again, never in a bush the hero is close to.
    Benchmark: 29 FPS (grassland 31).

67. Unholy bushes are real shrubs now (`tools/pipeline/shrub.py`): low leafy mounds down to the
    ground instead of little trees; the eyes peer out of their sides.
68. **Short grass:** new grass textures for Grassland, Mediterranean and Unholy lands (short turf
    seen from above; the long blades looked like grass lying flat). Fixed a bug from item 66: the
    new terrain tint read every zone's `ground_tint` (white, alpha 1) and turned the grass grey;
    the Unholy tint is its own key `grass_tint` now.
69. Any attack ability pressed with a live target starts auto-attack, even when the ability
    itself can't be used yet (not enough rage, cooldown, range); buffs (Battle Cry, Stealth,
    Mana Shield, Blink) don't. Struck without a target, the hero targets the attacker, now also
    when the blow is absorbed or the hero is immune (new `Combatant.attacked` signal). Tests:
    `--fight KIND --notarget` (no target, no fight bot), `--press N` (ability key at frame 450);
    STATE prints the target and auto-attack.

70. **Jump starts sooner:** the clip tucks the legs after 3 frames instead of 5 and the blend
    into it takes 0.05 s instead of 0.2 s (`CharAnimator.set_move`); falling switches to it
    after 0.15 s instead of 0.25 s.
71. **Left forearm showed skin through the plate:** a bake miss filled with the base body;
    misses now get a second, longer-reaching bake first (design/asset-pipeline.md 6.5).
72. **HUD:** the XP bar sits right under the action bar, as wide as it, with the numbers on it;
    money and potions below. **Cooldown clock** (WoW style): a dark pie over each button for
    the part of the cooldown still to run, shrinking clockwise from 12 o'clock with a bright
    hand; the ability's own cooldown or the global cooldown, whichever ends later. Test:
    `--press N --press-at FRAME`.

73. Bush eyes subtler: smaller, dimmer (and dimmed by the mist), shorter, every 1.5–5 s, at
    most two.
74. Title screen: the main page shows the picture of the zone type the saved game continues in
    (`title_<type>.jpg`); without a save the pyramids. New `title_unholy.jpg` (haunted forest).
75. **Camp: sitting on the ground** (no more crouch): seat on the ground, legs out in front with
    the knees a little up, hands toward the knees; the fire sits 1.8 m ahead, past the feet.
    `anim_dev.py` prints the body's lowest point and the seat height at a clip's last frame
    (GROUND), which is how the hips drop was set (both 0).
76. **Ground variety** (terrain shader, one tileable noise texture): drier yellowish and darker
    grass patches, ragged bare-soil spots and fine soil grit between the blades (plain soil
    `dirt.png` in every zone, olive and darker in the Unholy lands); amount per zone `bare`
    (0.5 default, Mediterranean 0.7, Unholy 0.9); off on snow and sand.
77. **Ground clutter** (`world/clutter.gd`, `shaders/clutter.gdshader`): grass tufts in clumps,
    a few flowers and pebbles around the hero in 12 m chunks, colors per zone type, lit like the
    ground (world-up normals), swaying in the wind, shrinking away at the edge. Amount by the
    graphics quality: Low 14 m / 0.35, Medium 20 m / 0.55, High 36 m / 1.3 (radius, density).
    Benchmark: Low 30.5, Medium 29.6, High 28.6 FPS (before: 30.9). Test: `--quality NAME`.

78. An enemy that evades (leashes home) shows "Evade" and is dropped as the hero's target
    (auto-attack stops). Test: `--fight KIND --flee` (the hero jumps 70 m away at frame 200).
79. **Escape menu** in the title screen's style: Up/Down (W/S) choose, Left/Right (A/D) change
    Quality and Day and night, Enter/Space select, Esc close; mouse hover and click work too.
80. **Low quality: no sun shadows**, round blob shadows under the hero, enemies and villagers
    instead (old WoW style, `world/blob_shadow.gd`; they stay on the ground when jumping).
    Benchmark: Low 39.3 FPS (scale 0.6), Medium 30.0 (scale 0.75).
81. **Mountains:** the border rim follows ridged noise in world coordinates (peaks, ridges,
    saddles, 32–94 m, craggy foothills; both zones still meet at the same height). New cliff
    textures (`cliff.png`, layered strata, on steep faces; `cliff_top.png`, rough rock with
    lichen, seen from above) for Grassland, North, Mediterranean and Unholy lands; the rock at
    two scales, warm/cool tints over the range, broad darker layers, snow caps above the zone's
    `snow_line` (Grassland 82 m, North 40 m). Medium: 27.8 FPS (was 30.0).

82. **Enemies didn't attack** unless they were being pushed apart from a group mate: facing the
    hero and the swing timer sat inside the separation branch (a lone bat swarm never attacked,
    cultists rarely). Now every enemy in reach faces the hero and attacks on its swing timer.
83. Flying creatures (bat swarm, wisps) die by dropping out of the air, tumbling onto their side,
    then shrinking away after 2 s (they floated tilted in mid-air before).
84. An attack ability with no target picks the nearest live enemy within 30 m (ones behind the
    hero count 15 m farther; evading ones are skipped), then starts auto-attack as before.
85. Turning on the spot (keys, mouse steering; enemies turning to face the hero) plays the walk
    cycle slowly as shuffling steps. Test: `--turn`.

86. Middle mouse button re-centers the camera behind the hero (default angle).
87. **Passives from Oldworld2** completed: rogue Prey on the Weak (level 8: +10% crit chance per
    level above the target, up to 100%; `Combatant._crit_vs`) and Poison Resistance (level 10:
    poison ticks do 75% less), druid Thorns (level 4: a melee hit costs the attacker 1/16 of the
    druid's max HP). Enrage, Second Wind, Improved Sprint, Cheat Death, Demon Armor and the
    shaman's totems already existed.
88. **Abilities menu** (P or N, replaces the read-only spell book; Oldworld2 game-design 7.3):
    the 6 action-bar slots on the left, every class ability (greyed until learned) and the
    passives on the right, details of the selection below. Keyboard: Up/Down, Left/Right switch
    sides, Space puts a known ability into the first free slot or lets you pick the slot (one
    already on the bar swaps), Space on a slot takes it off, Esc cancels/closes; mouse too.
    Pauses the game. The loadout (`Player.loadout`, slot -> ability id; each ability's `key` is
    its default slot) drives keys 1–6 and the action bar and is saved. Tests: `--spellbook`,
    `--keys down,space,...` (key presses from frame 40, every 4 frames).

89. **Passive slots:** actives and passives don't share slots: 6 active slots (keys 1–6) and 3
    passive slots, both set in the abilities menu, now on **N** only (P no longer opens it). A
    passive works only while learned and slotted (`Player.has_passive`); a newly learned one
    goes into a free passive slot by itself (rogues have four passives, so one waits outside).
    Saved as `passives`; older saves fill the slots with the learned ones. This also fixed
    Enrage and Second Wind, which had been given to every class by level.

90. Camp breaks only on direct hits; damage-over-time ticks (poison, bleeding, burning) don't
    end the rest (`Combatant.ticking`). Test: `--camp --dot`; STATE prints `camp`.
91. The loading screen shows only "Loading..." over the title picture of the zone that is
    loading (the start, saved or test position's zone type). `--loading` keeps it up for a shot.
92. **Whole-body animations.** Standing attacks now use the whole body: the weight goes back
    onto the right leg in the wind-up, the pelvis turns away and then drives the blow over planted
    feet, the left foot plants forward and the knees bend (the body is lowered so the feet stay
    on the ground). The heavy strike rises onto the back leg and steps into a deep lunge. New: a
    thrust (`attack3`; auto-attacks go slash, slash, thrust), a combat stance ("ready" loop,
    sword held forward, knees soft) while fighting, for the hero and humanoid enemies, a
    stagger step in the hit reaction, a cast and release with the feet set, an idle with a slow
    weight shift, and a new death (the knees buckle, the body drops onto its seat, rolls back
    flat, the sword lies on the ground). CharAnimator fires two one-shots: the whole body one
    fades out as soon as the character moves, so running swings keep the run cycle. Hit
    flinches no longer cut off a swing. Fixed: the `--fight` test bot wasn't running (a call
    ended up on a comment line in item 90). Tests: `--swing CLIP`, `--burst N --burst-step K`.
93. **Armor layers (WoW style).** Plate legs are real geometry now, worn over the pants: a waist
    skirt, tassets, cuisses, knee cops, greaves and sabatons, plus pauldrons. They're steel
    shells cut from the body's own surface, each rigid on its bone, with crisp brass trim and
    lames (`tools/pipeline/armor.py`, `shaders/armor.gdshader`, `Humanoid.set_layer`). They show
    with plate items (and on the warrior by default) and are hidden otherwise.
    **Attacks:** a weapon trail (`WeaponTrail`) during the cutting part of each swing. The head no
    longer pokes out of the helmet in fast blows (the head shrink used the previous frame's pose).
    **Deaths:** a second humanoid death (`death2`: spun around, onto the knees, then face down;
    picked at random), creature deaths with a recoil hop, a falling roll onto a random side and a
    bounce (time based, not per frame), and corpses that sink into the ground before they go.
    **Color:** a color grade (saturation 1.22, contrast 1.06), lighter distance haze, per-zone
    rock tint and moss on rock ledges (`rock_tint`, `rock_moss`), a less murky Unholy zone.
    **Run and walk:** the sword hand holds the blade steady (the wrist takes back the forearm's
    swing; it waved around and cut through the leg). **Smoke** (bandit smoke bomb): a soft,
    swirling cloud fading at its outline and into the ground instead of a hard grey dome
    (`shaders/smoke.gdshader`).
    Tests: `--kill-at F`. Pose experiments: `ANIM_TEST=dir` (asset-pipeline.md 6.6).

94. **Creature animations.** Wolves, boars, bears, crabs, spiders, scorpions, scarabs and snakes
    are rigged and animated now instead of sliding and tipping over as static meshes
    (`tools/pipeline/creature_rig.py`, `tools/build_creatures.sh` -> `<name>_rig.glb` + `.json`
    walk/run speeds; `CreatureAnim` plays them). The script finds the limbs from the geometry:
    four legs, spine, neck, head and tail for animals; legs, claws and a tail radiating from the
    body for bugs (by direction seen from above); the raised neck for snakes. Clips: idle, walk,
    run, attack (wolves bite and shake, the bear rears up and swipes, the boar charges and tosses
    its tusks, crabs and scorpions raise and strike with their claws, the spider rears up on its
    front legs, snakes pull back and strike), hit, and two deaths that end lying down (animals
    collapse onto the belly with the forelegs forward and the head on the ground, the bear slumps
    onto its side, bugs drop flat with the legs splayed, snakes collapse onto their coil). The
    crab faces forward now (its claws pointed sideways). Floating creatures (wisps, bats, spirits)
    stay procedural. Animation updates by distance and visibility (`CreatureAnim.tick`).
    **Camp:** weapons and shield are put away while sitting at the fire (`Humanoid.stow`).
    **Grass:** smaller blades: the grass textures hold 2x2 copies (originals in
    `spike/img/v2/grass_1x/`) and the second, rotated read is finer (a finer tiling instead cost
    3.6 FPS through texture filtering).
    Tests: `--creatures CLIP [--creature-t T] [--creature-only a,b]` (rigged creatures in a row),
    `--static-creatures` (the old static models, for comparison). Medium bench: 25.8 FPS (26.8
    with static creatures and the old grass).

95. **No elites around the settlement.** Only bandits kept the elite distance (150 m); berserkers,
    nomads, corsairs, hoplites, cultists and vampires spawned from 60 m on, so a level 1 hero ran
    into elite groups right outside town. Now every elite kind stays beyond 170 m and the
    champion beyond 190 m; inside that ring are 9–19 groups of normal enemies per zone
    (`--spawn-report` prints the count and the nearest elite group).
96. **Attacking on the move, combat text, level up.**
    - Rigged creatures play their clips through an AnimationTree like the humanoids
      (`creature_anim.gd`): standing, an attack or hit plays on the whole body; moving, only on
      the bones that aren't legs or the root (chest, neck, head, tail, claws), so the legs keep
      walking instead of sliding in the attack pose. `--creatures walkattack` tests it. Bench
      unchanged (27.0 FPS vs 27.2 with static creatures).
    - Floating combat text attached to a character (damage, "Evade", ability names) rises
      relative to that character (`World.float_text(..., follow)`), so it no longer stays behind
      in the world and flies toward the camera when running forward.
    - Level up: "Level N" in large letters and below it each new ability (with its key) and
      passive; the new ability's slot on the bar pulses for 12 s. Before, the "Level N!" message
      replaced the "New ability" line at once.
    - HUD: changing the action bar no longer builds the minimap and quest tracker a second time.
97. **Linen hood fitted to the body.** The cloth hood model is a hood with a cape to the hips;
    it hung on the head bone, shrunk to head size, the cape turning with the head. Now
    `tools/pipeline/hood_layer.py` fits it to the base body as a skinned layer (like the plate
    layers, but with its own texture; `Humanoid.HEAD_LAYERS`, built by build_characters.sh):
    scaled so the hood fits the head, split into faces of at most 5 cm, pushed outside radius
    maps of the body (torso with the hanging arms, and head) plus 1.8 cm, and skinned from the
    nearest skin (head, neck, spine, shoulders; over the arms 60% upper arm, so the elbows
    don't push through when they swing). Some skin can show at the back in overhead blows.
98. **Feedback round: view range, dodge, auras, minimap, sprint, daze, north roads.**
    - Low quality draws the world to 180 m (vegetation to 100 m) and ends it in depth fog
      (from a quarter of the way, full at 165 m; the sky's horizon takes the fog color).
      `World.set_view`, applied at start and when the quality changes in the menu. Bench on
      Low: 32.7 FPS (Medium unchanged, 26.8).
    - Enemies dodge 5% of the hero's melee hits from the front (not from behind; "Dodge",
      opens Overwhelm like a miss). Spirits, mummies, tomb guardians and ice trolls don't
      dodge. Their crit chance was already 5% (bandits 20%, some 10%).
    - Buffs and debuffs under the hero's and the target's frames, with the seconds left: green
      frame for buffs, red for debuffs (Enrage, Second Wind, Battle Cry, poison, stun, slow,
      Dazed...; `Combatant.auras`).
    - Minimap centered on the hero (north up, 260 m across), continuing into neighboring
      zones.
    - Sprint works while strafing (forward or sideways, not backward).
    - Dazed: a direct hit from an enemy behind the hero, 30%: half speed for 4 s.
    - North: roads and the plaza dark grey (`road_tint` per zone type), also on the minimap.
99. **Hood without the cape; ability bar under the global cooldown.**
    - The cloth hood's cape is cut off (`hood_layer.py`, faces lower than 7 cm under the head's
      base): it clipped through arms, weapons and shields. A short collar stays.
    - Action bar: ability names are white only when usable right now (grey otherwise, also
      during the global cooldown). Under the global cooldown's sweep an ability that couldn't
      be used once it ends (Overwhelm without a dodge, too little rage) keeps its dark shade;
      Overwhelm's gold frame shows only when it is really open.
100. **Full-size face under the hood.** The head no longer shrinks under the cloth hood (it did
     to 0.7: a tiny face in a big hood). The hood layer is fitted around the full-size head, so
     no hair pokes through (checked: mage, priest, warlock; front, side, back, running). The
     closed headgear (helm, coif, cowl) still shrinks the head; the face doesn't show there.
101. **Damage that keeps up with the levels.** Oldworld2's level factor (2L/5+2) didn't scale
     the formula's flat +2, which is most of an enemy's hit, while health grows 9% per level:
     a same-level wolf hit a warrior for 1.1% of its health at level 1 and 0.8% at level 12.
     Now the whole hit grows like health (rules.gd, mechanics.md section 4): level 1 is
     unchanged, later levels keep its proportions (both ways: the hero's hits too).
     Defense was not the problem (a stat ratio with no runaway, and only a fifth of an enemy
     hit depends on it), so no cap. Test fights got `--gear RARITY` (a full set of the hero's
     level) and print the group, the lowest health and the damage per source (TAKEN).
102. **Warrior: Juggernaut and Whirlwind** (design/classes.md 2.2).
     - Juggernaut (passive, level 10): Charge without cooldown, also in combat (no +15 rage
       there, or charging back and forth would farm rage); 1 rage per second while fighting.
       Saves made before it slot it into a free passive slot on load.
     - Whirlwind (level 12, 1 min cooldown): 10 rage on use and every second after; each
       second power 40 to every enemy within 4 m. Lasts until rage runs out, a stun, or a
       second press. Moving works; auto-attack and other abilities (but Battle Cry) pause.
       Not on the bar by default (six slots full): abilities menu, N.
     - Looks: the model spins 3.4 times a second (tuned in play: 1.25, 1.9 and 2.85 felt too slow; the sword trail and the wind keep it readable)
       and finishes its turn to face forward after; the sword's trail stays on while spinning,
       drawing the arc. The upper body holds the blade-out frame of the second slash
       (CharAnimator: a one-key "whirl" clip sampled at 60% of attack2, blended over the upper
       body); the legs keep walking or running. Wind: three open cylinders with streaks
       spiralling up (whirl.gdshader), turned by the hero's own spin at about half its speed
       (the outer band and the dust at the feet slower still). Test: `--whirl [--press-at F]`,
       `--whirl-at FRAC`. Frame bursts need `godot --fixed-fps 25`: saving each picture is
       slow and the spin aliases.
     - Fix: after a Whirlwind, strafing turned the model in full circles (the unwind treated
       the strafe lean of up to 60° as an unfinished turn). The unwind now runs only right
       after a Whirlwind ends, then hands the model back. Test: `--strafe-at F`.
     - Wind made a bit chaotic: four bands (six were too busy) of random radius, height and
       spiral pitch, each tipping up to 17° (the dust 8°) one way or another, a new way now
       and then; stacked like a tornado (the higher, the wider, each band flaring out toward
       its top), built twice with its own random draw: an inner funnel (about 0.4 m at the
       feet to 1.2 m above the head) and a fainter outer one (about 0.8 m to 1.7 m), the dust
       ring only once, the outer one without the middle band; each
       drifts between 70% and 135% of its pace (new goal every 0.3–0.7 s) and its radius
       wobbles unevenly around the circle and over time (vertex shader). Moving while
       whirling is at half speed.
103. **Hit sounds by weapon.** Every blow that lands now plays its weapon's impact
     (tools/audio/makeaudio.py, three takes each, `Audio.hit(kind, crit)`): sword (thump,
     bright slice, short ring), axe (chop, splinters), mace (deep crunch, bone cracks, dull
     clank), club (wooden thud), staff (lighter knock), dagger (short tick), claws (three
     rips), bite (crunch), arrow (thunk). Crits add the crit ring. The hero's sound follows the
     main-hand weapon (the class weapon without one; claws in Bear Form); enemies use their
     weapon, beasts claws (bear, scorpion, crab) or a bite. Covers auto-attacks, melee
     abilities, Whirlwind (each enemy hit, plus a whoosh), Thunder Clap, Knife Throw, arrows
     on impact and enemy blows on the hero. Strong blows (power 40+) keep the "slash" swish
     over the impact. The bow's release played the hit sound; it's the twang now ("launch",
     which was never copied into the game).
104. **Bow grip; kiting without evades.**
     - The hunter's bow lay along the forearm. Two holds now (humanoid.gd, `set_bow_aim`):
       at rest slanting, the lower limb forward and down past the knee and the upper one back
       and out past the hip; in combat and while shooting across the fist like a sword's grip,
       upright with the string toward the archer when the arm is raised; eased between them in
       0.2 s. (Any hold across the fist runs along the thigh with the arm hanging and went
       through the leg; a 20° tip just moved which end did.)
     - Leash: past 40 m from home an enemy evades only after 6 s without taking damage
       (`LEASH_GRACE`); as long as the hero keeps hurting it, it keeps following, so a hunter
       can kite. (mechanics.md's "or 10 s without damage" rule was never built and is gone.)
105. **Hunter: Concussive Shots (passive, level 2)** replaces the Concussive Shot ability: every
     arrow that hits (Auto Shot, Steady Shot, Venom Arrow, Volley) slows its target by 60% for
     4 s ("Concussed", refreshed by the next arrow). Volley and First Aid moved up to keys 4
     and 5. Saves: the old ability drops off the bar, the passive takes a free slot on load.
106. **Real arrows.** The hunter's shots were glowing balls (the spell bolt). Now
     `Projectile.arrow()`: a wooden shaft, a steel head and three red feathers, flying at
     38 m/s in a shallow arc nose-first, sticking in the target for 2 s (gone earlier if it
     dies). New sounds: the bow loosing (`bow_shot1..3`: a low string twang and slap, the arrow
     hissing off) and a sharper impact (`hit_arrow`: the head's click, a short punch, the shaft
     quivering). Test: `--fight KIND --hold M` (the group stands stunned, the hero M m away).
107. **README with a screenshot gallery** (like Oldworld2's): 15 pictures, every class and every
     land, 12 of them in fights, plus a camp at dusk, two settlements and the world map.
     `tools/screenshots.sh [NAME...]` retakes them (High quality, native resolution, rare gear,
     the HUD without the controls list: new `--nohelp`). `--whirl` now ignores the global
     cooldown (the bot's last ability blocked it).
108. **Pathfinding, casting, spells, robes, staves.**
     - Enemies go around obstacles (enemy.gd `_steer`): rays ahead at knee height (middle and
       both shoulders; walkable slopes don't count); when blocked, the clear direction closest
       to the goal, on one side kept for 2 s (no dithering at a wall); no headway for half a
       second: a sidestep along the wall. Test `--chase-from X,Z`: an enemy behind the inn
       reached the hero in 5–6 s (never without steering, `--no-steer`). Costs < 1 FPS.
     - Casting: a channelling loop for the whole cast (staff raised, the free hand circling at
       chest height, feet apart; skeleton.py `cast_loop`, blended in by CharAnimator.set_cast)
       and a release with a lunge, both hands thrust at the target. While casting: light
       gathering in the left hand and a rune circle at the feet in the spell's colour.
     - Spells have models (combat/spell_fx.gd, all built in code): a fireball with a flame
       ribbon and smoke, an ice shard, a water orb, a green thorn, a crackling storm bolt, a
       golden holy orb, a shadow bolt trailing smoke; impacts with a burst and a flash of light;
       Moonbeam a column of light. Enemy casters use them too. Trails are continuous ribbons
       (particles alone clumped per frame at these speeds).
     - Hellfire Rain: while casting, a burning rune circle marks its 8 m area on the target;
       then 16 meteors fall at a slant into it, each bursting in flames, sparks and smoke with a
       heat ring over the ground and a scorch mark; enemies in the circle burn when the first
       ones land.
     - Casters (mage, priest, warlock, druid) wear robes: a skirt layer built from the body
       (tools/pipeline/robe_layer.py, from the waist to above the ankles, widening to the hem,
       skinned to hips and thighs so it swings with the stride), coloured per class with a belt
       and an embroidered hem (shaders/robe.gdshader, Player.ROBES).
     - Staves are 25% shorter (they stood far over the head).
     - Tests: `--nobot` (target the group but only act on `--press`).
109. **Jumping with a staff, the global cooldown, hidden abilities, graveyards.**
     - Staff wielders keep their arms still in a jump (CharAnimator `keep_arms_in_air`: the idle
       pose on the arms over the jump clip); the jump's arm swing had tipped the staff over
       backward. Everyone else jumps as before.
     - No global cooldown after a spell with a cast time goes off, only after instants (the
       cast starts one, which has run out by the time the spell goes off).
     - Abilities and passives not learned yet are hidden: not in the abilities menu, and their
       action bar slots stay empty (`slot_ability` returns nothing for them) until the level;
       then the bar refreshes and the new one pulses in its slot.
     - Unholy lands: gravestones no longer stand scattered through the forest; each zone has
       three graveyards instead (world/graveyard.gd): a clearing 60–200 m from the settlement,
       a wrought-iron fence (one mesh, bars with spear tips, a collider per section) with its
       gate toward the settlement, a crypt at the back with a faint green light, rows of
       gravestones on both sides of the path (some missing, leaning or turned), dead trees in
       the back corners; a cross on the minimap.
110. **Starting items that explain the look.** Every class starts with what it is seen wearing,
     as plain common items with 1 point of their stat (Items.STARTER): the warrior a Worn
     Greatsword, Dented Helm, Squire's Breastplate and Legplates; the casters their staff or
     mace and a robe (Apprentice's, Initiate's, Acolyte's, Grove Robe); the rogue two daggers;
     the hunter a Hunting Bow; paladin and shaman a mace and a shield. The look now follows only
     what is worn (Player._show_weapons): no main hand, empty hands; a bow or a parrying dagger
     from the item; headgear by armor type; plate legs and pauldrons with plate pieces; a robe
     with a cloth chest (class colours, a plain brown one for others). Before, an empty slot
     showed the class's own kit, so a new hero held a sword with nothing equipped. Saves from
     before get the kit in their empty slots once (`kit` in the save).
111. **Real robes; stripping down to the plain clothes.**
     - The robe (after Oldworld2's) is a whole garment now, not a skirt: a standing collar, a
       bodice hugging the torso, the skirt falling in folds to the ankles, bell sleeves widening
       down the forearm (robe_layer.py, all measured from the body; the bodice and sleeves
       skinned from the nearest body skin, the skirt from the hips to the thighs and, toward the
       hem, the shins). robe.gdshader: an embroidered front panel collar to hem, the collar, a
       leather belt with gold studs and a round buckle, the hem and the cuffs embroidered, fold
       valleys shaded. Under it the body's chest, arms and legs aren't drawn, nor a foot kicked
       up behind in a stride (body_slots `robed`), so nothing pokes through.
     - Armor is the outfit: each body part (chest, hands, legs, feet) shows the class outfit
       only while an item is worn there, else the plain shirt, cloth trousers and shoes under it
       (Humanoid.set_pick); a warrior without his plate stands in shirt and trousers. The
       starting kits cover all of it now (gloves, boots, trousers, jerkins; the paladin a mail
       tabard, so no pauldrons); saves with the first kit get the new pieces (kit version 2).
       Test: `--strip` (all armor off).
112. **Faces, a more natural robe, the warlock in red.**
     - Every class has the base body's face now: the outfits' baked heads came out smeared (the
       druid's face off its place, the mage's skin too dark, the warlock's pink).
     - The robe sits closer (1 cm over the torso, 2 cm over the legs, half the flare, small bell
       sleeves, shallower folds) and looks like cloth: muted wool colours, a fine weave and soft
       drape wrinkles as relief (a procedural normal map), a narrow front panel, thin collar, hem
       and cuffs in an accent colour with quiet embroidery, a plain leather belt with a small
       buckle. Robes take [cloth, embroidery, accent]; the warlock's is deep red with black.
     - Cloth handwraps and slippers show bare hands and the plain shoes (the casters' outfits
       had coloured gloves and shoes that clashed with their robes).
113. **Staff grip, quieter casting, Blizzard.**
     - The robe's fine weave and noise are gone (they shimmered at a distance); only broad drape
       wrinkles stay.
     - Staves are held about the middle, upright and a little off the body (Humanoid
       STAFF_GRIP / STAFF_TILT; they were held at the lower end, leaning in through the robe).
       Test: `--staff-grip x,y,z,rx,ry,rz`.
     - The rune circle at the feet only shows for channels and casts of 2.5 s or more; ordinary
       spells keep the light in the hand.
     - Mage: Blizzard (level 8), the first channelled spell: 6 s on an 8 m circle at the target
       (fixed when it starts), every second Ice damage (power 22) and a 50% slow ("Chilled") to
       each enemy in it; paid when it starts, broken by moving or a stun. SpellFx.Blizzard: an
       icy rune on the ground, driving snow, ice shards crashing down and bursting, low frost
       mist, a cold light. Test: `--slot6 blizzard --press 6`.
114. **Robes from every side, the staff held upright, a camping tip, easing into rest.**
     - Under a robe the legs and feet are drawn below the hem again (only above 24 cm they're
       hidden): from the side the ankles and shoes showed nothing between hem and ground.
     - Staves stay upright in the hand whatever the arm does (Humanoid._staff_update, after the
       animation every frame): turned about the fist, the shaft a little beside it, the foot
       leaning slightly out, so it stands clear of the robe; with the hand raised in a cast it
       is held up, no longer upside down; in a melee swing it swings with the hand.
     - A new hero gets a tip after the first fight: "press C to camp and recover your health
       (and mana)" (shown 8 s, once; saves remember tips, older saves count as seen).
     - Camping eases in: nothing for the first second while the fire catches, then half the rate,
       rising to the full rate over 4 s.
     - Fix: an empty action bar key (or one not learned yet) asked about made errors
       (ability_problem on an empty ability).

115. **Real trees, a real moon, distance fog, options, combat feel.**
     - Trees: the grassland's beech, linden and birch, the Mediterranean's olive and cypress and
       the bushes are built procedurally (`tools/pipeline/tree.py`, `tools/build_trees.sh`):
       trunk, limbs and branches as tubes, leaves as sprig cards rooted on the branches (the
       generated models were clouds of leaf flakes with nothing holding them). Normals bent out
       of the crown, darker sprigs inside it. Old models: v0.2.0. ~6% fewer FPS.
     - Trees with a wide base sink to the lowest ground under them on slopes, or a narrow tree
       of the zone grows there instead (scatter.gd `BASE`, `MAX_DROP`).
     - The moon: a generated near side (`tools/textures/moon.py`: the maria at their real
       places, faint craters, Tycho's rays) on a quad in the sky with a halo
       (`shaders/moon.gdshader`); the sky's blurry disc is off at night.
     - Dense distance fog in all zones but the deserts (full at 210 m; the Unholy lands at
       170 m), the sky's horizon band in the fog's color so the rim mountains fade into it.
     - Options (title screen and Esc menu): quality, day and night, sound effects and music
       volume (buses "SFX" and "Music", saved in settings.cfg).
     - Blows land at the swing's moment of impact (CharAnimator.IMPACT), for the hero and the
       enemies: damage, hit sound and riders (stuns, poison) then, if the target is still in
       reach. Combat ends as soon as no enemy is after the hero (Charge works again at once);
       crossed swords at the top while in combat; a "You died" banner shows the penalty.
     - Nameplates like WoW's: a health bar with a black border over the name, no level, no %;
       about the same size on screen at any distance. Combat text twice as large. No sound on
       a kill.
     - Mage: Fireball (level 10, 25 mana, cast 2 s, power 60, ignites the target).
     - Cloth hood: snug around the head, ending just under the jaw (no gap over a robe).
     - Running: the weapon hand swings with the arm (75% of the forearm's swing) instead of
       holding the blade at one angle.
     - Chests mostly in elite camps (up to three). Wolves and other creatures are matte (the
       generated metal maps made fur shine in the moonlight).
     - Items: a weapon's own stat takes the whole budget and the suffix comes on top (an
       iron dagger of the Owl had less Magic and Mana than a plain one two levels lower).
     - Trees and bushes within 2–5.5 m of the camera dither out (scatter.gd `NEAR_FADE`): a
       camera pushed into a crown (dense Unholy forest) no longer sees a black wall of branches.
     - Exit: no more leaked music playback (streams released on exit), tooltips closed before
       quitting.

116. **Headgear around the real head; nameplates with the name on the bar.**
     - Hood, coif, leather cap and plate helm are no generated models on the head bone any more
       (the head was shrunk to fit them and showed small inside the open ones): each is a shell
       built around the full-size head (`tools/pipeline/headgear.py`, in build_characters.sh):
       an egg around the head (round like WoW's), the face opening cut as a smooth oval (the
       helm: an eye slit), ending at the neck, never on the shoulders. The hood closes under
       the chin and takes the robe's colours. One shader for cloth, mail rings, stitched
       leather, steel with brass (`shaders/headgear.gdshader`). The head shrink is gone.
     - Under headgear the body shader draws only the face and the neck (`hide_hair`): hair
       would poke through the shells (WoW hides it too).
     - Test: `--heads [--heads-turn 180]` shows the four in a row.
     - The hood snug (1.2 cm off, inside the hair's outline where the head isn't drawn anyway),
       mirrored left to right, with a soft point at the back; the forehead covered down to the
       brows; below the chin a smooth tube around the neck (`tube`). The head's middle for
       hide_hair is 9 cm ahead of the head bone (the ears showed through the hood).
     - All four snug the same way (`snug`, `shown`, `tube` per kind), the sides narrowest (the
       ears and the side hair aren't drawn under headgear); the leather cap hides the ears too.
     - Centered on the face's line (nose and chin tips), 3.2 cm beside the head bone: centered on
       the bone, every shell bulged on one side and sat tight on the other (`CX`, HEAD_SIDE).
     - Head-shaped instead of a ball: narrower than deep, taller, the skull reaching back, the
       sides narrowing from the temples to the jaw (`egg(kx, kb, ku, jaw)`).
     - Nameplates: the name in white on the health bar, the bar as wide as the name needs,
       drawn over everything, about 50% larger.

117. **Weapon damage and two-handed weapons; stocky goblins; Whirlwind and Rend.**
     - Every weapon has Damage; it multiplies the hero's physical hits (Rules.weapon_mult,
       design/mechanics.md 4); weapons lost their Attack. Two-handed greatsword, greataxe and
       maul: 30% more, no off hand. The warrior's starting greatsword is one now. The bags show
       the weapon damage and its factor.
     - Goblins stubby: short legs and a big head (`Proportions`, a skeleton modifier scaling
       the thighs and the head after the animation, the body lowered to keep the feet down),
       wide (`build`), and in rags (body_slots `tatter`: faded, stained cloth, frayed rips in
       shirt and trousers showing the green skin). The head egg-shaped, wide on top (body_slots
       `head_egg`, the build taken back out of the head), long pointed ears (Humanoid._add_ears,
       generated leaf meshes on the head bone). Test: `--heads-goblin`.
     - Combat text 10% smaller, nameplate names 10% larger; crits stick like WoW's (pop in big,
       stay put 0.7 s, then rise), also for crits taken.
     - Under a robe the legs are drawn whole (`robe_legs`; it was 0.24 m): any height cut left
       holes in the back leg when running, seen from behind. In a long stride the back shin shows
       behind the hem.
     - Goblin face: the base body's face in the skin's green (`head_tint`; the generated
       outfit's baked face was a smear), thin stringy black hair from a hairline above the brows
       (strands running down from the crown, in the head's own angles), a goblin skull: a low
       forehead sloping back from the brow, the crown narrowing, the back swept back (above the
       brows, and for the base hair's bangs and side locks found by their dark texels, the head
       is held inside an ellipse, its front and back axes blended across the middle; the upper
       front lowered the further ahead, so the forehead slants back into the crown; the hair's
       volume read as a cap on the forehead; the hair pull only on the front half and never on
       the face's surface: the dark eye corners and brows were pulled in too, which hollowed the
       eyes out in profile; the skull's front edge starts at the face's depth and follows a
       quarter ellipse from the brow round into the crown, no steep slope with a corner), its
       own face drawn in head space on even skin (the base face's painted shading made it
       darker): yellow almond eyes with slit pupils, a wide down-turned mouth with two fangs, a wide jaw, a beak nose (a long narrow bridge, the tip hooked down), goblin features shaped in the head shader (a long hooked
       nose, a heavy brow, a jutting chin), rougher mottled skin; fur hides instead of the
       outfit's cloth (body_slots `fur`: patches and fine strands, the folds kept), bare green
       hands, fewer rips.
     - Goblin ears smaller (0.24), a little darker than the face (thin, in full light, they
       looked brighter). Test: `--heads-goblin --heads-goblin-lift 0.75` (faces at eye level).
     - Goblin ears point up (40 degrees), the build taken back out of them too (stretched with
       the body, their base stood off the head).
     - Whirlwind: every kill by it takes 5 s off its cooldown. Rend from level 2.
     - No level penalty on weapons: the hero's physical hits don't grow with the hero's level,
       the weapon brings the growth (1.2 × Damage / 8); a same-level weapon hits as before,
       levelling never lowers damage, a new weapon raises it. Spells still grow with level.
     - Two-handed animations: a two-handed hold over the arms (`hold2h` in skeleton.py: both
       hands in front, the blade up and forward), the left hand kept on the grip below the right
       one by a two-bone IK after the animation (`two_hand_grip.gd`); swings follow with both
       hands. (Godot's TwoBoneIK3D left the hand 12 cm off and the arm up.) Out of combat a
       two-hander is carried like a one-hander; the two-handed hold eases in when fighting
       (Humanoid.set_two_hand_stance). Two-handed models 20% larger.
     - Attackers no longer rise into the air: pressing against a crate or the tent in a fight,
       their capsule slid up its edge; enemies are kept on the ground.
     - Buildings and props matte (generated metal maps) with a weathering pass
       (`shaders/grime.gdshader`: dirt splashed up, rain streaks, mottled plaster; strong in the
       Mediterranean, `grime`). The well is built in code now (`world/well.gd`; the generated model's
       ring had no inside that could meet a shaft): a fieldstone wall with capstones, gritty
       masonry with moss and grime low down (`well_stone.gdshaderinc`, bump lighting from its
       relief), its inner wall going on 3.5 m down to a black bottom as a portal through the
       terrain (an invisible disc at the opening marks it in the stencil buffer, the shaft is
       drawn there without depth test), weathered wooden posts, roof, crank, rope and bucket.
     - No distance fog in the Mediterranean (clear air, like the deserts).
     - Strafing like WoW: the legs run toward where the hero moves (up to 75 degrees), the upper
       body twisted back so chest and head keep facing ahead (`TorsoTwist`, a skeleton
       modifier); no back shown to an enemy while running sideways.
     - Charge follows the ground's height directly (at 22 m/s a bump lifted the hero off a slope
       and the slope stopped him like a wall). Enemies are only put back on the ground when
       20 cm or more above it (on a crate). Test: `--hill-chase [--hill-charge]`.
     - Running: the weapon hand turns fully with the arm, the wrist nearly straight (35°; it was
       bent 95° down like standing still, the blade kept pointing at the ground).

118. **Zones twice as large, built in the background; autorun, a war horn, camera, wells.**
     - Zones 1024 m across (were 512); the rim, foothills, forest band, lakes (5-9), spawn and
       chest ranges, graveyards (5 in the Unholy lands) and border crossings follow the size;
       three times the enemy groups per kind.
     - A zone is built entirely on a worker thread (data and nodes) and attached a few nodes per
       frame (4 ms; before, its nodes cost up to 1.3 s in single frames). Neighbors start 300 m
       before their border. Enemies get their model only within 170 m of the hero, a few per
       frame (all of a zone's took 8 s; far away they cost frames for nothing). If the hero
       reaches a zone still being built, he waits; the main thread never waits for the worker
       (that hung the game). `--zone-timing` prints the steps.
     - Quests are dropped when leaving their zone. Black Bear is the Brown Bear.
     - F2: autorun (until a key other than strafing or turning). The world map scrolls with the
       arrow keys. Battle Cry blows a war horn over war drums. The camera keeps 0.4 m from the
       ground and walls (a sphere, not a ray). Borderless fullscreen by default.
     - The "jumping" swing: skeleton.py measured the feet for a clip's first key in whatever
       pose the scene showed (attack1, made after sitting, floated 40 cm up its first frames);
       it goes to the clip's frame first now.
     - The well's wood is brown.

119. **Fur on wolves, bears and boars; corpses stay while seen; no falling out of the world.**
     - The generated creature textures have a painted sheen (it stayed glossy fully rough).
       shaders/fur.gdshader (Enemy._matte, HAIRY kinds): the painted color pulled toward its
       blurred average (the highlights go), fine wavering strands and tufts in object space
       flowing back and down, almost no specular.
     - Corpses: after CORPSE s they vanish only when out of the camera's view (or 150 m off);
       respawns at home only when home is out of view.
     - A hero more than 2 m under the ground is put back on top (saves from before the zone
       size change); loading a save never places the hero under the ground. Test: --sink-at N.
     - Rend: 5% of max HP every 3 s for 30 s (was 1/32 for 15 s).
     - Enemy groups per kind x4 per zone (GROUPS_PER 4): the density of the smaller zones.
     - Music at 50% by default. The volume bars in the options are real bars: a click (or a
       drag) sets the volume to where the mouse is; "<" and ">" step by 10%. Test:
       --menu options --menu-click N (a click at 30% of the music bar).


## Known issues / next

- Only head items, weapons and shields are visible; body armor keeps the class outfit (visible
  armor needs outfits per item type).
- Elite groups (2–3 elites one level above you) kill rogues, priests, mages and hunters of the
  same level in automated fights; tune if that feels too hard in play.
- Two-handed weapons are the one-handed models, larger.
- After crossing zones, 78 plain RefCounted objects are reported leaked at exit (harmless,
  probably a reference cycle in a script object).
- Some generated buildings look rough up close (the Mediterranean villa), the obelisk has no
  pointed tip, the tomb guardian's kilt came out as trousers.
- Sunrise and sunset light is dim on the side facing away from the sun.
- Not built yet: dungeons, trainers, story quests, mounts.

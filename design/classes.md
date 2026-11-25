# Classes and Abilities

> Part of the [Oldworld3 design docs](game-design.md). Based on Oldworld2's `classes.md`.
> v1 has only the Warrior; the other eight classes follow later with the same approach.

## 1. Classes

The nine classes of Oldworld2 stay: Warrior, Rogue, Hunter, Mage, Warlock, Priest, Paladin,
Shaman, Druid. Their identities, affinities and armor types are unchanged (see Oldworld2's
`classes.md` and `items.md`). Each gets a real-time version of its abilities when it is added.

- Heroes are Physical-typed; class elements are affinities (1.5× on matching abilities).
- A class sets its resource (rage, energy or mana), armor type, weapons and ability pool.

## 2. Warrior

High health, Attack and Defense, Physical affinity, plate armor, swords, axes, maces, spears
and shields. Resource: **rage**. Double out-of-combat health regeneration.

### 2.1 Base Stats (level 1)

| HP | Attack | Magic | Defense | Resistance |
|---:|-------:|------:|--------:|-----------:|
| 480 | 14 | 4 | 13 | 8 |

From Oldworld2 (HP × 4, see [mechanics.md](mechanics.md#3-stats)); growth per level as there.

### 2.2 Abilities (levels 1–12)

| Level | Ability | Oldworld2 | Real time | Cost | Cooldown |
|---:|---|---|---|---|---|
| 1 | **Auto-attack** | Punch (fallback) | Swing timer from the weapon (2H 2.6 s, 1H 1.8 s); hits give rage | — | — |
| 1 | **Heavy Strike** | Power 50, 15 rage | Instant strong hit, power 50 | 15 rage | GCD |
| 1 | **Battle Cry** | Attack +1 stage | Attack +25% for 2 min; usable out of combat. Costs nothing and gives 10 rage, so a fight can start with a Heavy Strike sooner | 0, gives 10 rage | 2 min |
| 2 | **Overwhelm** | After a dodge or miss | Usable for 5 s after the target dodges or a Smoke miss; power 100, can't be dodged | 5 rage | GCD |
| 3 | **Enrage** (passive) | On crits taken | Taking a crit (or 30% on any hit) gives +25% damage for 12 s | — | — |
| 4 | **Thunder Clap** (new) | — | Area: power 25 to all enemies within 8 m, slows their attacks by 20% for 10 s. Answer to packs | 20 rage | 6 s |
| 6 | **Charge** | First round, stun, +15 rage | Rush to the target from 8–25 m, stun 1.5 s, +15 rage; out of combat only | 0, gives 15 rage | 15 s |
| 8 | **Second Wind** (passive) | Regen on hit | 30% chance when hit (always on a crit taken): heals 1/32 of max HP every 3 s for 9 s; refreshes, doesn't stack | — | — |
| 10 | **Rend** | Bleed 10 rounds | Bleed: 1/32 of max HP every 3 s for 15 s | 10 rage | GCD |
| 10 | **Juggernaut** (passive, new) | — | Charge has no cooldown and works in combat (no rage from it there); 1 rage per second while fighting | — | — |
| 12 | **Whirlwind** (new) | — | Spin with the blade out: power 40 to every enemy within 4 m once a second, 10 rage a second until rage runs out or pressed again; moving allowed, no other abilities (but Battle Cry) and no auto-attack meanwhile. Not on the bar by default (abilities menu, N) | 10 rage per second | 1 min |

- **Thunder Clap** is new: real-time combat brings packs, and a pure single-target kit made
  packs too punishing in testing on paper. Its level-4 slot was empty in Oldworld2.
- Later (trainers, from Oldworld2's pool): Shield Slam, Armor Break, Finishing Blow (Execute),
  Berserk; tome: Unbroken. Hamstring (slow) is an IDEA for chasing fleeing enemies.

### 2.3 Rotation Sketch (for balance checks)

Open with Charge (15 rage, stun) → Heavy Strike → auto-attacks build rage → Heavy Strike
whenever there are 15 rage → Rend on long fights → Overwhelm when it lights up → Thunder Clap
against two or more enemies. Battle Cry before pulling.

### 2.4 Action Bar

- Abilities sit on a bar of 9 slots (keys 1–9); new abilities go into the first free slot.
- Passives are listed in the spell book (key P) but take no slot. The spell book and the action
  bar tooltips are generated from this document (`tools/docs/ability_text.py`).

## 3. Mage (implemented 2026-11-13)

Oldworld2's Mage in real time: highest Magic, low health, Ice/Water/Fire affinities, cloth.
Resource: **mana** (300, doesn't grow with level; regenerates 2% per second starting 5 s after
the last spell that cost mana). Spells with a cast time show a cast bar; moving or jumping
interrupts them. Magic damage uses Magic vs. Resistance and the element chart.

| HP | Attack | Magic | Defense | Resistance |
|---:|-------:|------:|--------:|-----------:|
| 340 | 4 | 16 | 7 | 12 |

| Level | Spell | Real time | Mana | Cooldown |
|---:|---|---|---:|---|
| 1 | Fire Bolt | Cast 1.6 s, power 40, Fire projectile (filler) | 0 | GCD |
| 1 | Ice Bolt | Cast 2.0 s, power 55, Ice; slows the target 40% for 6 s | 24 | GCD |
| 2 | Frost Ring | Instant, all enemies within 8 m: power 45 Ice, rooted 5 s | 30 | 20 s |
| 3 | Mana Shield | 20 s: half of the damage taken is paid with mana | 30 | 30 s |
| 4 | Ignite | Instant, Fire burn: 1/32 max HP every 3 s for 24 s | 24 | GCD |
| 6 | Blink | Teleport 15 m forward, breaks roots and slows | 15 | 15 s |
| 8 | Blizzard (new) | Channelled 6 s: snow and ice on an 8 m circle at the target, Ice damage (power 22) every second to each enemy in it and a 50% slow for 2 s; moving or a stun breaks it. Not on the bar by default (abilities menu, N) | 45 | — |

Later (Oldworld2's pool): Arcane Explosion, Frostfire Bolt, Ice Block, Time Warp, Meteor.
The look: a blue embroidered tunic (ControlNet outfit on the base body) and a staff with a
glowing crystal. Long robes would need their own geometry (see asset-pipeline.md).

## 4. Rogue (implemented 2026-11-13)

Oldworld2's Rogue in real time: high crit chance (12%), daggers in both hands (swing 1.8 s),
leather, Physical/Dark affinities. Resource: **energy** (0–100, +5 per second).

| HP | Attack | Defense | Resistance |
|---:|-------:|--------:|-----------:|
| 380 | 14 | 9 | 8 |

| Level | Ability | Real time | Energy | Cooldown |
|---:|---|---|---:|---|
| 1 | Quick Stab | Power 45, +25% crit chance | 40 | GCD |
| 1 | Stealth | Out of combat: aggro radii ×0.3, 70% speed; the first hit out of stealth deals +50%; any action or damage breaks it | 0 | 6 s |
| 2 | Knife Throw | Ranged 25 m, power 45 | 20 | GCD |
| 3 | Poisoned Blade | Power 20 + Poison (1/32 max HP every 3 s, 15 s) | 30 | GCD |
| 6 | Cheap Shot | Power 10, stuns 3 s | 40 | 20 s |
| 8 | Gut Slash | Power 75 | 30 | GCD |

Passives: **Improved Sprint** (6): Sprint stamina lasts five times as long. **Cheat Death** (8):
Once every 2 minutes, a lethal hit leaves 10% health instead.

## 5. Priest, Paladin, Warlock, Hunter, Shaman, Druid (implemented 2026-11-13)

All nine classes of Oldworld2 are playable (choose on the title screen). Health is Oldworld2's
× 4; all but the Warrior and Rogue use mana (300). Abilities are in `game/scripts/player/player.gd`
(`ABILITIES_<CLASS>`); the numbers are first guesses for playtesting.

| Class | Weapon | Abilities (level) |
|---|---|---|
| Priest | mace | Smite (Holy bolt, free filler), Mend (cast heal 25%), Holy Burst (2, Holy area), Ward of Light (3, absorbs 25% max HP), Renewal (4, heal over time), Mind Pain (6, Dark damage over time) |
| Paladin | mace, shield | Righteous Strike (Holy melee), Holy Seal (every hit adds a Holy hit, 30 s), Judgment Hammer (2, stun 2.5 s), Devotion (4, Defense +25%), Healing Light (6, cast heal 30%), Divine Shield (8, immune 6 s) |
| Warlock | staff | Hex Bolt (Dark bolt, free filler), Drain Life (drain over time, heals you), Wither (Dark damage over time), Hellfire Rain (2, Fire area at the target), Curse of Weakness (3, target Attack −25%), Dread (6, target attacks half as often); passive Demon Armor (4, regeneration in combat) |
| Hunter | bow | Auto Shot (arrows from 5–30 m on the swing timer), Steady Shot (instant arrow, power 50, 30 m), Venom Arrow (poison), Mark Prey (2, target Defense −25%), Concussive Shots (passive, 2: every arrow slows its target by 60% for 4 s), Volley (6, Nature area), First Aid (8, cast heal 30%) |
| Shaman | mace, shield | Storm Bolt (Air bolt, free filler), Flame Shock (Fire + burn), Chain Lightning (2, up to 3 targets), Healing Wave (3, cast heal 25%), Stone Shock (4, silences: no special abilities 4 s), Frost Shock (6, slow); passive totems (4): entering combat places a Wrath Totem (Magic +25% nearby) and a Healing Stream Totem for 30 s |
| Druid | staff | Thorn Lash (Nature bolt, free filler), Rejuvenate (heal over time), Insect Swarm (2, damage over time + Attack −25%), Grasping Roots (3, root 6 s), Moonbeam (4, Holy cast), Bear Form (6): the druid becomes a bear (melee with Magic as Attack, Defense ×2, heals 25% on shifting; spells unavailable until shifting back) |

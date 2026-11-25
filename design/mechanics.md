# Game Mechanics

> Part of the [Oldworld3 design docs](game-design.md). Starting values, to be tuned by
> playtesting. Based on Oldworld2's `mechanics.md`, converted from turns to real time.

## 1. Combat Overview

- Combat happens in the world, in real time. There is no battle screen.
- **Several enemies can fight the hero at once.** Pulling a whole pack is the main risk, as in
  WoW Classic. Enemies in a group help each other (see [Aggro](#7-aggro-and-leash)).
- The hero has a **target**. Abilities and auto-attack act on the target unless they say
  otherwise (self, area around the hero).
- **Facing and range:** melee needs the target within 2.5 m (plus the target's radius) and in
  front of the hero (within ±60°). Ranged and spells need line of sight.
- The hero is **in combat** while any enemy is fighting them and for 5 s after the last hit.
  Some things only work out of combat (resting, eating, Charge).

## 2. Turns Become Seconds

| Oldworld2 (turn-based) | Oldworld3 (real time) |
|---|---|
| One action per turn | **Global cooldown (GCD)** of 1.5 s after most abilities |
| Fallback attack (Punch, Fire Bolt…) | **Auto-attack** on a swing timer (melee) or a free filler spell (casters, later) |
| Priority +1/+2 | Gone. Instant abilities simply happen at once |
| "N rounds" | N × 3 s (1 round ≈ 3 s) |
| Once per battle | Cooldown (usually 30 s – 2 min) |
| First round only | Only while the target is not in combat yet |
| Stat stage ±1 | Timed buff/debuff ±25% (stacks to ±3 stages, no further) |
| Wait | Gone |
| Grace period between battles | Gone |

## 3. Stats

| Stat | Effect |
|------|--------|
| Health (HP) | 0 = dead |
| Resource | Rage (Warrior), Energy (Rogue), Mana (casters). See [Resources](#5-resources) |
| Attack | Physical damage |
| Magic | Spell damage and healing |
| Defense | Reduces physical damage |
| Resistance | Reduces magical damage |
| Crit chance | 5% base; a crit deals 1.5× (abilities) or 2× (auto-attacks) |

- Oldworld2's **Speed** stat is dropped: turn order doesn't exist anymore. Attack speed comes
  from the weapon, movement speed is the same for everyone (enemies have their own).
- **Health scale:** real-time fights last longer than two or three turns, so all health values
  (hero and enemies) are **4× Oldworld2's**. A level-1 Warrior has 480 HP.
- Growth per level (from Oldworld2): HP × (1 + 0.09 × (Level − 1)), other stats
  × (1 + 0.1 × (Level − 1)).

## 4. Damage

Oldworld2's formula at level 1, per hit, growing with the attacker's level like health:

```
Base   = ((2.4 × Power × Atk / Def) / 50 + 2) × (1 + 0.09 × (Level − 1))
Damage = max(1, floor(3 × Base × Affinity × Element × Crit × Random × Other))
```

- The level growth matches HP's, so a hit takes the same share of a same-level target's
  health at every level (Oldworld2's factor 2 × Level / 5 + 2 didn't scale the flat + 2, and
  enemies hit a level-12 hero a third less, relative to its health, than a level-1 one).
- Atk/Def: Attack vs. Defense for physical hits, Magic vs. Resistance for magical ones.
- Affinity 1.5 if the ability's element is one of the attacker's affinities.
- **Weapon (the hero's physical hits):** Other includes 1.2 × (weapon Damage / that of a
  common one-hander of the hero's level)^0.75, two-handed weapons rated against two-handers
  and then ×1.3. A same-level common one-hander gives 1.2 (what its Attack used to add), a
  two-hander 1.56, a rare one-hander about 1.6; an item-level-1 weapon at level 10 0.74; fists
  0.71. Enemies: 1. Spells don't use it.
- Element: the chart from Oldworld2 (8 elements; heroes are always Physical-typed and take
  neutral damage). Random 0.85–1.0. Other: buffs, debuffs, Enrage, gear.
- **No random misses**, as in Oldworld2: hits always land unless a visible mechanic says
  otherwise (Flying dodges 50% of melee; Smoke; evade abilities).
- **Auto-attack power** = weapon speed × 12 (a 2.6 s two-hander hits with power 31, a 1.8 s
  one-hander with 22), so damage per second doesn't depend on the weapon's speed.
- **Target fight length:** a same-level trash enemy takes a Warrior about 15 s; an elite about
  30 s. A same-level pack of three trash enemies is dangerous but winnable with full health.

## 5. Resources

| Resource | Classes | Rules |
|----------|---------|-------|
| **Rage** 0–100 | Warrior | Starts at 0. Dealing damage gives rage (auto-attack hit: 8, crit: 16); taking damage gives 1 per 2% of max HP lost. Decays by 2/s out of combat |
| Energy 0–100 | Rogue (later) | Refills 10 per 2 s |
| Mana | Casters (later) | Abilities cost ~5–10% of max mana; regenerates 2%/s after 5 s without casting |

## 6. Status Effects

From Oldworld2, with rounds replaced by ticks every 3 s. Damage and healing over time stay
**fractions of the target's max HP**, so they matter at every level.

| Effect | Real-time version |
|--------|-------------------|
| Bleed, Poison, Burn, other DoTs | 1/32 of max HP per 3 s tick (half the old per-round value, since fights have more ticks) |
| Drain (Warlock) | 1/16 per tick, heals the caster as much |
| Regen | Heals 1/32 of max HP per tick |
| Stun | Can't act or move |
| Freeze | Like Stun, broken by damage |
| Slow | Movement −50% (new in real time, e.g. Hamstring, Frost) |
| Root | Can't move, can act (new) |
| Silence | Can't cast spells |
| Smoke | Bandit Smoke Screen: a cloud on the ground; attacks from inside it miss 50%. Step out of it |
| Shield | Absorbs damage up to a value, then breaks |

- The same effect doesn't stack; reapplying it refreshes the duration. Different effects stack.
- No damage over time deals more than 1/16 of max HP per tick.

## 7. Aggro and Leash

| Behavior | Aggro radius | Notes |
|----------|-------------:|-------|
| Defensive | — | Never starts a fight; fights back when attacked |
| Passive | 6 m | Only notices the hero up close |
| Normal | 12 m | |
| Aggressive | 20 m | Spots the hero from afar |

- Radii shrink by 1 m per level the hero is above the enemy (minimum 4 m) and grow by 1 m per
  level below it, as in WoW.
- **Social pull:** when an enemy enters combat, members of its group within 10 m join.
- **Threat:** v1 is single-player with one hero, so every enemy simply attacks the hero.
- **Leash:** an enemy that is dragged more than 40 m from its spawn point and hasn't taken
  damage for 6 s runs back, heals to full and resets. It ignores the hero on the way back. While
  the hero keeps hurting it, it keeps following, however far (a hunter can kite it).
- **Movement speed:** slow 4 m/s, normal 6 m/s, fast 7.5 m/s (wolves can catch a running hero;
  slow enemies can always be walked away from). The hero runs at 7 m/s.

## 8. Death

- At 0 HP the hero dies: respawn at the last checkpoint with full health, lose 10% of the money
  and the XP toward the next level.
- Enemies that were fighting the hero leash back and reset.

## 9. Regeneration and Resting

- Out of combat, after 5 s: health regenerates 2% of max HP per second (Warriors 4%, from
  Oldworld2's double regeneration).
- **Camp:** press C while standing still out of combat: a fire is lit and health regenerates
  10% per second until the hero moves (from Oldworld2).
- Food (later, with items): heals over 20 s while sitting.

## 10. XP and Levels

Oldworld2's curve, unchanged:

```
KillsNeeded(L) = round(2 + 2 × log2(L))       # same-level trash kills from L to L+1
EnemyXP        = 10 × EnemyLevel × TierMod × LevelMod
XPToNext(L)    = KillsNeeded(L) × 10 × L
LevelMod       = clamp(1 + 0.1 × (EnemyLevel − PlayerLevel), 0.1, 1.5)
TierMod        = trash 1, elite 2, champion 3, boss 5
```

- Levels are uncapped in the long run; v1 ends at level 10.
- Real-time fights with packs are faster to chain than turn-based fights, so the curve may need
  more kills per level. TODO: check by playtesting (target: level 10 after about 1.5 hours).

class_name Rules
extends RefCounted
## Combat and progression formulas (design/mechanics.md). Pure functions, no nodes.

const CRIT_ABILITY := 1.5
const CRIT_AUTO := 2.0
const TIER_DAMAGE := {"player": 1.0, "trash": 0.8, "elite": 1.0, "champion": 1.1, "boss": 1.2}
const TIER_XP := {"trash": 1.0, "elite": 2.0, "champion": 3.0, "boss": 5.0}


## Damage per hit (Oldworld2's formula at level 1). power: ability power; atk/def: the attacker's
## Attack and the defender's Defense (or Magic/Resistance); affinity 1.5 when the element matches.
## It grows with the attacker's level like health does (9% per level), so a hit takes the same
## share of a same-level target's health at every level. (Oldworld2's level factor 2L/5+2 left
## its flat +2 behind: by level 12 enemies hit a third less, measured in the hero's health.)
static func damage(level: int, power: float, atk: float, def: float, affinity: float, crit_mult: float, other: float, rng: RandomNumberGenerator) -> int:
	var base := grow((2.4 * power * atk / maxf(def, 1.0)) / 50.0 + 2.0, level, true)
	var rnd := rng.randf_range(0.85, 1.0)
	return maxi(1, int(floor(3.0 * base * affinity * crit_mult * rnd * other)))


## Stat at a level: HP grows 9% per level, other stats 10% (Oldworld2).
static func grow(base: float, level: int, is_hp := false) -> float:
	return base * (1.0 + (0.09 if is_hp else 0.1) * (level - 1))


static func xp_to_next(level: int) -> int:
	var kills := roundi(2.0 + 2.0 * log(float(level)) / log(2.0))
	return kills * 10 * level


static func enemy_xp(enemy_level: int, player_level: int, tier: String) -> int:
	var level_mod := clampf(1.0 + 0.1 * (enemy_level - player_level), 0.1, 1.5)
	if enemy_level <= player_level - 10:
		return 0
	return roundi(10.0 * enemy_level * TIER_XP.get(tier, 1.0) * level_mod)


## Auto-attack power from the weapon's swing time, so damage per second doesn't depend on it.
static func swing_power(swing_time: float) -> float:
	return swing_time * 12.0


## Oldworld2's element chart (design/mechanics.md): attack element against defender types.
const CHART := {
	"Fire": {"Fire": 0.5, "Water": 0.5, "Ice": 2.0, "Nature": 0.5, "Dark": 2.0},
	"Water": {"Fire": 2.0, "Water": 0.5, "Nature": 2.0},
	"Ice": {"Fire": 0.5, "Water": 0.5, "Ice": 0.5, "Nature": 2.0, "Air": 2.0},
	"Nature": {"Fire": 2.0, "Ice": 2.0, "Air": 0.0},
	"Air": {"Water": 2.0, "Nature": 0.5, "Air": 0.5},
	"Holy": {"Holy": 0.5, "Dark": 2.0},
	"Dark": {"Holy": 2.0, "Dark": 0.5},
}


static func element_mult(element: String, types: Array) -> float:
	var m := 1.0
	var row: Dictionary = CHART.get(element, {})
	for t in types:
		m *= float(row.get(t, 1.0))
	return m

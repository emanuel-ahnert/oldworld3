class_name Combatant
extends Node
## Health, stats, rage, buffs and damage over time of a hero or enemy (design/mechanics.md).
## The owning body (Player, Enemy) moves and animates; this node keeps the numbers.

signal died(killer: Combatant)
signal damaged(amount: int, crit: bool, source: Combatant)
signal attacked(source: Combatant)    ## every strike, also when absorbed or immune
signal missed(source: Combatant)
signal healed(amount: int)

const TICK := 3.0                     ## damage/heal over time tick (s)
const COMBAT_LINGER := 5.0            ## in combat for this long after the last hit

var display_name := ""
var level := 1
var tier := "trash"                   ## player, trash, elite
var base := {"hp": 480.0, "attack": 14.0, "defense": 13.0}
var max_hp := 1
var hp := 1
var attack := 1.0
var defense := 1.0
var magic := 1.0
var resistance := 1.0
var types: Array = ["Physical"]      ## defensive types (element chart); heroes are Physical
var affinities: Array = ["Physical"] ## elements that get the 1.5x bonus
var mana := 0.0
var max_mana := 0.0
var uses_mana := false
var energy := 100.0                   ## rogue resource, 0..100, refills 5 per second
var uses_energy := false
var absorb := 0                       ## damage absorbed before health (Ward of Light)
var immune_until := 0.0               ## takes no damage until then (Divine Shield)
var cheat_death_cd := 0.0             ## > 0: once per this many seconds a lethal hit leaves 10% HP
var _cheat_ready := 0.0
var last_cast := -100.0
var root_until := 0.0
var crit_chance := 0.05
var dodge_chance := 0.0               ## melee hits from the front it dodges (enemies: 5%)
var prey_on_weak := false             ## rogue passive: +10% crit per level above the target
var poison_resist := false
var ticking := false                  ## true while a damage-over-time tick is being applied            ## rogue passive: poison ticks do 75% less
var base_crit := 0.05                 ## crit chance without gear
var gear := {}                        ## stat bonuses of the equipped items (Items.totals)
var weapon_damage := -1.0              ## the hero's weapon damage (0: fists); -1: none (enemies, x1)
## The hero's physical hits grow with the weapon instead of the level (Rules.weapon_mult).
var weapon_mult := 1.0                 ## physical hits multiplied by this (Rules.weapon_mult)
var swing_time := 2.0
var affinity := 1.5                   ## Physical attacks by Physical-typed units
var rage := 0.0                       ## warrior resource, 0..100
var uses_rage := false
var regen_mult := 1.0                 ## out-of-combat regeneration factor (warriors 2x)
var dead := false
var last_combat := -100.0
var stun_until := 0.0
var slow_until := 0.0
var slow_factor := 1.0
var slow_name := "Slowed"             ## shown on the HUD ("Dazed")
var buffs := {}                       ## name -> {until, attack, damage, attack_speed}
var dots := {}                        ## name -> {until, next, amount, source, heal}
var body: Node3D                      ## the unit this belongs to
var rng := RandomNumberGenerator.new()
var _regen := 0.0


func setup(p_level: int, p_base: Dictionary) -> void:
	level = p_level
	base = p_base
	recompute()
	mana = max_mana
	hp = max_hp
	rng.randomize()


## Derived stats from the base, the level and the equipped gear (Items.totals). Keeps the
## current health and mana (clamped), so equipping mid-fight doesn't heal.
func recompute() -> void:
	max_hp = roundi(Rules.grow(base.hp, level, true) + float(gear.get("hp", 0)))
	attack = Rules.grow(base.attack, level) + float(gear.get("attack", 0))
	defense = Rules.grow(base.defense, level) + float(gear.get("defense", 0))
	magic = Rules.grow(float(base.get("magic", 4.0)), level) + float(gear.get("magic", 0))
	resistance = Rules.grow(float(base.get("resistance", base.defense * 0.7)), level) + float(gear.get("resistance", 0))
	max_mana = float(base.get("mana", 0.0))      # mana doesn't grow with level (Oldworld2)
	if max_mana > 0.0:
		max_mana += float(gear.get("mana", 0))
	crit_chance = base_crit + float(gear.get("crit", 0)) / 100.0
	weapon_mult = 1.0 if weapon_damage < 0.0 else Rules.weapon_mult(weapon_damage)
	hp = mini(hp, max_hp)
	mana = minf(mana, max_mana)


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func in_combat() -> bool:
	return now() - last_combat < COMBAT_LINGER


func mark_combat() -> void:
	last_combat = now()


func stunned() -> bool:
	return now() < stun_until


func move_factor() -> float:
	if now() < root_until:
		return 0.0
	return slow_factor if now() < slow_until else 1.0


## Slowed to `factor` of the speed for `duration` s (a later slow replaces it).
func slow(duration: float, factor: float, name := "Slowed") -> void:
	slow_until = now() + duration
	slow_factor = factor
	slow_name = name


func buff_mult(key: String) -> float:
	var m := 1.0
	for b in buffs.values():
		m *= float(b.get(key, 1.0))
	return m


func add_buff(name: String, duration: float, data: Dictionary) -> void:
	var b := data.duplicate()
	b["until"] = now() + duration
	buffs[name] = b


## Everything on this unit for the HUD: [{name, left (s, < 0: no timer), debuff}]. Buffs that
## lower a stat, damage over time and stun, root and slow are debuffs.
## Buffs, debuffs and states for the HUD: {name, id (Icons), left (s, -1 = lasting), debuff}.
func auras() -> Array:
	var t := now()
	var out: Array = []
	for k: String in buffs:
		var b: Dictionary = buffs[k]
		var debuff := false
		for v in b.values():
			if v is float and v < 1.0 and v != b.until:
				debuff = true
		var left := float(b.until) - t
		out.append({"name": k.capitalize(), "id": k, "left": left if left < 600.0 else -1.0, "debuff": debuff})
	for k: String in dots:
		var d: Dictionary = dots[k]
		out.append({"name": k.capitalize(), "id": k, "left": float(d.until) - t, "debuff": not d.heal})
	if t < stun_until and not buffs.has("gouge") and not buffs.has("sap"):    # (they show as themselves)
		out.append({"name": "Stunned", "id": "stunned", "left": stun_until - t, "debuff": true})
	if t < root_until:
		out.append({"name": "Rooted", "id": "rooted", "left": root_until - t, "debuff": true})
	if t < slow_until:
		out.append({"name": slow_name, "id": "slowed", "left": slow_until - t, "debuff": true})
	if t < immune_until:
		out.append({"name": "Immune", "id": "immune", "left": immune_until - t, "debuff": false})
	if absorb > 0:
		out.append({"name": "Absorb %d" % absorb, "id": "absorb", "left": -1.0, "debuff": false})
	# "total": the whole duration, for the icons' clock sweep. Kept here per aura: when its end
	# moves later (applied anew, refreshed) the clock starts over.
	var seen := {}
	for a: Dictionary in out:
		var id := String(a.id)
		var left := float(a.left)
		if left < 0.0:
			a["total"] = -1.0
			continue
		var end := t + left
		var was: Array = _aura_clock.get(id, [])
		if was.is_empty() or end > float(was[0]) + 0.05:
			was = [end, left]
		else:
			was[0] = end
		seen[id] = was
		a["total"] = maxf(float(was[1]), left)
	_aura_clock = seen
	return out


var _aura_clock := {}                 ## aura id -> [end time, duration] (auras())


func has_buff(name: String) -> bool:
	return buffs.has(name)


## Damage over time (or heal over time with heal = true): fraction of the target's max HP per tick.
## drain: the source heals by the damage dealt (Drain Life).
func add_dot(name: String, duration: float, fraction: float, source: Combatant, heal := false, drain := false) -> void:
	dots[name] = {"until": now() + duration, "next": now() + TICK, "amount": maxi(1, roundi(max_hp * fraction)), "source": source, "heal": heal, "drain": drain}


## A physical hit with an element (Paladin's Righteous Strike): Attack vs. Defense, but the
## element chart and the element's affinity apply.
## Crit chance against `target` (Prey on the Weak adds 10% per level above it, up to 100%).
func _crit_vs(target: Combatant) -> float:
	if prey_on_weak and target:
		return minf(1.0, crit_chance + 0.1 * maxi(0, level - target.level))
	return crit_chance


func roll_damage_elem(target: Combatant, power: float, element: String) -> Dictionary:
	var crit := rng.randf() < _crit_vs(target)
	var aff := 1.5 if element in affinities else 1.0
	var other: float = buff_mult("damage") * Rules.element_mult(element, target.types) * float(Rules.TIER_DAMAGE.get(tier, 1.0)) * weapon_mult
	var amount := Rules.damage(_hit_level(), power, attack * buff_mult("attack"), target.defense * target.buff_mult("defense"), aff, Rules.CRIT_ABILITY if crit else 1.0, other, rng)
	return {"amount": amount, "crit": crit}


## The level a physical hit grows with: the hero's weapon brings the growth (level 1 here),
## everyone else's hits grow with their level.
func _hit_level() -> int:
	return 1 if weapon_damage >= 0.0 else level


## One hit from this unit on `target`. power: ability power; auto: auto-attack (2x crit).
## Returns {amount, crit}; the caller applies it with target.take_damage.
func roll_damage(target: Combatant, power: float, auto := false, extra := 1.0) -> Dictionary:
	var crit := rng.randf() < _crit_vs(target)
	var cm := (Rules.CRIT_AUTO if auto else Rules.CRIT_ABILITY) if crit else 1.0
	var other: float = buff_mult("damage") * float(Rules.TIER_DAMAGE.get(tier, 1.0)) * extra * weapon_mult
	var amount := Rules.damage(_hit_level(), power, attack * buff_mult("attack"), target.defense * target.buff_mult("defense"), affinity, cm, other, rng)
	return {"amount": amount, "crit": crit}


## A spell hit: Magic vs. Resistance, element chart against the target's types.
func roll_spell(target: Combatant, power: float, element: String) -> Dictionary:
	var crit := rng.randf() < _crit_vs(target)
	var aff := 1.5 if element in affinities else 1.0
	var other: float = buff_mult("damage") * Rules.element_mult(element, target.types)
	var amount := Rules.damage(level, power, magic * buff_mult("magic"), target.resistance, aff, Rules.CRIT_ABILITY if crit else 1.0, other, rng)
	return {"amount": amount, "crit": crit, "mult": Rules.element_mult(element, target.types)}


## True while this combatant lands an auto-attack (a swing, an Auto Shot): its damage numbers
## are white; everything else (abilities, their damage over time) shows yellow, WoW style.
var auto_hit := false
## Whether the last hit taken was an auto-attack (read by the damage number).
var last_hit_auto := false


func take_damage(amount: int, crit: bool, source: Combatant) -> void:
	if dead:
		return
	last_hit_auto = source != null and source.auto_hit
	if source:
		attacked.emit(source)
	if now() < immune_until:
		if body:
			World.float_text(body.global_position + Vector3(0, 2.0, 0), "Immune", Color(1, 0.95, 0.6), 36, body)
		return
	if absorb > 0:
		var soaked := mini(absorb, amount)
		absorb -= soaked
		amount -= soaked
		if amount <= 0:
			if body:
				World.float_text(body.global_position + Vector3(0, 2.0, 0), "Absorbed", Color(0.9, 0.9, 1.0), 32, body)
			return
	if has_buff("mana_shield") and uses_mana:
		# Mana Shield: half of the damage is taken from mana instead (1 mana per point).
		var soak := mini(amount / 2, int(mana))
		mana -= soak
		amount -= soak
		if mana < 1.0:
			buffs.erase("mana_shield")
	hp = maxi(0, hp - amount)
	mark_combat()
	if uses_rage:
		rage = minf(100.0, rage + 50.0 * amount / max_hp)   # 1 rage per 2% of max HP lost
	if hp == 0 and cheat_death_cd > 0.0 and now() >= _cheat_ready:
		# Cheat Death (rogue): survive with 10% health instead, every debuff gone.
		_cheat_ready = now() + cheat_death_cd
		hp = maxi(1, max_hp / 10)
		clear_debuffs()
		if body:
			World.float_text(body.global_position + Vector3(0, 2.2, 0), "Cheat Death", Color(0.9, 0.9, 1.0), 44, body)
	damaged.emit(amount, crit, source)
	if hp == 0:
		dead = true
		died.emit(source)


## Takes off everything harmful: damage over time, weakening buffs (a value under 1, as
## auras() tells debuffs), stun, root and slow.
func clear_debuffs() -> void:
	for k in dots.keys():
		if not dots[k].heal:
			dots.erase(k)
	for k in buffs.keys():
		var b: Dictionary = buffs[k]
		for v in b.values():
			if v is float and v < 1.0 and v != b.until:
				buffs.erase(k)
				break
	stun_until = 0.0
	root_until = 0.0
	slow_until = 0.0


func heal(amount: int) -> void:
	if dead or amount <= 0:
		return
	var before := hp
	hp = mini(max_hp, hp + amount)
	if hp > before:
		healed.emit(hp - before)


func revive() -> void:
	dead = false
	hp = max_hp
	rage = 0.0
	absorb = 0
	energy = 100.0
	mana = max_mana
	buffs.clear()
	dots.clear()


func _process(dt: float) -> void:
	if dead:
		return
	var t := now()
	for k in buffs.keys():
		if t > float(buffs[k].until):
			buffs.erase(k)
	for k in dots.keys():
		var d: Dictionary = dots[k]
		if t >= float(d.next):
			d.next = float(d.next) + TICK
			if d.heal:
				heal(d.amount)
			else:
				var amt: int = d.amount
				if poison_resist and k == "poison":
					amt = maxi(1, amt / 4)
				ticking = true
				take_damage(amt, false, d.source)
				ticking = false
				if d.get("drain", false) and d.source and not d.source.dead:
					d.source.heal(d.amount)
				if dead:
					return
		if t > float(d.until):
			dots.erase(k)
	if not in_combat():
		# Out of combat: health regenerates 2% per second (warriors 4%), rage decays.
		if hp < max_hp:
			_regen += max_hp * 0.02 * regen_mult * dt
			if _regen >= 1.0:
				hp = mini(max_hp, hp + int(_regen))
				_regen -= int(_regen)
		rage = maxf(0.0, rage - 2.0 * dt)
	if uses_energy:
		energy = minf(100.0, energy + 5.0 * dt)
	if uses_mana and t - last_cast > 5.0 and mana < max_mana:
		mana = minf(max_mana, mana + max_mana * 0.02 * dt)

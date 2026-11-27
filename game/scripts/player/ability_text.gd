class_name AbilityText
extends RefCounted
## Ability descriptions for tooltips and the spell book (hand-kept: change them with the
## abilities in player.gd; design/classes.md has the overview). Placeholders, filled in with the
## hero's current stats (left out where there is no hero): {hp:F} the share F of max health in
## HP; {phys:P[:Element]} / {spell:P:Element} the damage of power P against a same-level
## common enemy (Defense/Resistance of a typical one), without crits.

const TEXT := {
	"druid:Bear Form": "The druid becomes a bear: melee with Magic as Attack and a 2.0 s swing, Defense ×2, and shifting heals 25% of max health{hp:0.25}. No spells until you press it again to shift back",
	"druid:Grasping Roots": "Instant, 30 m: roots burst from the ground under the target, Nature damage (power 30{spell:30:Nature}), and hold it in place for 6 s (it can still attack and cast)",
	"druid:Insect Swarm": "Instant, 30 m: a swarm eats at the target for 24 s, 4% of its max health every 3 s (32% in all), and lowers its Attack by 25% meanwhile",
	"druid:Moonbeam": "Cast 2.0 s, 30 m: a column of moonlight comes down on the target, Holy damage (power 55{spell:55:Holy})",
	"druid:Rejuvenate": "Instant: heals 4% of your max health{hp:0.04} every 3 s for 24 s (32% in all{hp:0.32})",
	"druid:Thorn Lash": "Cast 1.6 s, 30 m, no mana: a Nature bolt (power 50{spell:50:Nature})",
	"hunter:Auto Shot": "Arrows from 5–30 m on the swing timer",
	"hunter:First Aid": "Cast 2.0 s: bandages heal 30% of your max health{hp:0.3}",
	"hunter:Mark Prey": "Instant, 30 m: the target's Defense −25% for 30 s, so every physical hit on it deals more",
	"hunter:Steady Shot": "Instant arrow, 30 m: Physical damage (power 50{phys:50})",
	"hunter:Venom Arrow": "Instant arrow, 30 m: Nature damage (power 25{phys:25:Nature}) and poison, 4% of the target's max health every 3 s for 15 s (20% in all)",
	"hunter:Volley": "Instant: an arrow at every enemy within 8 m of the target, Nature damage (power 45{phys:45:Nature}) each",
	"mage:Blink": "Teleport 15 m forward; breaks roots and slows",
	"mage:Blizzard": "Channelled for 6 s: snow and ice rain on an 8 m circle at the target; every second Ice damage (power 22{spell:22:Ice}) to each enemy in it and a 50% slow for 2 s. Moving or a stun breaks it",
	"mage:Fire Bolt": "Cast 1.6 s, 30 m, no mana: a Fire projectile (power 40{spell:40:Fire})",
	"mage:Fireball": "Cast 2.0 s, 30 m: a big Fire projectile (power 60{spell:60:Fire}) that sets the target alight: 5% of its max health every 3 s for 24 s (40% in all)",
	"mage:Frost Ring": "Instant: a ring of frost bursts out to 8 m around you, Ice damage (power 45{spell:45:Ice}) to every enemy in it, and freezes their feet for 5 s",
	"mage:Ice Bolt": "Cast 2.0 s, 30 m: an Ice projectile (power 55{spell:55:Ice}); slows the target by 40% for 6 s",
	"mage:Ignite": "Instant, 30 m: sets the target on fire, 5% of its max health every 3 s for 24 s (40% in all)",
	"mage:Mana Shield": "For 20 s half of the damage you take is paid with mana instead of health (it ends early when the mana runs out)",
	"mage:Polymorph": "Cast 1.5 s: turns the target into a sheep for 20 s. It wanders about, can't attack and heals 20% of its health a second; any damage turns it back (and it comes for you). One sheep at a time: a new Polymorph frees the last one",
	"paladin:Devotion": "Your Defense +25% for 60 s",
	"paladin:Divine Shield": "You take no damage at all for 6 s",
	"paladin:Healing Light": "Cast 2.0 s: heals 30% of your max health{hp:0.3}",
	"paladin:Holy Seal": "For 30 s every melee hit of yours carries an extra Holy hit (power 20{phys:20:Holy})",
	"paladin:Judgment Hammer": "A hammer blow, Holy damage (power 30{phys:30:Holy}), that stuns the target for 2.5 s",
	"paladin:Righteous Strike": "A melee strike, Holy damage (power 50{phys:50:Holy})",
	"priest:Holy Burst": "Instant: holy light bursts out to 8 m around you, Holy damage (power 45{spell:45:Holy}) to every enemy in it",
	"priest:Mend": "Cast 1.5 s: heals 25% of your max health{hp:0.25}",
	"priest:Mind Pain": "Instant, 30 m: Dark damage over time, 4% of the target's max health every 3 s for 24 s (32% in all)",
	"priest:Renewal": "Instant: heals 4% of your max health{hp:0.04} every 3 s for 24 s (32% in all{hp:0.32})",
	"priest:Smite": "Cast 1.8 s, 30 m, no mana: a Holy bolt (power 45{spell:45:Holy})",
	"priest:Ward of Light": "Instant: a ward that soaks up the next 25% of your max health{hp:0.25} in damage",
	"rogue:Cheap Shot": "A low blow (power 10{phys:10}) that stuns the target for 3 s. Gives a combo point",
	"rogue:Gut Slash": "A deep slash, Physical damage (power 75{phys:75}). Gives a combo point",
	"rogue:Knife Throw": "A thrown knife, 5–25 m: Physical damage (power 45{phys:45}). Gives a combo point",
	"rogue:Poisoned Blade": "A poisoned cut (power 20{phys:20}): poison, 4% of the target's max health every 3 s for 15 s (20% in all), and it moves at half speed for as long. Gives a combo point",
	"rogue:Quick Stab": "A quick stab (power 45{phys:45}) with +25% crit chance. Gives a combo point",
	"rogue:Stealth": "Out of combat: you fade (half transparent) and enemies don't notice you at all; 70% speed (Master of Subtlety: 120%). The first hit out of stealth is always a critical hit and deals +50%. Any action or damage breaks it",
	"rogue:Eviscerate": "A finishing cut that spends all combo points: power 27 for each (5 points: power 135{phys:135}). Needs at least one",
	"rogue:Gouge": "A blow that takes the target out of the fight for 6 s: it can't move, attack or use abilities. Any damage wakes it (poisons and bleeds too), and you stop swinging at it",
	"rogue:Sap": "Only in stealth, and you stay hidden: the target is knocked out for 15 s without noticing you (no fight starts). Any damage wakes it",
	"shaman:Chain Lightning": "Cast 2.0 s, 30 m: lightning hits the target and jumps to up to 2 more enemies within 10 m of it, Air damage (power 45{spell:45:Air}) each",
	"shaman:Flame Shock": "Instant, 25 m: Fire damage (power 25{spell:25:Fire}) and a burn, 4% of the target's max health every 3 s for 24 s (32% in all)",
	"shaman:Frost Shock": "Instant, 25 m: Ice damage (power 45{spell:45:Ice}) and the target is slowed by 50% for 8 s",
	"shaman:Healing Wave": "Cast 2.0 s: heals 25% of your max health{hp:0.25}",
	"shaman:Stone Shock": "Instant, 25 m: Nature damage (power 40{spell:40:Nature}) and the target is silenced: no special abilities for 4 s",
	"shaman:Storm Bolt": "Cast 1.6 s, 30 m, no mana: an Air bolt (power 45{spell:45:Air})",
	"warlock:Curse of Weakness": "Instant, 30 m: the target's Attack −25% for 30 s",
	"warlock:Siphon Life": "Instant, 30 m: for 15 s takes 5% of the target's max health every 3 s (25% in all) and heals you by as much",
	"warlock:Fear": "Cast 2.0 s, 30 m: the target panics and runs about at random for 8 s, its hands in the air; it doesn't attack or use abilities meanwhile",
	"warlock:Hellfire Rain": "Cast 2.0 s, 30 m: meteors rain into an 8 m circle at the target (marked on the ground while casting) for 5 s: every second Fire damage (power 20{spell:20:Fire}) to every enemy in it",
	"warlock:Life Tap": "Instant: turns 10% of your max health{hp:0.1} into as much mana. Not when it would leave you with almost no health",
	"warlock:Hex Bolt": "Cast 1.6 s, 30 m, no mana: a Dark bolt (power 40{spell:40:Dark})",
	"warlock:Wither": "Instant, 30 m: Dark damage over time, 4% of the target's max health every 3 s for 30 s (40% in all)",
	"warrior:Auto-attack": "Swing timer from the weapon (2H 2.6 s, 1H 1.8 s); hits give rage",
	"warrior:Battle Horn": "Blow the war horn: gain 20 rage at once. Usable out of combat and outside the global cooldown, so a fight can open with a Heavy Strike",
	"warrior:Charge": "Rush to the target from 8–25 m, stun 1.5 s, +15 rage; out of combat only (Juggernaut: also in combat, no rage there, no cooldown)",
	"warrior:Heavy Strike": "Instant strong hit (power 50{phys:50})",
	"warrior:Overwhelm": "Usable for 5 s after the target dodges or a Smoke miss: a blow that can't be dodged (power 100{phys:100})",
	"warrior:Rend": "Bleed: 5% of the target's max health every 3 s for 30 s (50% in all)",
	"warrior:Thunder Clap": "Instant: power 25{phys:25} to every enemy within 8 m, and their attacks 20% slower for 10 s. The answer to packs",
	"warrior:Whirlwind": "Spin with the blade out: power 40{phys:40} to every enemy within 4 m once a second, 10 rage a second (the first on use) until rage runs out or you press it again. Every kill by it takes 5 s off its cooldown. You can move; no other abilities but Battle Horn, no auto-attack meanwhile",
}

## class -> [[level, name, text]]
const PASSIVES := {
	"warrior": [[3, "Enrage", "Taking a crit (or 30% on any hit) gives +25% damage for 12 s"], [8, "Second Wind", "30% chance when hit (always on a crit taken): heals 4% of max health{hp:0.04} every 3 s for 9 s; refreshes, doesn't stack"], [10, "Juggernaut", "Charge has no cooldown and works in combat (no rage from it there); 1 rage per second while fighting"]],
	"warlock": [[4, "Demon Armor", "In combat you heal 2% of your max health{hp:0.02} every 3 s."], [10, "Dark Ward", "Every enemy that hits you in melee is cursed with Curse of Weakness: its Attack −25% for 30 s."]],
	"shaman": [[4, "Totems", "Entering combat places a Wrath Totem and a Healing Stream Totem for 30 s. Within 20 m of them your Magic is +25% and you heal 4% of your max health{hp:0.04} every 3 s."]],
	"rogue": [[2, "Improved Sprint", "Sprint stamina lasts five times as long."], [6, "Master of Subtlety", "In stealth you move at 120% speed instead of 70%."], [8, "Combat Specialization", "When an enemy dodges your attack you gain 20 energy; a kill gives 40."], [8, "Cheat Death", "Once every 2 minutes, a lethal hit leaves 10% health instead and removes all your debuffs (poisons, bleeds, curses, stuns, roots, slows)."],
		[8, "Prey on the Weak", "+10% critical hit chance for each level above the enemy, up to 100%."],
		[10, "Poison Resistance", "Poison does 75% less damage to you."]],
	"hunter": [[2, "Concussive Shots", "Every arrow you shoot (Auto Shot, Steady Shot, Venom Arrow, Volley) slows its target by 60% for 4 s."]],
	"druid": [[4, "Thorns", "Enemies hitting you in melee take 7% of your max health{hp:0.07} in damage."]],
}


## Tooltip: name and key, level, cost and cooldown, what it does.
static func describe(cls: String, a: Dictionary, key := -1) -> String:
	var cost := ""
	for r in ["rage", "mana", "energy"]:
		if int(a.get(r, 0)) > 0:
			cost = "%d %s" % [int(a[r]), r]
	var cd := float(a.get("cd", 0.0))
	var parts := ["Level %d" % int(a.level)]
	if cost != "":
		parts.append(cost)
	if cd > 0.0:
		parts.append(("%d s cooldown" % roundi(cd)) if cd < 60.0 else ("%d min cooldown" % roundi(cd / 60.0)))
	var k := "" if key == 0 else " (%d)" % (key if key > 0 else int(a.key))
	return "%s%s\n%s\n%s" % [a.name, k, ", ".join(parts), fill(TEXT.get("%s:%s" % [cls, a.name], ""))]


## Buffs, debuffs and states that are no ability of their own (aura icons' tooltips): id ->
## [name, text].
const EFFECTS := {
	"stunned": ["Stunned", "Can't move, attack or cast."],
	"rooted": ["Rooted", "Held in place: can't move, but can still attack and cast."],
	"slowed": ["Slowed", "Moves and attacks more slowly."],
	"immune": ["Immune", "Takes no damage."],
	"absorb": ["Absorb", "A shield soaks up the next damage taken."],
	"poison": ["Poison", "Loses 4% of max health every 3 s."],
	"burn": ["Burning", "Loses 4% of max health every 3 s."],
	"life_drain": ["Life Drain", "Loses health every 3 s to the one draining it."],
	"healing_stream": ["Healing Stream", "Heals 4% of max health{hp:0.04} every 3 s near the Healing Stream Totem."],
	"wrath_totem": ["Wrath Totem", "Magic +25% near the totem."],
	"berserk": ["Berserk", "Enraged: deals more damage."],
	"howl": ["Howl", "The pack's howl: wolves nearby hit harder."],
	"enrage": ["Enrage", "Your damage +25%."],
	"second_wind": ["Second Wind", "Heals 4% of max health{hp:0.04} every 3 s."],
	"demon_armor": ["Demon Armor", "Heals 2% of max health{hp:0.02} every 3 s in combat."],
	"fear": ["Fear", "Runs about in panic: can't attack or use abilities."],
	"gouge": ["Gouge", "Out of the fight: can't move, attack or use abilities. Any damage ends it."],
	"sap": ["Sap", "Knocked out: can't move, attack or notice anyone. Any damage ends it."],
	"polymorph": ["Polymorph", "A sheep: wanders about, can't attack, heals fast. Any damage breaks it."],
}


## The tooltip of a buff/debuff icon: the ability it comes from (any class), else EFFECTS, else
## just its name. `left`: seconds left (-1: lasting).
static func describe_aura(id: String, name: String, left: float) -> String:
	var small := ("%d s left" % ceili(left)) if left >= 0.0 else ""
	for c in ["warrior", "mage", "rogue", "priest", "paladin", "warlock", "hunter", "shaman", "druid"]:
		for a: Dictionary in Player.abilities_of(c):
			if String(a.id) == id:
				return "%s\n%s\n%s" % [a.name, small, fill(TEXT.get("%s:%s" % [c, a.name], ""))]
	if EFFECTS.has(id):
		return "%s\n%s\n%s" % [EFFECTS[id][0], small, fill(EFFECTS[id][1])]
	return "%s\n%s" % [name, small]


## The placeholders ({hp:…}, {phys:…}, {spell:…}) filled in from the hero (World.player).
static func fill(text: String) -> String:
	var re := RegEx.create_from_string("\\{(hp|phys|spell):([0-9.]+)(?::(\\w+))?\\}")
	var hero: Player = World.player if is_instance_valid(World.player) else null
	var out := text
	for m in re.search_all(text):
		var rep := ""
		if hero:
			var st: Combatant = hero.stats
			var v := float(m.get_string(2))
			match m.get_string(1):
				"hp":
					rep = " (%d)" % maxi(1, roundi(st.max_hp * v))
				"phys", "spell":
					var d := estimate(st, m.get_string(1) == "spell", v, m.get_string(3) if m.get_string(3) != "" else "Physical")
					rep = ": %d–%d damage" % [d.x, d.y]
		out = out.replace(m.get_string(), rep)
	return out


## The damage range of power `power` against a same-level common enemy (Defense 10,
## Resistance 8 at level 1, the middle of enemy_data), neutral to the element, without crits.
static func estimate(st: Combatant, spell: bool, power: float, element: String) -> Vector2i:
	var aff := 1.5 if element in st.affinities else 1.0
	if spell:
		return Rules.damage_range(st.level, power, st.magic * st.buff_mult("magic"), Rules.grow(8.0, st.level), aff, st.buff_mult("damage"))
	var lvl := 1 if st.weapon_damage >= 0.0 else st.level
	if element == "Physical":
		aff = st.affinity
	return Rules.damage_range(lvl, power, st.attack * st.buff_mult("attack"), Rules.grow(10.0, st.level), aff, st.buff_mult("damage") * float(Rules.TIER_DAMAGE.get(st.tier, 1.0)) * st.weapon_mult)

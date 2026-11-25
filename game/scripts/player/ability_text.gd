class_name AbilityText
extends RefCounted
## Ability descriptions for tooltips and the spell book, generated from design/classes.md
## by tools/docs/ability_text.py (don't edit by hand).

const TEXT := {
	"druid:Bear Form": "The druid becomes a bear (melee with Magic as Attack, Defense ×2, heals 25% on shifting; spells unavailable until shifting back)",
	"druid:Grasping Roots": "Root 6 s",
	"druid:Insect Swarm": "Damage over time + Attack −25%",
	"druid:Moonbeam": "Holy cast",
	"druid:Rejuvenate": "Heal over time",
	"druid:Thorn Lash": "Nature bolt, free filler",
	"mage:Blizzard": "Channelled for 6 s: snow and ice rain on an 8 m circle at the target; every second Ice damage (power 22) to each enemy in it and a 50% slow for 2 s. Moving or a stun breaks it",
	"hunter:Auto Shot": "Arrows from 5–30 m on the swing timer",
	"hunter:First Aid": "Cast heal 30%",
	"hunter:Mark Prey": "Target Defense −25%",
	"hunter:Steady Shot": "Instant arrow, power 50, 30 m",
	"hunter:Venom Arrow": "Poison",
	"hunter:Volley": "Nature area",
	"mage:Blink": "Teleport 15 m forward, breaks roots and slows",
	"mage:Fire Bolt": "Cast 1.6 s, power 40, Fire projectile (filler)",
	"mage:Fireball": "Cast 2.0 s, power 60, a big Fire projectile; ignites the target (Ignite's burn)",
	"mage:Frost Ring": "Instant, all enemies within 8 m: power 45 Ice, rooted 5 s",
	"mage:Ice Bolt": "Cast 2.0 s, power 55, Ice; slows the target 40% for 6 s",
	"mage:Ignite": "Instant, Fire burn: 1/32 max HP every 3 s for 24 s",
	"mage:Mana Shield": "20 s: half of the damage taken is paid with mana",
	"paladin:Devotion": "Defense +25%",
	"paladin:Divine Shield": "Immune 6 s",
	"paladin:Healing Light": "Cast heal 30%",
	"paladin:Holy Seal": "Every hit adds a Holy hit, 30 s",
	"paladin:Judgment Hammer": "Stun 2.5 s",
	"paladin:Righteous Strike": "Holy melee",
	"priest:Holy Burst": "Holy area",
	"priest:Mend": "Cast heal 25%",
	"priest:Mind Pain": "Dark damage over time",
	"priest:Renewal": "Heal over time",
	"priest:Smite": "Holy bolt, free filler",
	"priest:Ward of Light": "Absorbs 25% max HP",
	"rogue:Cheap Shot": "Power 10, stuns 3 s",
	"rogue:Gut Slash": "Power 75",
	"rogue:Knife Throw": "Ranged 25 m, power 45",
	"rogue:Poisoned Blade": "Power 20 + Poison (1/32 max HP every 3 s, 15 s)",
	"rogue:Quick Stab": "Power 45, +25% crit chance",
	"rogue:Stealth": "Out of combat: aggro radii ×0.3, 70% speed; the first hit out of stealth deals +50%; any action or damage breaks it",
	"shaman:Chain Lightning": "Up to 3 targets",
	"shaman:Flame Shock": "Fire + burn",
	"shaman:Frost Shock": "Slow",
	"shaman:Healing Wave": "Cast heal 25%",
	"shaman:Stone Shock": "Silences: no special abilities 4 s",
	"shaman:Storm Bolt": "Air bolt, free filler",
	"warlock:Curse of Weakness": "Target Attack −25%",
	"warlock:Drain Life": "Drain over time, heals you",
	"warlock:Dread": "Target attacks half as often",
	"warlock:Hellfire Rain": "Meteors rain into an 8 m circle at the target (marked on the ground while casting): Fire damage to every enemy in it",
	"warlock:Hex Bolt": "Dark bolt, free filler",
	"warlock:Wither": "Dark damage over time",
	"warrior:Auto-attack": "Swing timer from the weapon (2H 2.6 s, 1H 1.8 s); hits give rage",
	"warrior:Battle Cry": "Attack +25% for 2 min; usable out of combat. Costs nothing and gives 10 rage, so a fight can start with a Heavy Strike sooner",
	"warrior:Charge": "Rush to the target from 8–25 m, stun 1.5 s, +15 rage; out of combat only (Juggernaut: also in combat, no rage there, no cooldown)",
	"warrior:Heavy Strike": "Instant strong hit, power 50",
	"warrior:Overwhelm": "Usable for 5 s after the target dodges or a Smoke miss; power 100, can't be dodged",
	"warrior:Rend": "Bleed: 1/32 of max HP every 3 s for 15 s",
	"warrior:Whirlwind": "Spin with the blade out: power 40 to every enemy within 4 m once a second, 10 rage a second (the first on use) until rage runs out or you press it again. You can move; no other abilities but Battle Cry, no auto-attack meanwhile",
	"warrior:Thunder Clap": "Area: power 25 to all enemies within 8 m, slows their attacks by 20% for 10 s. Answer to packs",
}

## class -> [[level, name, text]]
const PASSIVES := {
	"warrior": [[3, "Enrage", "Taking a crit (or 30% on any hit) gives +25% damage for 12 s"], [8, "Second Wind", "30% chance when hit (always on a crit taken): heals 1/32 of max HP every 3 s for 9 s; refreshes, doesn't stack"], [10, "Juggernaut", "Charge has no cooldown and works in combat (no rage from it there); 1 rage per second while fighting"]],
	"warlock": [[4, "Demon Armor", "Regeneration in combat"]],
	"shaman": [[4, "Totems", "Entering combat places a Wrath Totem (Magic +25% nearby) and a Healing Stream Totem for 30 s"]],
	"rogue": [[6, "Improved Sprint", "Sprint stamina lasts five times as long."], [8, "Cheat Death", "Once every 2 minutes, a lethal hit leaves 10% health instead."],
		[8, "Prey on the Weak", "+10% critical hit chance for each level above the enemy, up to 100%."],
		[10, "Poison Resistance", "Poison does 75% less damage to you."]],
	"hunter": [[2, "Concussive Shots", "Every arrow you shoot (Auto Shot, Steady Shot, Venom Arrow, Volley) slows its target by 60% for 4 s."]],
	"druid": [[4, "Thorns", "Enemies hitting you in melee take 1/16 of your max health."]],
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
	return "%s%s\n%s\n%s" % [a.name, k, ", ".join(parts), TEXT.get("%s:%s" % [cls, a.name], "")]

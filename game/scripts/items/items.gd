class_name Items
extends RefCounted
## Items, loot and prices (design/items.md, after Oldworld2's design/items.md). An item is a plain
## Dictionary so it saves as JSON:
##   {name, slot, kind, ilvl, rarity, stats: {damage, attack, defense, magic, resistance, hp, mana, crit},
##    count (potions only)}
## Gear changes the hero's numbers only; the look stays the class outfit for now.

const SLOTS := ["head", "chest", "legs", "hands", "feet", "main", "off", "neck", "ring"]
const SLOT_NAMES := {"head": "Head", "chest": "Chest", "legs": "Legs", "hands": "Hands", "feet": "Feet",
	"main": "Main hand", "off": "Off hand", "neck": "Neck", "ring": "Ring"}
const SLOT_MOD := {"chest": 1.0, "legs": 1.0, "main": 1.0, "head": 0.8, "hands": 0.6, "feet": 0.6,
	"off": 0.6, "neck": 0.45, "ring": 0.45}
const BAG_SIZE := 20

const RARITY := {
	"common": {"mod": 1.0, "color": Color(0.92, 0.92, 0.92), "price": 5, "bonus": 0},
	"uncommon": {"mod": 1.2, "color": Color(0.3, 0.95, 0.3), "price": 12, "bonus": 1},
	"rare": {"mod": 1.45, "color": Color(0.3, 0.55, 1.0), "price": 30, "bonus": 2},
	"epic": {"mod": 1.75, "color": Color(0.75, 0.35, 1.0), "price": 75, "bonus": 3},
}
## Rarity odds per source (common, uncommon, rare, epic), items.md section 7.
const ODDS := {"trash": [80, 18, 2, 0], "elite": [55, 35, 9, 1], "champion": [0, 60, 34, 6], "shop": [100, 0, 0, 0]}

## Armor types: a class wears its own and lighter ones.
const ARMOR_RANK := {"cloth": 0, "leather": 1, "mail": 2, "plate": 3}
const CLASS_ARMOR := {"warrior": "plate", "paladin": "plate", "hunter": "mail", "shaman": "mail",
	"rogue": "leather", "druid": "leather", "mage": "cloth", "warlock": "cloth", "priest": "cloth"}
## Defense and Resistance per point of budget by armor type (cloth protects against magic).
const ARMOR_STATS := {"cloth": [0.5, 1.0], "leather": [0.8, 0.6], "mail": [0.95, 0.45], "plate": [1.15, 0.3]}
const ARMOR_NOUNS := {
	"plate": {"head": "Helm", "chest": "Breastplate", "legs": "Legplates", "hands": "Gauntlets", "feet": "Sabatons"},
	"mail": {"head": "Coif", "chest": "Hauberk", "legs": "Leggings", "hands": "Gloves", "feet": "Boots"},
	"leather": {"head": "Cap", "chest": "Jerkin", "legs": "Breeches", "hands": "Gloves", "feet": "Boots"},
	"cloth": {"head": "Hood", "chest": "Robe", "legs": "Trousers", "hands": "Handwraps", "feet": "Slippers"},
}
## What each class starts with, worn: plain common items (1 point of their stat) that are what
## the hero is seen wearing, the weapon in the hand, the casters' robe, the warrior's plate. They
## are replaced as better ones drop. [slot, kind, name, stat]
## The armor pieces are the class's outfit: without them the hero is in the plain shirt, cloth
## trousers and shoes under it (Player._show_weapons, Humanoid.set_pick).
const STARTER := {
	"warrior": [["main", "greatsword", "Worn Greatsword", "damage"], ["head", "plate", "Dented Helm", "defense"],
		["chest", "plate", "Squire's Breastplate", "defense"], ["legs", "plate", "Squire's Legplates", "defense"],
		["hands", "plate", "Squire's Gauntlets", "defense"], ["feet", "plate", "Squire's Sabatons", "defense"]],
	"mage": [["main", "staff", "Apprentice's Staff", "magic"], ["chest", "cloth", "Apprentice's Robe", "resistance"],
		["legs", "cloth", "Apprentice's Trousers", "resistance"], ["hands", "cloth", "Apprentice's Handwraps", "resistance"],
		["feet", "cloth", "Apprentice's Slippers", "resistance"]],
	"rogue": [["main", "dagger", "Rusty Dagger", "damage"], ["off", "offdagger", "Old Parrying Dagger", "attack"],
		["chest", "leather", "Worn Leather Jerkin", "defense"], ["legs", "leather", "Worn Leather Breeches", "defense"],
		["hands", "leather", "Worn Leather Gloves", "defense"], ["feet", "leather", "Soft Leather Boots", "defense"]],
	"priest": [["main", "mace", "Initiate's Mace", "magic"], ["chest", "cloth", "Initiate's Robe", "resistance"],
		["legs", "cloth", "Initiate's Trousers", "resistance"], ["hands", "cloth", "Initiate's Handwraps", "resistance"],
		["feet", "cloth", "Initiate's Sandals", "resistance"]],
	"paladin": [["main", "mace", "Squire's Mace", "damage"], ["off", "shield", "Squire's Shield", "defense"],
		["chest", "mail", "Novice's Tabard", "defense"], ["legs", "mail", "Novice's Chausses", "defense"],
		["hands", "mail", "Novice's Gloves", "defense"], ["feet", "mail", "Novice's Boots", "defense"]],
	"warlock": [["main", "staff", "Acolyte's Staff", "magic"], ["chest", "cloth", "Acolyte's Robe", "resistance"],
		["legs", "cloth", "Acolyte's Trousers", "resistance"], ["hands", "cloth", "Acolyte's Handwraps", "resistance"],
		["feet", "cloth", "Acolyte's Slippers", "resistance"]],
	"hunter": [["main", "bow", "Hunting Bow", "damage"],
		["chest", "leather", "Ranger's Jerkin", "defense"], ["legs", "leather", "Ranger's Breeches", "defense"],
		["hands", "leather", "Ranger's Gloves", "defense"], ["feet", "leather", "Ranger's Boots", "defense"]],
	"shaman": [["main", "mace", "Tribal Mace", "damage"], ["off", "shield", "Hide Shield", "defense"],
		["chest", "leather", "Hide Vest", "defense"], ["legs", "leather", "Hide Breeches", "defense"],
		["hands", "leather", "Hide Gloves", "defense"], ["feet", "leather", "Hide Boots", "defense"]],
	"druid": [["main", "staff", "Grove Staff", "magic"], ["chest", "cloth", "Grove Robe", "resistance"],
		["legs", "cloth", "Grove Trousers", "resistance"], ["hands", "cloth", "Grove Handwraps", "resistance"],
		["feet", "cloth", "Grove Sandals", "resistance"]],
}


## The class's starting items: slot -> item.
static func starter_kit(cls: String) -> Dictionary:
	var out := {}
	for e: Array in STARTER.get(cls, []):
		var st := {e[3]: 1}
		if e[0] == "main":
			st = {"damage": weapon_damage_for(1, "common", e[1])}
			if e[3] == "magic":
				st["magic"] = 1
		out[e[0]] = {"name": e[2], "slot": e[0], "kind": e[1], "ilvl": 1, "rarity": "common", "stats": st}
	return out


static func two_handed(kind: String) -> bool:
	return int(WEAPONS.get(kind, {}).get("hands", 1)) == 2


## A weapon's Damage for its item level, rarity and kind (Rules: WEAPON_BASE, TWO_HANDED).
static func weapon_damage_for(ilvl: int, rarity: String, kind: String) -> int:
	var d := Rules.weapon_ref(ilvl) * float(RARITY[rarity].mod) * (Rules.TWO_HANDED if two_handed(kind) else 1.0)
	return maxi(1, roundi(d))


## The main-hand item's Damage (items from older saves have none: computed from it); 0 without one.
static func weapon_damage(item: Dictionary) -> int:
	if item.is_empty() or not WEAPONS.has(String(item.get("kind", ""))):
		return 0
	if item.get("stats", {}).has("damage"):
		return int(item.stats.damage)
	return weapon_damage_for(int(item.get("ilvl", 1)), String(item.get("rarity", "common")), String(item.kind))


## Materials by item level: 1-7, 8-15, 16+.
const MATERIALS := {
	"plate": ["Iron", "Steel", "Mithril"], "mail": ["Ringmail", "Chain", "Scale"],
	"leather": ["Hide", "Tanned", "Wyrmhide"], "cloth": ["Linen", "Wool", "Silk"],
	"weapon": ["Iron", "Steel", "Runed"], "wood": ["Ash", "Yew", "Heartwood"],
	"jewel": ["Copper", "Silver", "Gold"],
}

## Weapons: the classes that use them. Every weapon has Damage (weapon_damage_for, Rules
## WEAPON_*); caster weapons also Magic and some Mana. hands 2: two-handed (30% more damage, no
## off-hand). Off-hand kinds: shield (Defense), orb (Magic), dagger (Attack).
const WEAPONS := {
	"greatsword": {"classes": ["warrior", "paladin"], "stat": "attack", "noun": "Greatsword", "mat": "weapon", "hands": 2},
	"greataxe": {"classes": ["warrior", "shaman"], "stat": "attack", "noun": "Greataxe", "mat": "weapon", "hands": 2},
	"maul": {"classes": ["warrior", "paladin", "shaman"], "stat": "attack", "noun": "Maul", "mat": "weapon", "hands": 2},
	"sword": {"classes": ["warrior", "paladin", "rogue", "hunter"], "stat": "attack", "noun": "Sword", "mat": "weapon"},
	"axe": {"classes": ["warrior", "paladin", "hunter", "shaman"], "stat": "attack", "noun": "Axe", "mat": "weapon"},
	"mace": {"classes": ["warrior", "paladin", "priest", "shaman", "druid"], "stat": "attack", "noun": "Mace", "mat": "weapon"},
	"dagger": {"classes": ["rogue", "warrior", "hunter", "mage", "warlock", "priest", "druid"], "stat": "attack", "noun": "Dagger", "mat": "weapon"},
	"staff": {"classes": ["mage", "warlock", "priest", "druid", "shaman"], "stat": "magic", "noun": "Staff", "mat": "wood"},
	"bow": {"classes": ["hunter"], "stat": "attack", "noun": "Bow", "mat": "wood"},
}
const OFFHANDS := {
	"shield": {"classes": ["warrior", "paladin", "shaman"], "stat": "defense", "noun": "Shield", "mat": "weapon"},
	"orb": {"classes": ["mage", "warlock", "priest", "druid"], "stat": "magic", "noun": "Orb", "mat": "jewel"},
	"offdagger": {"classes": ["rogue"], "stat": "attack", "noun": "Parrying Dagger", "mat": "weapon"},
}
## Which main-hand kinds hit with Magic: casters' weapons put their budget into Magic.
const CASTERS := ["mage", "warlock", "priest", "druid"]

## Suffixes for uncommon and better items: the bonus stats (items.md section 5).
const SUFFIXES := {
	"of the Bear": ["attack", "hp"], "of the Owl": ["magic", "mana"], "of the Fox": ["crit", "attack"],
	"of the Turtle": ["defense", "resistance"], "of the Serpent": ["magic", "crit"],
	"of the Boar": ["attack", "defense"], "of the Wolf": ["attack", "crit"], "of Vigor": ["hp", "mana"],
}
const SUFFIX_FITS := {
	"warrior": ["of the Bear", "of the Boar", "of the Turtle", "of the Wolf"],
	"paladin": ["of the Bear", "of the Boar", "of the Turtle", "of Vigor"],
	"rogue": ["of the Fox", "of the Wolf", "of the Bear"],
	"hunter": ["of the Fox", "of the Wolf", "of the Boar"],
	"mage": ["of the Owl", "of the Serpent", "of Vigor"],
	"warlock": ["of the Serpent", "of the Owl", "of Vigor"],
	"priest": ["of the Owl", "of Vigor", "of the Turtle"],
	"shaman": ["of the Serpent", "of the Boar", "of Vigor"],
	"druid": ["of the Owl", "of the Bear", "of Vigor"],
}
## How many points of a stat one point of budget buys.
const STAT_SCALE := {"attack": 1.0, "defense": 1.0, "magic": 1.0, "resistance": 1.0, "hp": 9.0, "mana": 8.0, "crit": 0.6}
const STAT_NAMES := {"damage": "Damage", "attack": "Attack", "defense": "Defense", "magic": "Magic", "resistance": "Resistance",
	"hp": "Health", "mana": "Mana", "crit": "% Crit"}

const POTION := {"name": "Healing Potion", "slot": "potion", "kind": "potion", "ilvl": 1, "rarity": "common", "stats": {}, "count": 1}
const POTION_HEAL := 0.35      ## of max HP
const POTION_CD := 60.0


## Stat budget (items.md section 2), scaled so a full set adds about a third to the base stats.
static func budget(ilvl: int, slot: String, rarity: String) -> float:
	return (1.0 + 0.1 * (ilvl - 1)) * 1.25 * float(SLOT_MOD.get(slot, 0.5)) * float(RARITY[rarity].mod)


static func required_level(item: Dictionary) -> int:
	return maxi(1, int(item.get("ilvl", 1)) - 2)


static func roll_rarity(source: String, rng: RandomNumberGenerator) -> String:
	var odds: Array = ODDS.get(source, ODDS.trash)
	var r := rng.randi_range(1, 100)
	var names := ["common", "uncommon", "rare", "epic"]
	for i in 4:
		r -= int(odds[i])
		if r <= 0:
			return names[i]
	return "common"


## A random piece of gear. cls: the class it should fit (null-string: any class).
static func generate(ilvl: int, rarity: String, cls: String, rng: RandomNumberGenerator) -> Dictionary:
	var slot: String = SLOTS[rng.randi() % SLOTS.size()]
	return make(slot, ilvl, rarity, cls, rng)


static func make(slot: String, ilvl: int, rarity: String, cls: String, rng: RandomNumberGenerator) -> Dictionary:
	var b := budget(ilvl, slot, rarity)
	var tier := 0 if ilvl < 8 else (1 if ilvl < 16 else 2)
	var stats := {}
	var kind := ""
	var name := ""
	var bonus_share := 0.0 if rarity == "common" else 0.45
	var main_b := b * (1.0 - bonus_share)
	match slot:
		"main":
			var kinds := WEAPONS.keys().filter(func(k): return cls in WEAPONS[k].classes)
			if cls == "" or kinds.is_empty():
				kinds = WEAPONS.keys()
			kind = kinds[rng.randi() % kinds.size()]
			var w: Dictionary = WEAPONS[kind]
			# Weapons are worth more than armor: they carry most of the damage.
			var stat: String = "magic" if (cls in CASTERS and kind in ["staff", "dagger", "mace"]) else String(w.stat)
			# Damage on every weapon; caster weapons also their spell stat (the whole budget, the
			# suffix on top: a better rarity never lowers it). Physical weapons carry no Attack:
			# their Damage is what makes them hit harder.
			stats["damage"] = weapon_damage_for(ilvl, rarity, kind)
			if stat == "magic":
				_add(stats, "magic", b * 2.2)
				_add(stats, "mana", b * 0.6)
			name = "%s %s" % [MATERIALS[w.mat][tier], w.noun]
		"off":
			var kinds := OFFHANDS.keys().filter(func(k): return cls in OFFHANDS[k].classes)
			if cls == "" or kinds.is_empty():
				kinds = OFFHANDS.keys()
			kind = kinds[rng.randi() % kinds.size()]
			var o: Dictionary = OFFHANDS[kind]
			_add(stats, o.stat, b * 1.5)
			name = "%s %s" % [MATERIALS[o.mat][tier], o.noun]
		"neck", "ring":
			kind = "jewel"
			_add(stats, ["hp", "attack", "magic", "resistance"][rng.randi() % 4], main_b)
			name = "%s %s" % [MATERIALS.jewel[tier], "Pendant" if slot == "neck" else "Ring"]
		_:
			var armor: String = CLASS_ARMOR.get(cls, "") if cls != "" else ""
			if armor == "" or rng.randf() < 0.2:
				armor = ARMOR_RANK.keys()[rng.randi() % 4]
			kind = armor
			_add(stats, "defense", main_b * ARMOR_STATS[armor][0])
			_add(stats, "resistance", main_b * ARMOR_STATS[armor][1])
			name = "%s %s" % [MATERIALS[armor][tier], ARMOR_NOUNS[armor][slot]]
	if rarity != "common":
		var fits: Array = SUFFIX_FITS.get(cls, SUFFIXES.keys())
		var suffix: String = fits[rng.randi() % fits.size()] if rng.randf() < 0.75 else SUFFIXES.keys()[rng.randi() % SUFFIXES.size()]
		var pair: Array = SUFFIXES[suffix]
		var n := mini(int(RARITY[rarity].bonus), 2)
		for i in n:
			_add(stats, pair[i], b * bonus_share / n)
		if rarity == "epic":
			_add(stats, "crit", b * 0.3)
		name += " " + suffix
	return {"name": name, "slot": slot, "kind": kind, "ilvl": ilvl, "rarity": rarity, "stats": stats}


static func _add(stats: Dictionary, stat: String, points: float) -> void:
	var v := points * float(STAT_SCALE[stat])
	stats[stat] = int(stats.get(stat, 0)) + maxi(1, roundi(v))


## Can this class use the item? Returns "" or the reason.
static func problem(item: Dictionary, cls: String, level: int) -> String:
	if item.slot == "potion":
		return ""
	if level < required_level(item):
		return "Requires level %d" % required_level(item)
	var kind: String = item.kind
	if ARMOR_RANK.has(kind) and int(ARMOR_RANK[kind]) > int(ARMOR_RANK[CLASS_ARMOR[cls]]):
		return "%s can't wear %s" % [cls.capitalize(), kind]
	if item.slot == "main" and WEAPONS.has(kind) and not (cls in WEAPONS[kind].classes):
		return "%s can't use a %s" % [cls.capitalize(), kind]
	if item.slot == "off" and OFFHANDS.has(kind) and not (cls in OFFHANDS[kind].classes):
		return "%s can't use that" % cls.capitalize()
	return ""


## The sum of all equipped items' stats.
static func totals(equipped: Dictionary) -> Dictionary:
	var t := {}
	for slot in equipped:
		var it: Dictionary = equipped[slot]
		for k in it.get("stats", {}):
			t[k] = int(t.get(k, 0)) + int(it.stats[k])
	return t


static func sell_price(item: Dictionary) -> int:
	if item.slot == "potion":
		return 2
	return maxi(1, roundi(int(item.ilvl) * int(RARITY[item.rarity].price) * float(SLOT_MOD.get(item.slot, 0.5))))


static func buy_price(item: Dictionary, level: int) -> int:
	if item.slot == "potion":
		return 4 + 2 * level
	return sell_price(item) * 4


static func color(item: Dictionary) -> Color:
	return RARITY.get(item.get("rarity", "common"), RARITY.common).color


## Money as WoW coins: 100 bronze = 1 silver, 100 silver = 1 gold.
static func money_text(bronze: int) -> String:
	var g := bronze / 10000
	var s := (bronze / 100) % 100
	var b := bronze % 100
	var parts := []
	if g > 0:
		parts.append("%dg" % g)
	if g > 0 or s > 0:
		parts.append("%ds" % s)
	parts.append("%db" % b)
	return " ".join(parts)


## Tooltip text: name, slot and kind, stats, level requirement, price.
static func describe(item: Dictionary, cls: String, level: int) -> String:
	var lines := [item.name]
	if item.slot == "potion":
		lines.append("Restores %d%% health (cooldown %d s). Key R." % [roundi(POTION_HEAL * 100), roundi(POTION_CD)])
		lines.append("x%d" % int(item.get("count", 1)))
		return "\n".join(lines)
	lines.append("%s  %s%s  (item level %d)" % [SLOT_NAMES[item.slot], String(item.kind).replace("offdagger", "dagger").capitalize(), "  (two-handed)" if two_handed(item.kind) else "", int(item.ilvl)])
	if item.slot == "main" and not item.stats.has("damage") and WEAPONS.has(item.kind):
		lines.append("%d Damage" % weapon_damage(item))
	for k in STAT_NAMES:
		if k == "damage" and item.stats.has(k):
			lines.append("%d Damage" % int(item.stats[k]))
		elif item.stats.has(k):
			lines.append("+%d %s" % [int(item.stats[k]), STAT_NAMES[k]] if k != "crit" else "+%d%s" % [int(item.stats[k]), STAT_NAMES[k]])
	var p := problem(item, cls, level)
	if p != "":
		lines.append(p)
	lines.append("Sells for %s" % money_text(sell_price(item)))
	return "\n".join(lines)


## Stat changes if `item` replaced `current` (for the tooltip): "+3 Attack, -2 Defense".
static func compare(item: Dictionary, current: Dictionary) -> String:
	var parts := []
	for k in STAT_NAMES:
		var d := int(item.get("stats", {}).get(k, 0)) - int(current.get("stats", {}).get(k, 0))
		if d != 0:
			parts.append("%+d %s" % [d, STAT_NAMES[k]] if k != "crit" else "%+d%s" % [d, STAT_NAMES[k]])
	return ", ".join(parts) if not parts.is_empty() else "no change"

class_name EnemyData
extends RefCounted
## Grassland enemies (design/world.md, section 4.1). Level-1 values; health is Oldworld2's × 4.
## behavior: aggressive / normal / passive / defensive (design/mechanics.md, section 7).
## speed: m/s while chasing. model: "creature:<glb>" (uses <name>_rig.glb with its clips when built, else the static mesh moved procedurally) or
## "humanoid:<outfit>" (base body with a baked outfit and the shared animations).

const KINDS := {
	"wolf": {
		"name": "Wolf", "types": ["Physical"], "resistance": 8, "tier": "trash", "hp": 200, "attack": 8, "defense": 10,
		"behavior": "aggressive", "speed": 7.5, "swing": 2.0, "reach": 1.4, "radius": 0.5,
		"model": "creature:res://assets/creatures/wolf.glb", "group": Vector2i(2, 4),
		"abilities": ["howl"],
	},
	"boar": {
		"name": "Boar", "types": ["Physical", "Nature"], "resistance": 6, "tier": "trash", "hp": 240, "attack": 9, "defense": 12,
		"behavior": "defensive", "speed": 6.0, "swing": 2.4, "reach": 1.4, "radius": 0.5,
		"model": "creature:res://assets/creatures/boar.glb", "group": Vector2i(1, 2),
		"abilities": ["tusk_charge"],
	},
	"goblin": {
		"name": "Goblin", "types": ["Physical", "Dark"], "resistance": 7, "tier": "trash", "hp": 180, "attack": 9, "defense": 8,
		"behavior": "normal", "speed": 7.0, "swing": 2.0, "reach": 1.2, "radius": 0.35,
		"model": "humanoid:goblin", "scale": 0.7, "build": Vector3(1.4, 1.0, 1.3), "group": Vector2i(2, 3),
		# Stubby: short legs, a big head; ragged clothes with the green skin showing through.
		"legs": 0.7, "head_size": 1.3, "head_egg": 1.0, "ears": 0.24, "tatter": 0.5, "skin": Color(0.3, 0.44, 0.17),
		# The base face in the skin's green (the outfit's baked face was smeared), black hair; fur
		# hides instead of clothes, bare green hands.
		"head_tint": Color(0.44, 0.7, 0.3), "fur": 1.0, "fur_color": Color(0.48, 0.34, 0.2), "skin_hands": true,
		"abilities": ["sling_stone"], "weapon": "club",
	},
	"bear": {
		"name": "Brown Bear", "types": ["Physical", "Nature"], "resistance": 7, "tier": "trash", "hp": 320, "attack": 11, "defense": 12,
		"behavior": "defensive", "speed": 6.5, "swing": 2.6, "reach": 1.7, "radius": 0.8,
		"model": "creature:res://assets/creatures/bear.glb", "fallback": "res://assets/creatures/boar.glb",
		"group": Vector2i(1, 1), "abilities": ["savage_bite"],
	},
	"spider": {
		"name": "Giant Spider", "types": ["Physical", "Nature"], "resistance": 7, "tier": "trash", "hp": 170, "attack": 9, "defense": 9,
		"behavior": "aggressive", "speed": 7.0, "swing": 1.8, "reach": 1.4, "radius": 0.6,
		"model": "creature:res://assets/creatures/spider.glb", "fallback": "res://assets/creatures/scorpion.glb",
		"group": Vector2i(1, 3), "abilities": ["venom_bite", "web"],
	},
	"bandit": {
		"name": "Bandit", "types": ["Physical", "Dark"], "resistance": 8, "tier": "elite", "hp": 320, "attack": 13, "defense": 9,
		"behavior": "normal", "speed": 6.0, "swing": 1.8, "reach": 1.3, "radius": 0.35,
		"model": "humanoid:bandit", "scale": 1.0, "group": Vector2i(2, 3), "crit": 0.2,
		"abilities": ["poisoned_blade", "smoke_screen"], "weapon": "dagger",
	},
}

# The North (design/world.md, Oldworld2's north enemies; health × 4).
const NORTH := {
	"snow_wolf": {
		"name": "Snow Wolf", "types": ["Ice"], "resistance": 9, "tier": "trash", "hp": 200, "attack": 9, "defense": 9,
		"behavior": "aggressive", "speed": 7.5, "swing": 2.0, "reach": 1.4, "radius": 0.5,
		"model": "creature:res://assets/creatures/snowwolf.glb", "fallback": "res://assets/creatures/wolf.glb",
		"group": Vector2i(2, 3), "abilities": ["howl"],
	},
	"frost_wisp": {"dodge": 0.0, 
		"name": "Frost Wisp", "types": ["Ice"], "resistance": 11, "tier": "trash", "hp": 160, "attack": 4, "magic": 11,
		"defense": 7, "behavior": "passive", "speed": 6.0, "swing": 2.4, "reach": 1.2, "radius": 0.45,
		"model": "creature:res://assets/creatures/wisp.glb", "fallback": "res://assets/creatures/wolf.glb",
		"group": Vector2i(1, 2), "abilities": [], "ranged": 14.0, "element": "Ice", "float": 1.4,
	},
	"ice_troll": {"dodge": 0.0, 
		"name": "Ice Troll", "types": ["Physical", "Ice"], "resistance": 6, "tier": "trash", "hp": 300, "attack": 12, "defense": 13,
		"behavior": "normal", "speed": 4.5, "swing": 2.8, "reach": 1.8, "radius": 0.6,
		"model": "humanoid:troll", "scale": 1.35, "group": Vector2i(1, 2), "abilities": ["troll_smash"], "weapon": "club",
		"tint": Color(0.6, 0.75, 0.95),
	},
	"berserker": {
		"name": "Berserker", "types": ["Physical", "Ice"], "resistance": 8, "tier": "elite", "hp": 360, "attack": 15, "defense": 8,
		"behavior": "normal", "speed": 6.5, "swing": 2.2, "reach": 1.4, "radius": 0.4,
		"model": "humanoid:berserker", "scale": 1.05, "group": Vector2i(2, 3), "abilities": ["berserk", "cleave"],
		"weapon": "club", "crit": 0.1, "tint": Color(0.85, 0.7, 0.6),
	},
}


# The Desert (design/world.md, Oldworld2's desert enemies; health × 4).
const DESERT := {
	"sand_snake": {
		"name": "Sand Snake", "types": ["Nature"], "resistance": 8, "tier": "trash", "hp": 180, "attack": 9, "defense": 9,
		"behavior": "normal", "speed": 7.0, "swing": 1.8, "reach": 1.3, "radius": 0.45,
		"model": "creature:res://assets/creatures/sandsnake.glb", "fallback": "res://assets/creatures/boar.glb",
		"group": Vector2i(1, 2), "abilities": ["venom_bite"],
	},
	"scorpion": {
		"name": "Scorpion", "types": ["Physical", "Nature"], "resistance": 6, "tier": "trash", "hp": 220, "attack": 10, "defense": 13,
		"behavior": "defensive", "speed": 6.0, "swing": 2.2, "reach": 1.5, "radius": 0.6,
		"model": "creature:res://assets/creatures/scorpion.glb", "fallback": "res://assets/creatures/boar.glb",
		"group": Vector2i(1, 2), "abilities": ["venom_bite"],
	},
	"ember_spirit": {"dodge": 0.0, 
		"name": "Ember Spirit", "types": ["Fire"], "resistance": 11, "tier": "trash", "hp": 160, "attack": 4, "magic": 11,
		"defense": 7, "behavior": "passive", "speed": 6.0, "swing": 2.4, "reach": 1.2, "radius": 0.45,
		"model": "creature:res://assets/creatures/ember.glb", "fallback": "res://assets/creatures/wisp.glb",
		"group": Vector2i(1, 2), "abilities": [], "ranged": 14.0, "element": "Fire", "float": 1.4,
	},
	"nomad": {
		"name": "Nomad Raider", "types": ["Physical", "Fire"], "resistance": 8, "tier": "elite", "hp": 340, "attack": 14, "defense": 10,
		"behavior": "normal", "speed": 6.5, "swing": 1.9, "reach": 1.3, "radius": 0.4,
		"model": "humanoid:nomad", "scale": 1.0, "group": Vector2i(2, 3), "abilities": ["fire_brand", "smoke_screen"],
		"weapon": "club", "crit": 0.1, "tint": Color(0.9, 0.8, 0.65),
	},
}


# The Ancient Desert (Oldworld2's ancient desert enemies; health × 4).
const ANCIENT := {
	"scarab": {
		"name": "Scarab", "types": ["Physical", "Nature"], "resistance": 7, "tier": "trash", "hp": 160, "attack": 9, "defense": 12,
		"behavior": "aggressive", "speed": 7.5, "swing": 1.6, "reach": 1.2, "radius": 0.5,
		"model": "creature:res://assets/creatures/scarab.glb", "fallback": "res://assets/creatures/scorpion.glb",
		"group": Vector2i(2, 3), "abilities": ["hard_shell"],
	},
	"cobra": {
		"name": "Cobra", "types": ["Nature"], "resistance": 9, "tier": "trash", "hp": 180, "attack": 9, "magic": 9, "defense": 8,
		"behavior": "normal", "speed": 6.5, "swing": 2.2, "reach": 1.4, "radius": 0.45,
		"model": "creature:res://assets/creatures/cobra.glb", "fallback": "res://assets/creatures/sandsnake.glb",
		"group": Vector2i(1, 2), "abilities": ["venom_bite"], "ranged": 12.0, "element": "Nature",
	},
	"mummy": {"dodge": 0.0, 
		"name": "Mummy", "types": ["Physical", "Dark"], "resistance": 6, "tier": "trash", "hp": 240, "attack": 10, "magic": 8, "defense": 12,
		"behavior": "normal", "speed": 4.2, "swing": 2.4, "reach": 1.3, "radius": 0.4,
		"model": "humanoid:mummy", "scale": 1.0, "group": Vector2i(1, 3), "abilities": ["wrap", "ancient_curse"],
		"tint": Color(0.85, 0.78, 0.6),
	},
	"tomb_guardian": {"dodge": 0.0, 
		"name": "Tomb Guardian", "types": ["Physical", "Holy"], "resistance": 10, "tier": "elite", "hp": 380, "attack": 14, "magic": 10, "defense": 14,
		"behavior": "normal", "speed": 5.5, "swing": 2.2, "reach": 1.4, "radius": 0.45,
		"model": "humanoid:guardian", "scale": 1.1, "group": Vector2i(1, 2), "abilities": ["sun_strike", "sacred_ward"],
		"weapon": "mace", "shield": true, "tint": Color(0.75, 0.55, 0.35),
	},
}


# The Mediterranean and the Unholy lands (Oldworld2's enemies; health × 4).
const WEST_EAST := {
	"crab": {
		"name": "Giant Crab", "types": ["Water", "Physical"], "resistance": 6, "tier": "trash", "hp": 240, "attack": 10, "defense": 15,
		"behavior": "defensive", "speed": 5.5, "swing": 2.4, "reach": 1.5, "radius": 0.6,
		"model": "creature:res://assets/creatures/crab.glb", "fallback": "res://assets/creatures/scorpion.glb",
		"group": Vector2i(1, 2), "abilities": ["hard_shell"],
	},
	"wind_spirit": {"dodge": 0.0, 
		"name": "Wind Spirit", "types": ["Air"], "resistance": 10, "tier": "trash", "hp": 160, "attack": 4, "magic": 11,
		"defense": 7, "behavior": "passive", "speed": 7.5, "swing": 2.2, "reach": 1.2, "radius": 0.45,
		"model": "creature:res://assets/creatures/windspirit.glb", "fallback": "res://assets/creatures/wisp.glb",
		"group": Vector2i(1, 2), "abilities": [], "ranged": 14.0, "element": "Air", "float": 1.5,
	},
	"corsair": {
		"name": "Corsair", "types": ["Physical", "Water"], "resistance": 8, "tier": "elite", "hp": 340, "attack": 14, "defense": 9,
		"behavior": "normal", "speed": 6.5, "swing": 1.9, "reach": 1.3, "radius": 0.4,
		"model": "humanoid:corsair", "scale": 1.0, "group": Vector2i(2, 3), "abilities": ["pistol_shot", "smoke_screen"],
		"weapon": "club", "crit": 0.1,
	},
	"hoplite": {
		"name": "Hoplite", "types": ["Physical", "Holy"], "resistance": 9, "tier": "elite", "hp": 380, "attack": 13, "defense": 15,
		"behavior": "normal", "speed": 5.5, "swing": 2.2, "reach": 1.6, "radius": 0.4,
		"model": "humanoid:hoplite", "scale": 1.0, "group": Vector2i(2, 3), "abilities": ["shield_wall", "cleave"],
		"weapon": "club", "shield": true,
	},
	"dire_wolf": {
		"name": "Dire Wolf", "types": ["Dark", "Physical"], "resistance": 8, "tier": "trash", "hp": 232, "attack": 10, "defense": 10,
		"behavior": "aggressive", "speed": 7.5, "swing": 2.0, "reach": 1.5, "radius": 0.55,
		"model": "creature:res://assets/creatures/direwolf.glb", "fallback": "res://assets/creatures/wolf.glb",
		"group": Vector2i(2, 3), "abilities": ["howl", "savage_bite"],
	},
	"bat_swarm": {
		"name": "Bat Swarm", "types": ["Dark"], "resistance": 8, "tier": "trash", "hp": 160, "attack": 9, "defense": 7,
		"behavior": "aggressive", "speed": 8.0, "swing": 1.6, "reach": 1.3, "radius": 0.5,
		"model": "creature:res://assets/creatures/bats.glb", "fallback": "res://assets/creatures/wisp.glb",
		"group": Vector2i(1, 2), "abilities": [], "float": 1.8, "flying": true,
	},
	"cultist": {
		"name": "Cultist", "types": ["Dark", "Fire"], "resistance": 11, "tier": "elite", "hp": 320, "attack": 8, "magic": 14,
		"defense": 8, "behavior": "normal", "speed": 6.0, "swing": 2.2, "reach": 1.2, "radius": 0.4,
		"model": "humanoid:cultist", "scale": 1.0, "group": Vector2i(2, 3), "abilities": ["dark_pact"], "ranged": 14.0,
		"element": "Dark", "weapon": "dagger",
	},
	"vampire": {
		"name": "Vampire", "types": ["Dark"], "resistance": 11, "tier": "elite", "hp": 400, "attack": 14, "magic": 12,
		"defense": 10, "behavior": "normal", "speed": 7.0, "swing": 1.8, "reach": 1.3, "radius": 0.4,
		"model": "humanoid:vampire", "scale": 1.05, "group": Vector2i(1, 1), "abilities": ["life_drain", "mesmerize"],
	},
}


static func get_kind(kind: String) -> Dictionary:
	for d in [KINDS, NORTH, DESERT, ANCIENT, WEST_EAST]:
		if d.has(kind):
			return d[kind]
	return KINDS.wolf


const AGGRO := {"aggressive": 20.0, "normal": 12.0, "passive": 6.0, "defensive": 0.0}

class_name Player
extends CharacterBody3D
## The hero: WoW Classic style movement, camera and combat (design/game-design.md, section 5;
## design/mechanics.md; design/classes.md for the Warrior).
##   W/S forward/back, A/D turn (strafe while the right mouse button is held), Q/E strafe,
##   Space jump, Shift sprint, left drag orbit camera, right drag orbit + turn hero,
##   both buttons run forward, wheel zoom. Tab target, click target, right-click attack,
##   F auto-attack, 1–6 abilities.

signal leveled_up(level: int)
signal level_banner(level: int, learned: Array)   ## new abilities and passives as text lines
signal message(text: String)
signal death_banner(lines: Array)   ## after waking up: what the death cost
signal saved_point                  ## something worth an autosave happened (checkpoint, death)
signal loadout_changed              ## the action bar's abilities changed (abilities menu)

const RUN_SPEED := 7.0
const SPRINT_FACTOR := 1.5          ## sprint = 10.5 m/s (from Oldworld2: sprint on Shift)
const DAZE_TIME := 4.0              ## s of half speed after being dazed (hit from behind)
const STAMINA_TIME := 10.0          ## seconds of sprinting on a full bar
const STAMINA_REFILL := 20.0        ## seconds to refill while moving; twice as fast standing still
const BACK_FACTOR := 0.5
const TURN_SPEED := deg_to_rad(180.0)
const JUMP_VELOCITY := 6.5
const GRAVITY := 20.0
const MOUSE_SENS := 0.004
const ZOOM_MIN := 2.0
const ZOOM_MAX := 15.0
const MELEE_RANGE := 2.6            ## plus the target's radius
const GCD := 1.5
const SWING := 2.6                  ## two-handed sword swing time

## Warrior abilities (design/classes.md, section 2.2). key: action bar slot (1-based).
const ABILITIES_WARRIOR := [
	{"id": "heavy_strike", "name": "Heavy Strike", "key": 1, "level": 1, "rage": 15, "cd": 0.0, "power": 50.0},
	{"id": "battle_cry", "name": "Battle Cry", "key": 2, "level": 1, "rage": 0, "cd": 120.0, "gain": 10},
	{"id": "overwhelm", "name": "Overwhelm", "key": 3, "level": 2, "rage": 5, "cd": 0.0, "power": 100.0},
	{"id": "thunder_clap", "name": "Thunder Clap", "key": 4, "level": 4, "rage": 20, "cd": 6.0, "power": 25.0},
	{"id": "charge", "name": "Charge", "key": 5, "level": 6, "rage": 0, "cd": 15.0, "gain": 15},
	{"id": "rend", "name": "Rend", "key": 6, "level": 2, "rage": 10, "cd": 0.0},
	{"id": "whirlwind", "name": "Whirlwind", "key": 7, "level": 12, "rage": 10, "cd": 60.0, "power": 40.0},
]
## Whirlwind: spins while rage lasts (WHIRL_RAGE per second, the first second paid on use),
## hitting every enemy within WHIRL_RADIUS once a second; the model turns WHIRL_SPIN times a second.
const WHIRL_RAGE := 10.0
const WHIRL_RADIUS := 4.0
const WHIRL_KILL_CD := 5.0          ## s off Whirlwind's cooldown per kill by it
const WHIRL_SPIN := 3.4

## Mage spells (design/classes.md; Oldworld2's Mage in real time). cast: seconds (0 = instant),
## mana: cost, range: meters, element: for the element chart and the Mage's affinities.
const ABILITIES_MAGE := [
	{"id": "fire_bolt", "name": "Fire Bolt", "key": 1, "level": 1, "mana": 0, "cd": 0.0, "cast": 1.6, "power": 40.0, "element": "Fire", "range": 30.0},
	{"id": "ice_bolt", "name": "Ice Bolt", "key": 2, "level": 1, "mana": 24, "cd": 0.0, "cast": 2.0, "power": 55.0, "element": "Ice", "range": 30.0},
	{"id": "frost_ring", "name": "Frost Ring", "key": 3, "level": 2, "mana": 30, "cd": 20.0, "cast": 0.0, "power": 45.0, "element": "Ice", "range": 0.0},
	{"id": "mana_shield", "name": "Mana Shield", "key": 4, "level": 3, "mana": 30, "cd": 30.0, "cast": 0.0},
	{"id": "ignite", "name": "Ignite", "key": 5, "level": 4, "mana": 24, "cd": 0.0, "cast": 0.0, "element": "Fire", "range": 30.0},
	{"id": "blink", "name": "Blink", "key": 6, "level": 6, "mana": 15, "cd": 15.0, "cast": 0.0},
	{"id": "fireball", "name": "Fireball", "key": 8, "level": 10, "mana": 25, "cd": 0.0, "cast": 2.0, "power": 60.0, "element": "Fire", "range": 30.0},
	{"id": "blizzard", "name": "Blizzard", "key": 7, "level": 8, "mana": 45, "cd": 0.0, "channel": 6.0, "tick": 1.0, "power": 22.0, "element": "Ice", "range": 30.0},
]
## Blizzard: channelled over a circle of BLIZZARD_RADIUS m at the target (fixed when it starts).
const BLIZZARD_RADIUS := 8.0

## Rogue abilities (Oldworld2's Rogue in real time). energy: cost.
const ABILITIES_ROGUE := [
	{"id": "quick_stab", "name": "Quick Stab", "key": 1, "level": 1, "energy": 40, "cd": 0.0, "power": 45.0},
	{"id": "stealth", "name": "Stealth", "key": 2, "level": 1, "energy": 0, "cd": 6.0},
	{"id": "knife_throw", "name": "Knife Throw", "key": 3, "level": 2, "energy": 20, "cd": 0.0, "power": 45.0, "range": 25.0, "element": "Physical"},
	{"id": "poisoned_blade", "name": "Poisoned Blade", "key": 4, "level": 3, "energy": 30, "cd": 0.0, "power": 20.0},
	{"id": "cheap_shot", "name": "Cheap Shot", "key": 5, "level": 6, "energy": 40, "cd": 20.0, "power": 10.0},
	{"id": "gut_slash", "name": "Gut Slash", "key": 6, "level": 8, "energy": 30, "cd": 0.0, "power": 75.0},
]

## Priest (Oldworld2's Priest in real time): Holy damage, heals, a shield, Dark damage over time.
## self: no target needed.
const ABILITIES_PRIEST := [
	{"id": "smite", "name": "Smite", "key": 1, "level": 1, "mana": 0, "cd": 0.0, "cast": 1.8, "power": 45.0, "element": "Holy", "range": 30.0},
	{"id": "mend", "name": "Mend", "key": 2, "level": 1, "mana": 30, "cd": 0.0, "cast": 1.5, "heal": 0.25, "self": true},
	{"id": "holy_burst", "name": "Holy Burst", "key": 3, "level": 2, "mana": 30, "cd": 10.0, "cast": 0.0, "power": 45.0, "element": "Holy", "self": true},
	{"id": "ward_of_light", "name": "Ward of Light", "key": 4, "level": 3, "mana": 30, "cd": 15.0, "cast": 0.0, "self": true},
	{"id": "renewal", "name": "Renewal", "key": 5, "level": 4, "mana": 25, "cd": 0.0, "cast": 0.0, "self": true},
	{"id": "mind_pain", "name": "Mind Pain", "key": 6, "level": 6, "mana": 20, "cd": 0.0, "cast": 0.0, "element": "Dark", "range": 30.0},
]

## Paladin: holy melee with mana, a stun, defense and heals.
const ABILITIES_PALADIN := [
	{"id": "righteous_strike", "name": "Righteous Strike", "key": 1, "level": 1, "mana": 20, "cd": 0.0, "power": 50.0, "element": "Holy"},
	{"id": "holy_seal", "name": "Holy Seal", "key": 2, "level": 1, "mana": 20, "cd": 30.0, "self": true},
	{"id": "judgment_hammer", "name": "Judgment Hammer", "key": 3, "level": 2, "mana": 25, "cd": 20.0, "power": 30.0, "element": "Holy"},
	{"id": "devotion", "name": "Devotion", "key": 4, "level": 4, "mana": 20, "cd": 60.0, "self": true},
	{"id": "healing_light", "name": "Healing Light", "key": 5, "level": 6, "mana": 35, "cd": 0.0, "cast": 2.0, "heal": 0.3, "self": true},
	{"id": "divine_shield", "name": "Divine Shield", "key": 6, "level": 8, "mana": 30, "cd": 120.0, "self": true},
]

## Warlock: the strongest damage over time and life drain (Oldworld2).
const ABILITIES_WARLOCK := [
	{"id": "hex_bolt", "name": "Hex Bolt", "key": 1, "level": 1, "mana": 0, "cd": 0.0, "cast": 1.6, "power": 40.0, "element": "Dark", "range": 30.0},
	{"id": "drain_life", "name": "Drain Life", "key": 2, "level": 1, "mana": 30, "cd": 0.0, "cast": 0.0, "element": "Dark", "range": 30.0},
	{"id": "wither", "name": "Wither", "key": 3, "level": 1, "mana": 20, "cd": 0.0, "cast": 0.0, "element": "Dark", "range": 30.0},
	{"id": "hellfire_rain", "name": "Hellfire Rain", "key": 4, "level": 2, "mana": 30, "cd": 8.0, "cast": 2.0, "power": 45.0, "element": "Fire", "range": 30.0},
	{"id": "curse_of_weakness", "name": "Curse of Weakness", "key": 5, "level": 3, "mana": 20, "cd": 0.0, "cast": 0.0, "range": 30.0},
	{"id": "dread", "name": "Dread", "key": 6, "level": 6, "mana": 25, "cd": 20.0, "cast": 0.0, "range": 30.0},
]

## Hunter: a bow with an automatic ranged shot (5–30 m), shots and traps-like debuffs.
const ABILITIES_HUNTER := [
	{"id": "steady_shot", "name": "Steady Shot", "key": 1, "level": 1, "mana": 20, "cd": 0.0, "power": 50.0, "range": 30.0, "element": "Physical"},
	{"id": "venom_arrow", "name": "Venom Arrow", "key": 2, "level": 1, "mana": 20, "cd": 0.0, "power": 25.0, "range": 30.0, "element": "Nature"},
	{"id": "mark_prey", "name": "Mark Prey", "key": 3, "level": 2, "mana": 20, "cd": 0.0, "range": 30.0},
	{"id": "volley", "name": "Volley", "key": 4, "level": 6, "mana": 30, "cd": 10.0, "power": 45.0, "range": 30.0, "element": "Nature"},
	{"id": "first_aid", "name": "First Aid", "key": 5, "level": 8, "mana": 30, "cd": 30.0, "cast": 2.0, "heal": 0.3, "self": true},
]

## Shaman: elemental shocks, chain lightning, healing; totems in combat (level 4).
const ABILITIES_SHAMAN := [
	{"id": "storm_bolt", "name": "Storm Bolt", "key": 1, "level": 1, "mana": 0, "cd": 0.0, "cast": 1.6, "power": 45.0, "element": "Air", "range": 30.0},
	{"id": "flame_shock", "name": "Flame Shock", "key": 2, "level": 1, "mana": 20, "cd": 0.0, "power": 25.0, "element": "Fire", "range": 25.0},
	{"id": "chain_lightning", "name": "Chain Lightning", "key": 3, "level": 2, "mana": 30, "cd": 8.0, "cast": 2.0, "power": 45.0, "element": "Air", "range": 30.0},
	{"id": "healing_wave", "name": "Healing Wave", "key": 4, "level": 3, "mana": 30, "cd": 0.0, "cast": 2.0, "heal": 0.25, "self": true},
	{"id": "stone_shock", "name": "Stone Shock", "key": 5, "level": 4, "mana": 25, "cd": 12.0, "power": 40.0, "element": "Nature", "range": 25.0},
	{"id": "frost_shock", "name": "Frost Shock", "key": 6, "level": 6, "mana": 25, "cd": 8.0, "power": 45.0, "element": "Ice", "range": 25.0},
]

## Druid: nature spells, healing over time, roots, and Bear Form (level 6).
const ABILITIES_DRUID := [
	{"id": "thorn_lash", "name": "Thorn Lash", "key": 1, "level": 1, "mana": 0, "cd": 0.0, "cast": 1.6, "power": 50.0, "element": "Nature", "range": 30.0},
	{"id": "rejuvenate", "name": "Rejuvenate", "key": 2, "level": 1, "mana": 25, "cd": 0.0, "self": true},
	{"id": "insect_swarm", "name": "Insect Swarm", "key": 3, "level": 2, "mana": 30, "cd": 0.0, "range": 30.0, "element": "Nature"},
	{"id": "grasping_roots", "name": "Grasping Roots", "key": 4, "level": 3, "mana": 20, "cd": 12.0, "power": 30.0, "range": 30.0, "element": "Nature"},
	{"id": "moonbeam", "name": "Moonbeam", "key": 5, "level": 4, "mana": 25, "cd": 0.0, "cast": 2.0, "power": 55.0, "element": "Holy", "range": 30.0},
	{"id": "bear_form", "name": "Bear Form", "key": 6, "level": 6, "mana": 30, "cd": 10.0, "self": true},
]

## Per class: base stats at level 1 (health × 4, design/mechanics.md), look and weapon.
const CLASSES := {
	"warrior": {"name": "Warrior", "desc": "Tough melee fighter who recovers fast.", "base": {"hp": 480.0, "attack": 14.0, "defense": 13.0, "magic": 4.0, "resistance": 8.0},
		"outfit": "res://assets/characters/warrior/plate", "pick": [0, 1, 1, 1, 1], "helmet": true,
		"weapon": "res://assets/characters/warrior/sword.glb", "swing": 2.6, "affinities": ["Physical"]},
	"mage": {"name": "Mage", "desc": "Fragile caster of ice, water and fire.", "base": {"hp": 340.0, "attack": 4.0, "defense": 7.0, "magic": 16.0, "resistance": 12.0, "mana": 300.0},
		"outfit": "res://assets/characters/mage/mage", "pick": [1, 1, 1, 1, 1], "helmet": false,
		"weapon": "res://assets/weapons/staff.glb", "weapon_rot": Vector3.ZERO, "swing": 2.8,
		"affinities": ["Ice", "Water", "Fire"]},
	"rogue": {"name": "Rogue", "desc": "Fast striker with poisons and smoke.", "base": {"hp": 380.0, "attack": 14.0, "defense": 9.0, "magic": 5.0, "resistance": 8.0},
		"outfit": "res://assets/characters/rogue/rogue", "pick": [1, 1, 1, 1, 1], "helmet": false,
		"weapon": "res://assets/weapons/dagger.glb", "offhand": "res://assets/weapons/dagger.glb", "swing": 1.8,
		"affinities": ["Physical", "Dark"], "crit": 0.12},
	"priest": {"name": "Priest", "desc": "Holy caster who heals and shields.", "base": {"hp": 380.0, "attack": 4.0, "defense": 8.0, "magic": 13.0, "resistance": 13.0, "mana": 300.0},
		"outfit": "res://assets/characters/priest/priest", "pick": [1, 1, 1, 1, 1], "helmet": false,
		"weapon": "res://assets/weapons/mace.glb", "swing": 2.4, "affinities": ["Holy"]},
	"paladin": {"name": "Paladin", "desc": "Holy knight: the toughest defense.", "base": {"hp": 460.0, "attack": 11.0, "defense": 15.0, "magic": 8.0, "resistance": 11.0, "mana": 300.0},
		"outfit": "res://assets/characters/paladin/paladin", "pick": [1, 1, 1, 1, 1], "helmet": false,
		"weapon": "res://assets/weapons/mace.glb", "shield": "res://assets/weapons/shield.glb", "swing": 2.4,
		"affinities": ["Physical", "Holy"]},
	"warlock": {"name": "Warlock", "desc": "Dark caster: curses, drains and decay.", "base": {"hp": 380.0, "attack": 4.0, "defense": 8.0, "magic": 14.0, "resistance": 11.0, "mana": 300.0},
		"outfit": "res://assets/characters/warlock/warlock", "pick": [1, 1, 1, 1, 1], "helmet": false,
		"weapon": "res://assets/weapons/staff_warlock.glb", "weapon_rot": Vector3.ZERO, "swing": 2.8, "affinities": ["Dark"]},
	"hunter": {"name": "Hunter", "desc": "Archer who wears enemies down from afar.", "base": {"hp": 400.0, "attack": 13.0, "defense": 10.0, "magic": 6.0, "resistance": 9.0, "mana": 300.0},
		"outfit": "res://assets/characters/hunter/hunter", "pick": [1, 1, 1, 1, 1], "helmet": false,
		"bow": "res://assets/weapons/bow.glb", "swing": 2.4, "affinities": ["Physical", "Nature"]},
	"shaman": {"name": "Shaman", "desc": "Caller of storm, flame and water.", "base": {"hp": 420.0, "attack": 9.0, "defense": 9.0, "magic": 9.0, "resistance": 10.0, "mana": 300.0},
		"outfit": "res://assets/characters/shaman/shaman", "pick": [1, 1, 1, 1, 1], "helmet": false,
		"weapon": "res://assets/weapons/mace.glb", "shield": "res://assets/weapons/shield.glb", "swing": 2.4,
		"affinities": ["Air", "Fire", "Water"]},
	"druid": {"name": "Druid", "desc": "Nature caster: thorns, regrowth, bear form.", "base": {"hp": 400.0, "attack": 9.0, "defense": 10.0, "magic": 13.0, "resistance": 11.0, "mana": 300.0},
		"outfit": "res://assets/characters/druid/druid", "pick": [1, 1, 1, 1, 1], "helmet": false,
		"weapon": "res://assets/weapons/staff.glb", "weapon_rot": Vector3.ZERO, "swing": 2.8, "affinities": ["Nature"]},
}

const CASTERS := ["mage", "priest", "warlock", "shaman", "druid"]

var auto_forward := false           ## for scripted test runs
var auto_sprint := false            ## for scripted test runs
var stamina := 1.0                  ## 0..1
var sprinting := false
var cam_yaw := 0.0                  ## camera yaw relative to the hero
var cam_pitch := deg_to_rad(-18.0)
var zoom := 6.0

var cls := "warrior"
var stats: Combatant
var casting := {}                  ## {a, end, start, target} while a spell is being cast
var stealthed := false             ## rogue: enemies barely notice the hero; the next hit +50%
var bear := false                  ## druid in Bear Form
var _bear_model: Node3D
var _bear_phase := 0.0
var _totems: Array[Node3D] = []
var _totem_until := 0.0
var xp := 0
var money := 0                      ## in bronze (Items.money_text)
var bag: Array = []                 ## items (Dictionaries, see Items), at most Items.BAG_SIZE
var equipped := {}                  ## slot -> item
var potion_ready := 0.0
var merchant_until := 0.0           ## near an inn's merchant until then (Settlement sets it)
var quests := Quests.new()
var opened_chests := {}           ## chest key -> true (saved)
var visited := {}                  ## "x,z" -> true for every zone the hero has entered (world map)
var target: Enemy
var auto_attacking := false
var checkpoint := Vector3.ZERO
var cooldowns := {}                 ## ability id -> ready time
var gcd_until := 0.0
var overwhelm_until := 0.0          ## Overwhelm is usable until then (after a miss)
var camera: Camera3D
var model: Humanoid

var _lmb := false
var _rmb := false
var _press_pos := Vector2.ZERO
var _drag := 0.0
var _pivot: Node3D
var _pitch: Node3D
var _arm: SpringArm3D
var _swing_at := 0.0
var _charge_until := 0.0
var _charge_target: Enemy
var _knock := Vector3.ZERO
var _ring: MeshInstance3D
var _dead_at := -1.0
var _next_attack := "attack1"
var whirling := false
var _whirl_tick := 0.0              ## when Whirlwind hits next
var _whirl_fx: WhirlFx
var _spin := 0.0                    ## the model's Whirlwind turn so far (radians, unwrapped)
var _unwinding := false             ## Whirlwind over: the model finishes its turn to the front
var _jugg_t := 0.0                  ## Juggernaut: rage gained so far this second (fraction)


func _ready() -> void:
	BlobShadow.attach(self, 0.55)
	collision_layer = 4      # the hero; nothing collides with it, enemies walk through
	collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	floor_max_angle = deg_to_rad(45.0)
	floor_snap_length = 0.4

	var c: Dictionary = CLASSES[cls]
	stats = Combatant.new()
	stats.name = "Stats"
	stats.display_name = c.name
	stats.tier = "player"
	stats.uses_rage = cls == "warrior"
	stats.uses_mana = cls in ["mage", "priest", "paladin", "warlock", "hunter", "shaman", "druid"]
	stats.uses_energy = cls == "rogue"
	stats.base_crit = float(c.get("crit", 0.05))
	stats.crit_chance = stats.base_crit
	stats.regen_mult = 2.0 if cls == "warrior" else 1.0
	stats.swing_time = c.swing
	stats.affinities = c.affinities
	reset_loadout()
	stats.setup(1, c.base)
	stats.body = self
	add_child(stats)
	stats.damaged.connect(_on_damaged)
	stats.attacked.connect(_on_attacked)
	stats.died.connect(_on_died)
	if cls == "warrior":
		_whirl_fx = WhirlFx.new()
		add_child(_whirl_fx)

	model = Humanoid.new()
	model.name = "Model"
	add_child(model)
	model.build(look_of(cls))

	_pivot = Node3D.new()
	_pivot.position.y = 1.6
	add_child(_pivot)
	_pivot.top_level = true
	_pitch = Node3D.new()
	_pivot.add_child(_pitch)
	_arm = SpringArm3D.new()
	_arm.spring_length = zoom
	_arm.margin = 0.1
	# A sphere, not a ray: the camera keeps 0.4 m from the ground and walls in every direction
	# (low over the ground, the ray let it sink until the view clipped into the terrain).
	var cam_ball := SphereShape3D.new()
	cam_ball.radius = 0.4
	_arm.shape = cam_ball
	_arm.collision_mask = 1 | 8      # terrain, buildings, trunks and tree canopies
	_pitch.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 65.0
	camera.far = 600.0
	_arm.add_child(camera)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.85
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1, 0.25, 0.2)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.top_level = true
	_ring.visible = false
	add_child(_ring)


## The class's look for Humanoid.build (also the title screen's hero preview).
static func look_of(class_id: String) -> Dictionary:
	var c: Dictionary = CLASSES[class_id]
	var look := {"outfit": c.outfit, "pick": [0.0] + Array(c.pick).slice(1)}
	for k in ["weapon", "offhand", "shield", "bow", "weapon_rot"]:
		if c.has(k):
			look[k] = c[k]
	if c.helmet:
		look["helmet"] = "res://assets/characters/warrior/helmet.glb"
	if class_id == "warrior":
		look["layers"] = {"legs": LEG_LAYERS.plate, "shoulders": SHOULDER_LAYERS.plate}
	if ROBES.has(class_id):
		look["robe"] = ROBES[class_id]
	return look


## A robe for anyone else in a cloth chest piece.
const ROBE_PLAIN := [Color(0.35, 0.3, 0.24), Color(0.6, 0.53, 0.4), Color(0.16, 0.13, 0.1)]
## The casters' robes (Humanoid.set_robe): [cloth, embroidery, accent (panel, belt, hem, cuffs)];
## muted, like dyed wool and linen; the warlock red with black.
const ROBES := {
	"mage": [Color(0.13, 0.17, 0.32), Color(0.66, 0.6, 0.44), Color(0.06, 0.08, 0.15)],
	"priest": [Color(0.78, 0.76, 0.7), Color(0.66, 0.55, 0.3), Color(0.5, 0.47, 0.42)],
	"warlock": [Color(0.28, 0.035, 0.03), Color(0.36, 0.05, 0.04), Color(0.03, 0.025, 0.025)],
	"druid": [Color(0.22, 0.27, 0.16), Color(0.5, 0.4, 0.24), Color(0.12, 0.14, 0.08)],
}


func set_level(level: int) -> void:
	stats.setup(level, stats.base)
	for ps: Array in passives():
		if stats.level >= int(ps[0]):
			_slot_passive(ps[1])
	_level_passives()


func _level_passives() -> void:
	stats.cheat_death_cd = 120.0 if has_passive("Cheat Death") else 0.0
	stats.prey_on_weak = has_passive("Prey on the Weak")
	stats.poison_resist = has_passive("Poison Resistance")
	if bear:
		stats.attack = stats.magic      # Bear Form fights with Magic as Attack


# --- input -------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	_autorun_input(event)            # every key, also those the HUD or a menu takes


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_lmb = mb.pressed
				if mb.pressed:
					_press_pos = mb.position
					_drag = 0.0
				elif _drag < 6.0:
					_click_target(mb.position, false)
			MOUSE_BUTTON_RIGHT:
				_rmb = mb.pressed
				if mb.pressed:
					_press_pos = mb.position
					_drag = 0.0
					# Right drag steers the hero: face where the camera looks.
					rotation.y += cam_yaw
					cam_yaw = 0.0
				elif _drag < 6.0:
					_click_target(mb.position, true)
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					# Camera back behind the hero, at the default angle.
					cam_yaw = 0.0
					cam_pitch = deg_to_rad(-18.0)
			MOUSE_BUTTON_WHEEL_UP:
				zoom = maxf(ZOOM_MIN, zoom * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = minf(ZOOM_MAX, zoom * 1.1)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if (_lmb or _rmb) else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and (_lmb or _rmb):
		var mm := event as InputEventMouseMotion
		_drag += mm.relative.length()
		if _rmb:
			rotation.y -= mm.relative.x * MOUSE_SENS
		else:
			cam_yaw -= mm.relative.x * MOUSE_SENS
		cam_pitch = clampf(cam_pitch - mm.relative.y * MOUSE_SENS, deg_to_rad(-80), deg_to_rad(60))
	elif event.is_action_pressed("target_next"):
		_tab_target()
	elif event.is_action_pressed("camp"):
		toggle_camp()
	elif event.is_action_pressed("auto_attack"):
		if target and not target.stats.dead:
			auto_attacking = not auto_attacking
	elif event is InputEventKey and event.pressed and _zoom_key(event as InputEventKey) != 0:
		# Zoom with "-" (out) and "." (in), by the printed key (German layout: "-" sits right
		# of "."); holding repeats. Keypad - and + work too.
		zoom = clampf(zoom * (1.1 if _zoom_key(event as InputEventKey) > 0 else 0.9), ZOOM_MIN, ZOOM_MAX)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_KP_1 and k <= KEY_KP_6:
			k = k - KEY_KP_1 + KEY_1
		if k >= KEY_1 and k <= KEY_6:
			use_ability(k - KEY_1 + 1)
		elif k == KEY_R:
			use_potion()


## 1 = zoom out ("-"), -1 = zoom in ("."), 0 = not a zoom key.
## F2: run forward until a key is pressed that isn't strafing or turning (or F2 again).
var autorun := false
const AUTORUN_KEEPS := ["strafe_left", "strafe_right", "turn_left", "turn_right"]


func _autorun_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action("autorun"):
		autorun = not autorun
		return
	if not autorun:
		return
	for a in AUTORUN_KEEPS:
		if event.is_action(a):
			return
	autorun = false


func _zoom_key(e: InputEventKey) -> int:
	var label := e.key_label
	if label == KEY_MINUS or e.keycode == KEY_KP_SUBTRACT:
		return 1
	if label == KEY_PERIOD or e.keycode == KEY_KP_ADD:
		return -1
	return 0


func _click_target(screen_pos: Vector2, attack: bool) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is Enemy and not (hit.collider as Enemy).stats.dead:
		set_target(hit.collider)
		if attack:
			auto_attacking = true
	elif not attack:
		set_target(null)


## Tab: the nearest living enemy in front (within 40 m and ±75°); repeated presses cycle.
func _tab_target() -> void:
	var fwd := -global_transform.basis.z
	var cands: Array = []
	for e in World.enemies:
		if e.stats.dead or not e.visible:
			continue
		var d := e.global_position - global_position
		d.y = 0
		if d.length() > 40.0 or (d.length() > 3.0 and fwd.angle_to(d.normalized()) > deg_to_rad(75)):
			continue
		cands.append([d.length(), e])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var i := 0
	for k in cands.size():
		if cands[k][1] == target:
			i = (k + 1) % cands.size()
	set_target(cands[i][1])


## The closest live enemy within `max_dist`; one behind the hero counts 15 m farther.
func _nearest_hostile(max_dist: float) -> Enemy:
	var fwd := -global_transform.basis.z
	var best: Enemy = null
	var best_score := INF
	for e in World.enemies:
		if e.stats.dead or not e.visible or e.state == Enemy.State.RETURN:
			continue
		var d := e.global_position - global_position
		d.y = 0
		if d.length() > max_dist:
			continue
		var score := d.length() + (15.0 if d.length() > 3.0 and fwd.angle_to(d.normalized()) > deg_to_rad(75) else 0.0)
		if score < best_score:
			best_score = score
			best = e
	return best


func set_target(e: Enemy) -> void:
	target = e
	if e == null:
		auto_attacking = false


# --- combat ------------------------------------------------------------------------------

func abilities() -> Array:
	return abilities_of(cls)


static func abilities_of(class_id: String) -> Array:
	match class_id:
		"mage":
			return ABILITIES_MAGE
		"rogue":
			return ABILITIES_ROGUE
		"priest":
			return ABILITIES_PRIEST
		"paladin":
			return ABILITIES_PALADIN
		"warlock":
			return ABILITIES_WARLOCK
		"hunter":
			return ABILITIES_HUNTER
		"shaman":
			return ABILITIES_SHAMAN
		"druid":
			return ABILITIES_DRUID
	return ABILITIES_WARRIOR


## The action bar: SLOTS slots (keys 1–6), each an ability id or "" (abilities menu, saved).
## Every ability's "key" is its default slot.
const SLOTS := 6
var loadout: Array = []


func reset_loadout() -> void:
	loadout = []
	loadout.resize(SLOTS)
	loadout.fill("")
	for a in abilities():
		if int(a.key) >= 1 and int(a.key) <= SLOTS:
			loadout[int(a.key) - 1] = a.id


## Sets the loadout from a save (unknown ids are dropped).
func set_loadout(ids: Array) -> void:
	if ids.size() != SLOTS:
		return
	var known := abilities().map(func(a): return a.id)
	for i in SLOTS:
		loadout[i] = String(ids[i]) if String(ids[i]) in known else ""
	loadout_changed.emit()


## Passive slots: PASSIVE_SLOTS passive names or "" (abilities menu, saved). A passive works only
## while learned and in a slot; a newly learned one goes into a free slot by itself.
const PASSIVE_SLOTS := 3
var passive_loadout: Array = ["", "", ""]


## [level, name, text] of every passive of the class.
func passives() -> Array:
	return AbilityText.PASSIVES.get(cls, [])


func passive_level(name: String) -> int:
	for ps: Array in passives():
		if ps[1] == name:
			return int(ps[0])
	return 999


func has_passive(name: String) -> bool:
	return name in passive_loadout and stats.level >= passive_level(name)


## Puts a learned passive into the first free passive slot (if it isn't slotted yet).
func _slot_passive(name: String) -> void:
	if name in passive_loadout:
		return
	var free := passive_loadout.find("")
	if free >= 0:
		passive_loadout[free] = name


## From a save (unknown names dropped).
func set_passive_loadout(names: Array) -> void:
	if names.size() != PASSIVE_SLOTS:
		return
	for i in PASSIVE_SLOTS:
		var n := String(names[i])
		passive_loadout[i] = n if passive_level(n) < 999 else ""
	# Passives added to the game after the save was made: learned ones take a free slot.
	for ps: Array in passives():
		if stats.level >= int(ps[0]) and not String(ps[1]) in names:
			_slot_passive(ps[1])
	_level_passives()
	loadout_changed.emit()


func ability_by_id(id: String) -> Dictionary:
	for a in abilities():
		if a.id == id:
			return a
	return {}


## The ability in slot i (0-based), {} if empty.
## The ability in slot i (0-based), {} if empty or not learned yet (an empty slot until then).
func slot_ability(i: int) -> Dictionary:
	var a := ability_by_id(String(loadout[i])) if i >= 0 and i < loadout.size() and loadout[i] != "" else {}
	return a if not a.is_empty() and stats.level >= int(a.level) else {}


func slot_of(id: String) -> int:
	return loadout.find(id)


func ability_by_key(key: int) -> Dictionary:
	return slot_ability(key - 1)


## Why an ability can't be used right now ("" = it can).
func ability_problem(a: Dictionary, ignore_gcd := false) -> String:
	if a.is_empty():
		return "Nothing on that key"        # an empty slot (or not learned yet)
	var t := Combatant.now()
	if stats.level < int(a.level):
		return "Learned at level %d" % a.level
	if stats.dead or stats.stunned():
		return "Can't do that now"
	if t < float(cooldowns.get(a.id, 0.0)):
		return "Not ready yet"
	if a.id != "battle_cry" and t < gcd_until and not ignore_gcd:
		return "Not ready yet"
	if bear and a.id != "bear_form":
		return "Not in Bear Form"
	if whirling and a.id not in ["whirlwind", "battle_cry"]:
		return "Whirlwinding"
	if not casting.is_empty():
		return "Already casting"
	if stats.rage < float(a.get("rage", 0)):
		return "Not enough rage"
	if stats.mana < float(a.get("mana", 0)):
		return "Not enough mana"
	if stats.energy < float(a.get("energy", 0)):
		return "Not enough energy"
	match a.id:
		"battle_cry", "thunder_clap", "frost_ring", "mana_shield", "blink", "whirlwind":
			return ""
		"stealth":
			return "Not while in combat" if stats.in_combat() else ""
		"overwhelm":
			if t > overwhelm_until:
				return "Only after a miss or dodge"
	if a.get("self", false):
		return ""
	if target == null or target.stats.dead:
		return "No target"
	var d := _target_distance()
	if a.has("range") and float(a.range) > 0.0:
		if d > float(a.range):
			return "Out of range"
		if not _facing_target(90.0):
			return "You must face the target"
		return ""
	if a.id == "charge":
		if stats.in_combat() and not has_passive("Juggernaut"):
			return "Not in combat"
		if d < 8.0 or d > 25.0:
			return "Out of range (8–25 m)"
		return ""
	if d > MELEE_RANGE + float(target.data.radius):
		return "Out of range"
	if not _facing_target():
		return "You must face the target"
	return ""


## Abilities without the "self" flag that are no attack (they don't start auto-attack).
const NOT_ATTACKS := ["battle_cry", "mana_shield", "blink", "stealth"]


func use_ability(key: int) -> void:
	var a := ability_by_key(key)
	if a.is_empty():
		return
	# An attack without a target picks the nearest hostile one (preferring those in front).
	var attack: bool = not a.get("self", false) and not a.id in NOT_ATTACKS and stats.level >= int(a.level)
	if attack and (target == null or target.stats.dead):
		var e := _nearest_hostile(30.0)
		if e:
			set_target(e)
	# Any attack on a live target starts auto-attack (like WoW), even when the ability itself
	# can't be used yet (not enough rage, cooldown, out of range).
	if not a.get("self", false) and not a.id in NOT_ATTACKS and target and not target.stats.dead and stats.level >= int(a.level):
		auto_attacking = true
	if a.id == "whirlwind" and whirling:
		_stop_whirl()                 # pressed again: stop spinning
		return
	var why := ability_problem(a)
	if why != "":
		message.emit(why)
		return
	break_camp()
	var t := Combatant.now()
	if a.has("channel"):
		# A channel: paid when it starts, then it works every tick while the hero stands still.
		_spend_and_cooldown(a, t)
		var c := target.global_position
		casting = {"a": a, "start": t, "end": t + float(a.channel), "target": target, "channel": true,
			"next": t + 0.4, "center": c}
		if a.id == "blizzard":
			_channel_fx = SpellFx.Blizzard.start(Vector3(c.x, World.height_at(c.x, c.z), c.z), BLIZZARD_RADIUS)
		return
	if float(a.get("cast", 0.0)) > 0.0:
		# Cast time: the spell goes off at the end, if the hero didn't move (see _cast_process).
		casting = {"a": a, "start": t, "end": t + float(a.cast), "target": target}
		gcd_until = t + GCD
		return
	_spend_and_cooldown(a, t)
	_execute(a)


func _spend_and_cooldown(a: Dictionary, t: float) -> void:
	stats.rage -= float(a.get("rage", 0))
	stats.mana -= float(a.get("mana", 0))
	stats.energy -= float(a.get("energy", 0))
	if a.id != "stealth":
		_break_stealth()
	if stats.uses_mana and float(a.get("mana", 0)) > 0.0:
		stats.last_cast = t
	if float(a.cd) > 0.0 and not (a.id == "charge" and has_passive("Juggernaut")):
		cooldowns[a.id] = t + float(a.cd)
	# The global cooldown follows instant abilities only: a spell with a cast time is free to
	# chain into the next one the moment it goes off (its cast already took longer).
	if a.id != "battle_cry" and float(a.get("cast", 0.0)) <= 0.0:
		gcd_until = maxf(gcd_until, t + GCD)


func _stun(e: Enemy, seconds: float) -> void:
	e.stats.stun_until = Combatant.now() + seconds
	World.float_text(e.global_position + Vector3(0, 1.6, 0), "Stunned", Color(1, 0.8, 0.3), 36, e)


func _execute(a: Dictionary) -> void:
	match a.id:
		"heavy_strike":
			_melee_hit(float(a.power), "strike", 1.0)
		"overwhelm":
			overwhelm_until = 0.0
			_melee_hit(float(a.power), "attack2", 1.0, true)
		"battle_cry":
			stats.rage = minf(100.0, stats.rage + float(a.gain))
			stats.add_buff("battle_cry", 120.0, {"attack": 1.25})
			World.float_text(global_position + Vector3(0, 2.2, 0), "Battle Cry", Color(1, 0.8, 0.3), 40, self)
			Audio.sfx("battle_cry")
		"thunder_clap":
			model.anim.play_shot("strike")
			for e in World.enemies:
				if not e.stats.dead and e.global_position.distance_to(global_position) < 8.0:
					var r := stats.roll_damage(e.stats, float(a.power))
					e.stats.take_damage(r.amount, r.crit, stats)
					e.stats.add_buff("thunder_clap", 10.0, {"attack_speed": 0.8})
					Audio.hit(weapon_sound(), r.crit, -3.0)
					e.engage()
		"charge":
			_charge_target = target
			_charge_until = Combatant.now() + 1.2
			if not stats.in_combat():
				# Opening a fight only: with Juggernaut, charging back and forth would farm rage.
				stats.rage = minf(100.0, stats.rage + float(a.gain))
			auto_attacking = true
		"whirlwind":
			whirling = true
			_whirl_tick = 0.0
			_whirl_hit()
		"rend":
			model.anim.play_shot("attack1")
			target.stats.add_dot("rend", 30.0, 0.05, stats)
			target.engage()
		"fire_bolt", "fireball", "ice_bolt", "smite", "hex_bolt", "storm_bolt", "thorn_lash", "moonbeam":
			_bolt(a)
		"steady_shot", "venom_arrow":
			_arrow(target, float(a.power), String(a.element), a.id)
		"mark_prey":
			model.anim.play_shot("release")
			target.stats.add_buff("mark_prey", 30.0, {"defense": 0.75})
			World.float_text(target.global_position + Vector3(0, 1.8, 0), "Marked", Color(1, 0.6, 0.3), 34, target)
			target.engage()
		"volley":
			model.anim.play_shot("release")
			var vc := target.global_position
			for e in World.enemies:
				if not e.stats.dead and e.global_position.distance_to(vc) < 8.0:
					_arrow(e, float(a.power), "Nature", "volley")
		"first_aid", "healing_wave":
			model.anim.play_shot("release")
			stats.heal(roundi(stats.max_hp * float(a.heal)))
			World.float_text(global_position + Vector3(0, 2.2, 0), "+%d" % roundi(stats.max_hp * float(a.heal)), Color(0.4, 1, 0.4), 44, self)
			Audio.sfx("heal")
		"flame_shock", "stone_shock", "frost_shock":
			model.anim.play_shot("release")
			_spell_hit(target, float(a.power), String(a.element))
			match a.id:
				"flame_shock":
					target.stats.add_dot("burn", 24.0, 1.0 / 32.0, stats)
				"stone_shock":
					target.silenced_until = Combatant.now() + 4.0
					World.float_text(target.global_position + Vector3(0, 1.8, 0), "Silenced", Color(0.8, 0.7, 0.5), 34, target)
				"frost_shock":
					target.stats.slow(8.0, 0.5)
			Audio.sfx("magic", -4.0)
			target.engage()
		"chain_lightning":
			model.anim.play_shot("release")
			Audio.sfx("magic")
			var hit: Array[Enemy] = [target]
			for e in World.enemies:
				if hit.size() >= 3:
					break
				if not e.stats.dead and e != target and e.global_position.distance_to(target.global_position) < 10.0:
					hit.append(e)
			for e in hit:
				_spell_hit(e, float(a.power), "Air")
				e.engage()
		"rejuvenate":
			stats.add_dot("rejuvenate", 24.0, 1.0 / 32.0, stats, true)
			World.float_text(global_position + Vector3(0, 2.2, 0), "Rejuvenate", Color(0.5, 1, 0.5), 36, self)
			Audio.sfx("heal", -4.0)
		"insect_swarm":
			model.anim.play_shot("release")
			target.stats.add_dot("insect_swarm", 24.0, 1.0 / 32.0, stats)
			target.stats.add_buff("insect_swarm", 24.0, {"attack": 0.75})
			World.float_text(target.global_position + Vector3(0, 1.8, 0), "Insect Swarm", Color(0.6, 0.9, 0.3), 34, target)
			target.engage()
		"grasping_roots":
			model.anim.play_shot("release")
			_spell_hit(target, float(a.power), "Nature")
			target.stats.root_until = Combatant.now() + 6.0
			World.float_text(target.global_position + Vector3(0, 1.6, 0), "Rooted", Color(0.5, 0.8, 0.3), 34, target)
			target.engage()
		"bear_form":
			_set_bear(not bear)
		"mend", "healing_light":
			model.anim.play_shot("release")
			stats.heal(roundi(stats.max_hp * float(a.heal)))
			World.float_text(global_position + Vector3(0, 2.2, 0), "+%d" % roundi(stats.max_hp * float(a.heal)), Color(0.4, 1, 0.4), 44, self)
			Audio.sfx("heal")
		"holy_burst":
			model.anim.play_shot("release")
			_ring_effect(Color(1, 0.95, 0.6), 8.0)
			Audio.sfx("magic")
			for e in World.enemies:
				if not e.stats.dead and e.global_position.distance_to(global_position) < 8.0:
					_spell_hit(e, float(a.power), "Holy")
					e.engage()
		"ward_of_light":
			stats.absorb = roundi(stats.max_hp * 0.25)
			World.float_text(global_position + Vector3(0, 2.2, 0), "Ward of Light", Color(1, 0.95, 0.6), 40, self)
			Audio.sfx("magic")
		"renewal":
			stats.add_dot("renewal", 24.0, 1.0 / 32.0, stats, true)
			World.float_text(global_position + Vector3(0, 2.2, 0), "Renewal", Color(0.5, 1, 0.5), 36, self)
			Audio.sfx("heal", -4.0)
		"mind_pain", "wither":
			model.anim.play_shot("release")
			target.stats.add_dot(a.id, 30.0 if a.id == "wither" else 24.0, 1.0 / 32.0, stats)
			World.float_text(target.global_position + Vector3(0, 1.8, 0), a.name, Color(0.7, 0.4, 1.0), 34, target)
			Audio.sfx("magic", -4.0)
			target.engage()
		"drain_life":
			model.anim.play_shot("release")
			target.stats.add_dot("drain_life", 15.0, 1.0 / 24.0, stats, false, true)
			World.float_text(target.global_position + Vector3(0, 1.8, 0), "Drain Life", Color(0.6, 1.0, 0.4), 34, target)
			Audio.sfx("magic", -4.0)
			target.engage()
		"hellfire_rain":
			# Meteors fall into the circle shown while casting; whoever stands in it when the
			# first ones land burns.
			model.anim.play_shot("release")
			var c := _area.global_position if _area else target.global_position
			Audio.sfx("fireball")
			var power := float(a.power)
			SpellFx.hellfire(c, HELLFIRE_RADIUS, func():
				for e in World.enemies:
					if not e.stats.dead and Vector2(e.global_position.x - c.x, e.global_position.z - c.z).length() < HELLFIRE_RADIUS:
						_spell_hit(e, power, "Fire")
						e.engage())
		"curse_of_weakness":
			model.anim.play_shot("release")
			target.stats.add_buff("curse_of_weakness", 30.0, {"attack": 0.75})
			World.float_text(target.global_position + Vector3(0, 1.8, 0), "Weakened", Color(0.7, 0.4, 1.0), 34, target)
			target.engage()
		"dread":
			model.anim.play_shot("release")
			target.stats.add_buff("dread", 8.0, {"attack_speed": 0.5})
			World.float_text(target.global_position + Vector3(0, 1.8, 0), "Dread", Color(0.6, 0.3, 0.9), 36, target)
			target.engage()
		"righteous_strike":
			_melee_hit(float(a.power), "strike", 1.0, false, 0.0, "Holy")
		"judgment_hammer":
			_melee_hit(float(a.power), "attack2", 1.0, false, 0.0, "Holy", _stun.bind(2.5))
		"holy_seal":
			stats.add_buff("holy_seal", 30.0, {})
			World.float_text(global_position + Vector3(0, 2.2, 0), "Holy Seal", Color(1, 0.95, 0.6), 40, self)
			Audio.sfx("stat_up")
		"devotion":
			stats.add_buff("devotion", 60.0, {"defense": 1.25})
			World.float_text(global_position + Vector3(0, 2.2, 0), "Devotion", Color(1, 0.95, 0.6), 40, self)
			Audio.sfx("stat_up")
		"divine_shield":
			stats.immune_until = Combatant.now() + 6.0
			World.float_text(global_position + Vector3(0, 2.2, 0), "Divine Shield", Color(1, 0.95, 0.6), 44, self)
			Audio.sfx("heal")
		"quick_stab":
			_melee_hit(float(a.power), "attack1", 1.0, false, 0.25)
		"gut_slash":
			_melee_hit(float(a.power), "strike", 1.0)
		"poisoned_blade":
			_melee_hit(float(a.power), "attack2", 1.0, false, 0.0, "Physical", func(e: Enemy):
				e.stats.add_dot("poison", 15.0, 1.0 / 32.0, stats))
		"cheap_shot":
			_melee_hit(float(a.power), "attack1", 1.0, false, 0.0, "Physical", _stun.bind(3.0))
		"knife_throw":
			model.anim.play_shot("release")
			var e := target
			Projectile.launch(global_position + Vector3(0, 1.4, 0) - global_transform.basis.z * 0.5, e, Color(0.8, 0.8, 0.85), func():
				if e.stats.dead:
					return
				var r := stats.roll_damage(e.stats, float(a.power), false, _ambush())
				e.stats.take_damage(r.amount, r.crit, stats)
				Audio.hit("dagger", r.crit)
				e.engage(), 0.07)
		"stealth":
			stealthed = not stealthed
			model.mat.set_shader_parameter("stealth", 1.0 if stealthed else 0.0)
			message.emit("Stealth" if stealthed else "")
		"frost_ring":
			model.anim.play_shot("release")
			_ring_effect(Color(0.6, 0.85, 1.0), 8.0)
			Audio.sfx("water")
			for e in World.enemies:
				if not e.stats.dead and e.global_position.distance_to(global_position) < 8.0:
					_spell_hit(e, float(a.power), "Ice")
					e.stats.root_until = Combatant.now() + 5.0
					e.engage()
		"mana_shield":
			stats.add_buff("mana_shield", 20.0, {})
			World.float_text(global_position + Vector3(0, 2.2, 0), "Mana Shield", Color(0.6, 0.7, 1.0), 40, self)
			Audio.sfx("magic")
		"ignite":
			model.anim.play_shot("release")
			target.stats.add_dot("ignite", 24.0, 1.0 / 32.0, stats)
			World.float_text(target.global_position + Vector3(0, 1.8, 0), "Ignite", Color(1, 0.55, 0.2), 36, target)
			Audio.sfx("fireball", -4.0)
			target.engage()
		"blink":
			var fwd := -global_transform.basis.z
			var to := global_position + fwd * 15.0
			var h := World.height_at(to.x, to.z)
			global_position = Vector3(to.x, h + 0.3, to.z)
			stats.root_until = 0.0
			stats.slow_until = 0.0
			Audio.sfx("magic")
	if target and (cls in ["warrior", "rogue", "paladin", "hunter"] or bear) and not a.get("self", false) and not (a.id in ["battle_cry", "stealth"]):
		auto_attacking = true


## Fire Bolt / Ice Bolt: a projectile; Ice Bolt slows the target by 40% for 6 s.
func _bolt(a: Dictionary) -> void:
	var e: Enemy = casting.get("target", target) if not casting.is_empty() else target
	if e == null or e.stats.dead:
		return
	model.anim.play_shot("release")
	var ice: bool = a.element == "Ice"
	Audio.sfx("water" if ice else ("magic" if a.element in ["Holy", "Dark"] else "fireball"), -4.0)
	if a.id == "moonbeam":
		# A column of moonlight comes down on the target.
		SpellFx.beam(e.global_position)
		_spell_hit(e, float(a.power), a.element)
		e.engage()
		return
	var from := global_position + Vector3(0, 1.5, 0) - global_transform.basis.z * 0.6
	Projectile.spell(from, e, String(a.element), func():
		if e.stats.dead:
			return
		_spell_hit(e, float(a.power), a.element)
		if ice:
			e.stats.slow(6.0, 0.6)
		if a.id == "fireball" and not e.stats.dead:
			# Fireball: sets the target alight (Ignite's burn).
			e.stats.add_dot("ignite", 24.0, 1.0 / 32.0, stats)
		e.engage(), 1.7 if a.id == "fireball" else 1.0)


func _spell_hit(e: Enemy, power: float, element: String) -> void:
	var r := stats.roll_spell(e.stats, power, element)
	e.stats.take_damage(r.amount, r.crit, stats)
	stats.mark_combat()
	Audio.sfx("crit" if r.crit else "hit", -6.0)


## A flat ring flashing on the ground (Frost Ring).
func _ring_effect(color: Color, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.85
	tm.outer_radius = radius
	mi.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	World.root.add_child(mi)
	mi.global_position = global_position + Vector3(0, 0.2, 0)
	mi.scale = Vector3(0.2, 1, 0.2)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(mi.queue_free)


## While casting: moving or jumping interrupts; at the end the spell goes off.
func _cast_process(t: float, moving: bool) -> void:
	if casting.is_empty():
		return
	if casting.get("channel", false):
		if moving or stats.stunned():
			_end_channel()
			message.emit("Interrupted")
		elif t >= float(casting.end):
			_end_channel()
		elif t >= float(casting.next):
			casting.next = float(casting.next) + float(casting.a.tick)
			_channel_tick(casting.a, casting.center)
		return
	var e: Enemy = casting.target
	var needs_target: bool = not casting.a.get("self", false)
	if moving or stats.stunned() or (needs_target and (e == null or e.stats.dead)):
		casting = {}
		message.emit("Interrupted")
		return
	if t >= float(casting.end):
		var a: Dictionary = casting.a
		_spend_and_cooldown(a, t)
		_execute(a)
		casting = {}


var _channel_fx: Node            ## a channel's effect (SpellFx.Blizzard), stopped when it ends


## One tick of a channel: Blizzard hits and slows every enemy in its circle.
func _channel_tick(a: Dictionary, c: Vector3) -> void:
	match a.id:
		"blizzard":
			for e in World.enemies:
				if not e.stats.dead and Vector2(e.global_position.x - c.x, e.global_position.z - c.z).length() < BLIZZARD_RADIUS:
					_spell_hit(e, float(a.power), "Ice")
					e.stats.slow(2.0, 0.5, "Chilled")
					e.engage()


func _end_channel() -> void:
	casting = {}
	if _channel_fx and is_instance_valid(_channel_fx):
		_channel_fx.stop()
	_channel_fx = null


const HELLFIRE_RADIUS := 8.0
const HEAL_ELEMENT := {"priest": "Holy", "paladin": "Holy", "shaman": "Water", "druid": "Nature", "hunter": "Nature"}
var _cast_glow: Node3D            ## the spell gathering in the left hand while casting
var _cast_rune: Node3D            ## a rune circle at the feet while casting
var _area: Node3D                 ## Hellfire Rain: its area, marked while casting


## Casting looks: light gathering in the hand and a rune circle at the feet, in the spell's
## colour; Hellfire Rain marks its area on the target.
func _cast_fx_process() -> void:
	if casting.is_empty():
		if _cast_glow:
			_cast_glow.queue_free()
			_cast_glow = null
		if _cast_rune:
			_cast_rune.queue_free()
			_cast_rune = null
		if _area:
			_area.queue_free()
			_area = null
		return
	var a: Dictionary = casting.a
	if _cast_glow == null:
		var el := String(a.get("element", HEAL_ELEMENT.get(cls, "Holy")))
		_cast_glow = model.attach_to_bone("LeftHand", SpellFx.hand_glow(el), Vector3(0, -0.08, 0.04))
		# The rune at the feet only for the big ones: channels and casts of 2.5 s or more.
		if a.has("channel") or float(a.get("cast", 0.0)) >= 2.5:
			_cast_rune = SpellFx.rune(SpellFx.color(el), 1.1, 0.25, 0.5)
			add_child(_cast_rune)
			_cast_rune.position.y = 0.06
		if a.id == "hellfire_rain":
			_area = SpellFx.area_marker(HELLFIRE_RADIUS)
			World.root.add_child(_area)
	if _area and is_instance_valid(casting.target):
		var tp: Vector3 = (casting.target as Node3D).global_position
		_area.global_position = Vector3(tp.x, World.height_at(tp.x, tp.z), tp.z)


func _target_distance() -> float:
	var d := target.global_position - global_position
	return Vector2(d.x, d.z).length()


func _facing_target(cone := 60.0) -> bool:
	var d := target.global_position - global_position
	d.y = 0
	if d.length() < 0.6:
		return true
	return (-global_transform.basis.z).angle_to(d.normalized()) < deg_to_rad(cone)


## A melee hit on the target. In a bandit's smoke cloud half of the hits miss; enemies dodge 5%
## of hits from the front; a miss or dodge makes Overwhelm usable for 5 s (design/classes.md).
## What the hero's blows sound like: the main-hand weapon's kind (the class weapon without one),
## claws in Bear Form, a wooden knock for the hunter's bow.
func weapon_sound() -> String:
	if bear:
		return "claw"
	var kind := ""
	var main: Dictionary = equipped.get("main", {})
	if not main.is_empty():
		kind = String(main.kind)
	else:
		kind = String(CLASSES[cls].get("weapon", "")).get_file().get_basename()
	kind = {"greatsword": "sword", "greataxe": "axe", "maul": "mace"}.get(kind, kind)
	for k in ["sword", "axe", "mace", "dagger", "staff", "club"]:
		if kind.begins_with(k):
			return k
	return "staff"


## A melee blow: the swing starts now, the blow lands (hit, miss or dodge, the damage, the sound
## and `on_hit`) at the clip's moment of impact (CharAnimator.impact), if the target is still
## alive and within reach then.
func _melee_hit(power: float, anim: String, extra: float, no_miss := false, extra_crit := 0.0, element := "Physical", on_hit := Callable()) -> void:
	model.anim.play_shot(anim)
	extra *= _ambush()
	_break_stealth()
	var e := target
	e.engage()
	stats.mark_combat()
	get_tree().create_timer(CharAnimator.impact(anim), false).timeout.connect(func():
		if is_instance_valid(e) and not e.stats.dead and not stats.dead:
			_melee_land(e, power, anim, extra, no_miss, extra_crit, element, on_hit))


func _melee_land(e: Enemy, power: float, anim: String, extra: float, no_miss: bool, extra_crit: float, element: String, on_hit: Callable) -> void:
	var to_me := global_position - e.global_position
	if to_me.length() > MELEE_RANGE + float(e.data.radius) + 1.5:
		Audio.sfx("miss", -4.0)              # it got away during the swing
		return
	stats.mark_combat()
	if not no_miss and (World.in_smoke(global_position) or e.is_flying()) and randf() < 0.5:
		World.float_text(e.global_position + Vector3(0, 1.6, 0), "Miss", Color(0.8, 0.8, 0.8), 40, e)
		Audio.sfx("miss")
		overwhelm_until = Combatant.now() + 5.0
		return
	# Dodge: only facing the attacker (not from behind), like WoW; it opens Overwhelm too.
	if not no_miss and randf() < e.stats.dodge_chance and to_me.dot(-e.global_transform.basis.z) > 0.0:
		World.float_text(e.global_position + Vector3(0, 1.6, 0), "Dodge", Color(0.8, 0.8, 0.8), 40, e)
		Audio.sfx("miss")
		overwhelm_until = Combatant.now() + 5.0
		return
	stats.crit_chance += extra_crit
	var r := stats.roll_damage(e.stats, power, anim.begins_with("attack") and power < 40.0, extra * _enrage()) if element == "Physical" else stats.roll_damage_elem(e.stats, power, element)
	stats.crit_chance -= extra_crit
	if stats.has_buff("holy_seal"):
		# Holy Seal (paladin): every physical hit adds a Holy hit of power 20.
		var hs := stats.roll_damage_elem(e.stats, 20.0, "Holy")
		e.stats.take_damage(hs.amount, hs.crit, stats)
	e.stats.take_damage(r.amount, r.crit, stats)
	Audio.hit(weapon_sound(), r.crit)
	if power >= 40.0:
		Audio.sfx("slash", -6.0)          # strong blows: the blade's swish over the impact
	stats.rage = minf(100.0, stats.rage + (16.0 if r.crit else 8.0) * (1.0 if power < 40.0 else 0.0))
	if on_hit.is_valid() and not e.stats.dead:
		on_hit.call(e)


## Rogue: the first hit out of stealth deals 50% more.
const CONCUSSIVE_TIME := 4.0

## An arrow (Hunter): a projectile, physical damage with the element's chart and affinity.
func _arrow(e: Enemy, power: float, element: String, kind: String) -> void:
	model.anim.play_shot("release")
	Audio.sfx("bow_shot%d" % (randi() % 3 + 1), -3.0)
	stats.mark_combat()
	Projectile.arrow(global_position + Vector3(0, 1.4, 0) - global_transform.basis.z * 0.5, e, func():
		if e.stats.dead:
			return
		var r := stats.roll_damage_elem(e.stats, power, element) if element != "Physical" else stats.roll_damage(e.stats, power, kind == "auto")
		e.stats.take_damage(r.amount, r.crit, stats)
		Audio.hit("arrow", r.crit)
		if kind == "venom_arrow":
			e.stats.add_dot("poison", 15.0, 1.0 / 32.0, stats)
		if has_passive("Concussive Shots"):
			# Every arrow slows its target by 60% for 4 s (refreshed by the next one).
			e.stats.slow(CONCUSSIVE_TIME, 0.4, "Concussed")
		e.engage())


## Shaman (level 4): entering combat puts down a Wrath Totem (Magic +25% nearby) and a Healing
## Stream Totem (heals 1/32 of max HP every 3 s), for 30 s (Oldworld2's totems).
func _totem_process(t: float) -> void:
	if not has_passive("Totems"):
		return
	if stats.in_combat() and t > _totem_until:
		_totem_until = t + 30.0
		for n in _totems:
			n.queue_free()
		_totems.clear()
		var side := global_transform.basis.x
		for k in [["res://assets/props/totem_wrath.glb", -1.6], ["res://assets/props/totem_healing.glb", 1.6]]:
			if not ResourceLoader.exists(k[0]):
				continue
			var n: Node3D = load(k[0]).instantiate()
			World.root.add_child(n)
			var p: Vector3 = global_position + side * float(k[1]) - global_transform.basis.z * 1.0
			var aabb := Placement._aabb(n)
			var s := 1.6 / maxf(aabb.size.y, 0.01)
			n.scale = Vector3.ONE * s
			n.global_position = Vector3(p.x, World.height_at(p.x, p.z) - aabb.position.y * s, p.z)
			_totems.append(n)
		Audio.sfx("magic", -6.0)
		World.float_text(global_position + Vector3(0, 2.4, 0), "Totems", Color(0.6, 0.8, 1.0), 36, self)
	var near := false
	for n in _totems:
		if is_instance_valid(n) and n.global_position.distance_to(global_position) < 20.0:
			near = true
	if near and t < _totem_until:
		stats.add_buff("wrath_totem", 1.0, {"magic": 1.25})
		if not stats.dots.has("healing_stream"):
			stats.add_dot("healing_stream", 6.0, 1.0 / 32.0, stats, true)
	elif t > _totem_until and not _totems.is_empty():
		for n in _totems:
			n.queue_free()
		_totems.clear()


## Druid Bear Form: the hero becomes a bear (melee, Defense ×2, uses Magic as Attack), heals
## 25% on shifting. Shifting back restores the druid.
func _set_bear(on: bool) -> void:
	bear = on
	model.visible = not on
	if on:
		if _bear_model == null:
			_bear_model = load("res://assets/creatures/bear.glb").instantiate() if ResourceLoader.exists("res://assets/creatures/bear.glb") else load("res://assets/creatures/boar.glb").instantiate()
			_bear_model.rotation.y = PI
			add_child(_bear_model)
		_bear_model.visible = true
		stats.add_buff("bear_form", 3600.0, {"defense": 2.0})
		stats.attack = stats.magic
		stats.weapon_mult = Rules.weapon_mult(Rules.weapon_ref(stats.level))   # claws: like a same-level weapon
		stats.swing_time = 2.0
		stats.heal(roundi(stats.max_hp * 0.25))
		auto_attacking = target != null
		World.float_text(global_position + Vector3(0, 2.2, 0), "Bear Form", Color(0.7, 0.5, 0.3), 40, self)
	else:
		if _bear_model:
			_bear_model.visible = false
		stats.buffs.erase("bear_form")
		stats.recompute()
		stats.swing_time = CLASSES[cls].swing
		auto_attacking = false
	Audio.sfx("stat_up")


func _ambush() -> float:
	return 1.5 if stealthed else 1.0


func _break_stealth() -> void:
	if stealthed:
		stealthed = false
		model.mat.set_shader_parameter("stealth", 0.0)
		cooldowns["stealth"] = Combatant.now() + 6.0


func _enrage() -> float:
	return 1.25 if stats.has_buff("enrage") else 1.0


signal hint(text: String)            ## a tip shown once, a bit longer than a message
var tips_shown := {}                 ## tip id -> true (saved)
var _was_fighting := false
var _combat_check_at := 0.0


## Combat ends as soon as no living enemy is after the hero (not only 5 s after the last hit):
## after the last kill, Charge and camping are free again. A short grace after a hit, while a
## missile is on its way or the struck enemy turns to fight.
func _combat_end_check(t: float) -> void:
	if t < _combat_check_at or not stats.in_combat():
		return
	_combat_check_at = t + 0.25
	if t - stats.last_combat < 1.0:
		return
	for e in World.enemies:
		if e.state == Enemy.State.CHASE and not e.stats.dead:
			return
	stats.last_combat = -100.0


## Tips for a new hero: after the first fight, how to rest.
func _tips_process() -> void:
	var fighting := stats.in_combat()
	if _was_fighting and not fighting and kills > 0 and not tips_shown.has("camp") and not stats.dead:
		tips_shown["camp"] = true
		hint.emit("Tip: press C to camp and recover your health%s." % (" and mana" if stats.uses_mana else ""))
	_was_fighting = fighting


func _combat_process(t: float) -> void:
	_combat_end_check(t)
	_tips_process()
	# Demon Armor (warlock, level 4): regenerates 1/32 max HP every 3 s while fighting.
	if has_passive("Demon Armor") and stats.in_combat() and not stats.dots.has("demon_armor"):
		stats.add_dot("demon_armor", 9.0, 1.0 / 32.0, stats, true)
	if target and (target.stats.dead or not target.visible):
		set_target(null)
	if target:
		_ring.visible = true
		_ring.global_position = target.global_position + Vector3(0, 0.08, 0)
		var s: float = float(target.data.radius) * 1.6 + 0.4
		_ring.scale = Vector3(s, 1, s)
	else:
		_ring.visible = false
	_totem_process(t)
	if has_passive("Juggernaut") and stats.in_combat():
		# Juggernaut: 1 rage per second while fighting.
		var dt := clampf(t - _jugg_t, 0.0, 0.5)
		stats.rage = minf(100.0, stats.rage + dt)
	_jugg_t = t
	if whirling:
		if stats.stunned() or stats.dead:
			_stop_whirl()
		elif t >= _whirl_tick:
			if stats.rage < WHIRL_RAGE:
				_stop_whirl()
			else:
				stats.rage -= WHIRL_RAGE
				_whirl_hit()
		return                        # no auto-attack swings while spinning
	if cls == "hunter" and auto_attacking and target and t >= _swing_at and not stats.stunned() and casting.is_empty():
		var d := _target_distance()
		if d > 5.0 and d < 30.0 and _facing_target(90.0):
			# Auto Shot: the bow fires on the swing timer.
			_swing_at = t + stats.swing_time
			_arrow(target, Rules.swing_power(stats.swing_time), "Physical", "auto")
			return
	if auto_attacking and target and t >= _swing_at and not stats.stunned():
		if _target_distance() <= MELEE_RANGE + float(target.data.radius) and _facing_target():
			_swing_at = t + stats.swing_time
			_melee_hit(Rules.swing_power(stats.swing_time), _next_attack, 1.0)
			# Two slashes, then a thrust, then again.
			_next_attack = {"attack1": "attack2", "attack2": "attack3"}.get(_next_attack, "attack1")


## One Whirlwind sweep: every live enemy within reach takes a hit (no rage from these hits).
func _whirl_hit() -> void:
	_whirl_tick = Combatant.now() + 1.0
	stats.mark_combat()
	var a := ability_by_id("whirlwind")
	var hit := false
	for e in World.enemies:
		if e.stats.dead or not e.visible:
			continue
		if e.global_position.distance_to(global_position) > WHIRL_RADIUS + float(e.data.radius):
			continue
		var r := stats.roll_damage(e.stats, float(a.power), false, _enrage())
		e.stats.take_damage(r.amount, r.crit, stats)
		e.engage()
		Audio.hit(weapon_sound(), r.crit, -2.0)
		hit = true
		if e.stats.dead and cooldowns.has("whirlwind"):
			# Every kill by Whirlwind takes WHIRL_KILL_CD s off its own cooldown.
			cooldowns["whirlwind"] = float(cooldowns["whirlwind"]) - WHIRL_KILL_CD
			World.float_text(global_position + Vector3(0, 2.6, 0), "-%d s" % int(WHIRL_KILL_CD), Color(1, 0.8, 0.3), 32, self)
	Audio.sfx("miss", -6.0 if hit else -2.0)       # the blade's whoosh


func _stop_whirl() -> void:
	if whirling:
		_unwinding = true
	whirling = false


## Struck without a target: the attacker becomes the target.
func _on_attacked(source: Combatant) -> void:
	if (target == null or target.stats.dead) and source.body is Enemy and not source.dead:
		set_target(source.body)


func _on_damaged(amount: int, crit: bool, source: Combatant) -> void:
	_break_stealth()
	if not stats.ticking:
		break_camp()              # direct hits only: poison, bleeding etc. don't end the rest
	# Thorns (druid, level 4): a melee hit hurts the attacker for 1/16 of the druid's max HP.
	if has_passive("Thorns") and source and source.body is Enemy and not source.dead:
		var e := source.body as Enemy
		if not e.data.has("ranged") and e.global_position.distance_to(global_position) < 5.0:
			source.take_damage(maxi(1, stats.max_hp / 16), false, stats)
	World.float_text(global_position + Vector3(0, 2.0, 0), "-%d" % amount + ("!" if crit else ""), Color(1, 0.3, 0.25), 56 if crit else 44, self, crit)
	# Enrage (level 3): a crit taken, or 30% on any hit, gives +25% damage for 12 s.
	if has_passive("Enrage") and (crit or randf() < 0.3):
		stats.add_buff("enrage", 12.0, {})
	# Second Wind (level 8): 30% (crits always) to heal 1/32 max HP every 3 s for 9 s.
	if has_passive("Second Wind") and (crit or randf() < 0.3):
		stats.add_dot("second_wind", 9.0, 1.0 / 32.0, stats, true)
	# Dazed: a direct hit from behind by an enemy, 30%: half speed for 4 s (like WoW's daze).
	if not stats.ticking and source and source.body is Enemy and randf() < 0.3:
		var from := source.body.global_position - global_position
		if from.dot(-global_transform.basis.z) < 0.0:
			stats.slow(DAZE_TIME, 0.5, "Dazed")
			World.float_text(global_position + Vector3(0, 2.3, 0), "Dazed", Color(0.95, 0.85, 0.5), 38, self)
	if randf() < 0.25:
		model.anim.play_shot("hit")


func _on_died(_killer: Combatant) -> void:
	_dead_at = Combatant.now()
	auto_attacking = false
	_end_channel()
	_stop_whirl()
	model.anim.set_move("death")
	Audio.sfx("defeat")
	message.emit("You died. You wake up at the last checkpoint…")
	stats.last_combat = -100.0
	for e in World.enemies:
		if e.state == Enemy.State.CHASE:
			e._go_home()


var deaths := 0


func _respawn() -> void:
	deaths += 1
	# Death penalty (design/game-design.md, 7): 10% of the money and the XP toward the next level.
	var lost_money := money - int(money * 0.9)
	var lost_xp := xp
	money -= lost_money
	xp = 0
	var lines: Array = []
	lines.append("Lost %s (10%% of your money)" % Items.money_text(lost_money) if lost_money > 0 else "No money lost")
	lines.append("Lost %d XP (the progress toward level %d)" % [lost_xp, stats.level + 1] if lost_xp > 0 else "No XP lost")
	death_banner.emit.call_deferred(lines)
	stats.revive()
	if World.zones:
		World.zones.ensure(World.zones.cell_of(checkpoint))   # the checkpoint's zone may be unloaded
	global_position = checkpoint
	velocity = Vector3.ZERO
	_dead_at = -1.0
	set_target(null)
	model.anim.set_move("idle")
	saved_point.emit()


var kills := 0


func on_kill(e: Enemy) -> void:
	kills += 1
	var gained := Rules.enemy_xp(e.stats.level, stats.level, e.stats.tier)
	money += e.stats.level * ({"elite": 8, "champion": 40}.get(e.stats.tier, 3) as int)
	_loot(e)
	for q in quests.on_kill(e.kind):
		message.emit("%s: complete! Return to the inn." % q.title)
		Audio.sfx("stat_up")
	if not quests.active.is_empty():
		quests_changed.emit()
	if gained <= 0:
		return
	_gain_xp(gained)


func _gain_xp(gained: int) -> void:
	xp += gained
	World.float_text(global_position + Vector3(0, 2.4, 0), "+%d XP" % gained, Color(0.7, 0.5, 1.0), 40, self)
	while xp >= Rules.xp_to_next(stats.level):
		xp -= Rules.xp_to_next(stats.level)
		var hp_frac := float(stats.hp) / stats.max_hp
		stats.setup(stats.level + 1, stats.base)
		stats.hp = roundi(stats.max_hp * maxf(hp_frac, 0.5))
		_level_passives()
		var learned: Array = []
		for ab in abilities():
			if int(ab.level) == stats.level:
				var s := slot_of(ab.id)
				learned.append(("New ability: %s  (key %d)" % [ab.name, s + 1]) if s >= 0 else "New ability: %s  (put it on the bar in the abilities menu, N)" % ab.name)
		for ps: Array in passives():
			if int(ps[0]) == stats.level:
				_slot_passive(ps[1])
				learned.append(("New passive: %s" % ps[1]) if ps[1] in passive_loadout else "New passive: %s  (put it in a passive slot in the abilities menu, N)" % ps[1])
		_level_passives()
		leveled_up.emit(stats.level)
		loadout_changed.emit()            # newly learned abilities appear on the bar
		level_banner.emit(stats.level, learned)
		Audio.sfx("level_up")
		World.float_text(global_position + Vector3(0, 2.6, 0), "Level %d!" % stats.level, Color(1, 0.85, 0.2), 64, self)


func knockback(v: Vector3) -> void:
	_knock = v


# --- camp --------------------------------------------------------------------------------

## Camp (Oldworld2): C while standing still lights a fire; the hero sits and regenerates 10% of
## max HP and 20% of max mana per second. Moving, turning, jumping, an ability or a direct hit (not damage over time) breaks
## camp. Enemies can still find a resting hero.
const CAMP_HP := 0.10
const CAMP_MANA := 0.20
var camp: Node3D                    ## the fire while camping
var _camp_hp := 0.0
var _camp_since := 0.0
## Resting eases in: nothing for CAMP_DELAY s while the fire catches, then half the rate,
## rising to the full rate over CAMP_RAMP s.
const CAMP_DELAY := 1.0
const CAMP_RAMP := 4.0
var _crackle_at := 0.0


func toggle_camp() -> void:
	if camp:
		break_camp()
		return
	if stats.dead or bear or not is_on_floor() or Vector2(velocity.x, velocity.z).length() > 0.1 or not casting.is_empty():
		return
	auto_attacking = false
	model.stow(true)          # weapons and shield put away while resting
	camp = Node3D.new()
	get_parent().add_child(camp)
	var fwd := -global_transform.basis.z
	var p := global_position + fwd * 1.8      # past the outstretched feet
	p.y = World.height_at(p.x, p.z)
	camp.global_position = p
	var path := "res://assets/props/campfire.glb"
	if ResourceLoader.exists(path):
		var n: Node3D = load(path).instantiate()
		camp.add_child(n)
		var box := Placement._aabb(n)
		var sc := 1.0 / maxf(maxf(box.size.x, box.size.z), 0.001)    # 1 m across
		n.scale = Vector3.ONE * sc
		var c := box.get_center()
		n.position = Vector3(-c.x * sc, -box.position.y * sc - 0.03, -c.z * sc)
	camp.add_child(_flames())
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 7.0
	light.position.y = 0.5
	light.light_energy = 0.0
	camp.add_child(light)
	camp.create_tween().tween_property(light, "light_energy", 2.2, 0.6)
	camp.set_meta("light", light)
	model.rotation.y = 0.0
	_camp_hp = 0.0
	_camp_since = Combatant.now()
	_crackle_at = Combatant.now() + 0.8
	Audio.sfx("light")
	message.emit("You rest at a camp fire.")


## Flickering flames: small glowing quads that rise, shrink and fade.
func _flames() -> CPUParticles3D:
	var f := CPUParticles3D.new()
	f.amount = 28
	f.lifetime = 0.7
	f.position.y = 0.12
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.16
	f.direction = Vector3.UP
	f.spread = 12.0
	f.gravity = Vector3(0, 1.2, 0)
	f.initial_velocity_min = 0.4
	f.initial_velocity_max = 0.9
	f.scale_amount_min = 0.7
	f.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0))
	curve.add_point(Vector2(1, 0.1))
	f.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.35, 1.0))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	f.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5 * 0.8).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	m.albedo_texture = ImageTexture.create_from_image(img)
	q.material = m
	f.mesh = q
	return f


func break_camp() -> void:
	if camp == null:
		return
	var c := camp
	camp = null
	model.stow(false)
	var light: OmniLight3D = c.get_meta("light")
	var tw := c.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.tween_callback(c.queue_free)


func _camp_process(dt: float) -> void:
	if camp == null:
		return
	if stats.dead:
		break_camp()
		return
	var since := Combatant.now() - _camp_since
	var rate := 0.0 if since < CAMP_DELAY else 0.5 + 0.5 * clampf((since - CAMP_DELAY) / CAMP_RAMP, 0.0, 1.0)
	_camp_hp += stats.max_hp * CAMP_HP * rate * dt
	if _camp_hp >= 1.0:
		stats.hp = mini(stats.max_hp, stats.hp + int(_camp_hp))
		_camp_hp -= int(_camp_hp)
	if stats.uses_mana:
		stats.mana = minf(stats.max_mana, stats.mana + stats.max_mana * CAMP_MANA * rate * dt)
	var light: OmniLight3D = camp.get_meta("light")
	if light.light_energy > 1.5:          # flicker once the fire is lit
		light.light_energy = 2.2 + 0.35 * sin(Combatant.now() * 17.0) * sin(Combatant.now() * 5.3)
	var t := Combatant.now()
	if t >= _crackle_at:
		_crackle_at = t + randf_range(0.7, 1.8)
		Audio.sfx("fire_crackle%d" % randi_range(1, 2), -8.0)


# --- movement ----------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var t := Combatant.now()
	if stats.dead:
		velocity = Vector3(0, velocity.y - GRAVITY * dt, 0) if not is_on_floor() else Vector3.ZERO
		move_and_slide()
		if t - _dead_at > 4.0:
			_respawn()
		return
	_combat_process(t)
	_camp_process(dt)
	if World.zones and not World.zones.zones.has(World.zones.cell_of(global_position)):
		if not World.zones.ensure_here(global_position):
			velocity = Vector3.ZERO                       # a zone still building: wait, don't fall
			return
	# Fallen through the world (a save from an older version, a gap in the ground): back on top.
	var ground := World.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 2.0:
		global_position.y = ground + 0.5
		velocity = Vector3.ZERO
	if t < _charge_until and _charge_target and not _charge_target.stats.dead:
		_do_charge(dt)
		return
	var fwd := Input.get_axis("move_back", "move_forward")
	if (_lmb and _rmb) or auto_forward or autorun:
		fwd = 1.0
	var side := Input.get_axis("strafe_left", "strafe_right")
	var turn := Input.get_axis("turn_right", "turn_left")
	if _rmb:
		side = clampf(side - turn, -1.0, 1.0)
		turn = 0.0
	if stats.stunned():
		fwd = 0.0
		side = 0.0
		turn = 0.0
	rotation.y += turn * TURN_SPEED * dt

	var local := Vector3(side, 0, -fwd)
	if local.length() > 1.0:
		local = local.normalized()
	var speed := RUN_SPEED * stats.move_factor() * (0.7 if stealthed else 1.0) * (0.5 if whirling else 1.0)
	# Sprint forward or sideways (strafing), not backward.
	var moving := local.length() > 0.01 and fwd >= 0.0
	sprinting = ((Input.is_action_pressed("sprint") or auto_sprint) and moving and stamina > 0.0 and is_on_floor()) or (sprinting and not is_on_floor())
	if sprinting:
		speed *= SPRINT_FACTOR
		# Improved Sprint (rogue, level 6): stamina lasts five times as long (Oldworld2).
		var drain := 0.2 if has_passive("Improved Sprint") else 1.0
		stamina = maxf(0.0, stamina - dt / STAMINA_TIME * drain)
	else:
		var refill := dt / STAMINA_REFILL * (2.0 if local.length() < 0.01 else 1.0)
		stamina = minf(1.0, stamina + refill)
	if fwd < 0.0:
		speed *= BACK_FACTOR
	_cast_process(t, local.length() > 0.01 or not is_on_floor() or Input.is_action_just_pressed("jump"))
	if camp and (local.length() > 0.01 or Input.is_action_just_pressed("jump") or turn != 0.0):
		break_camp()
	var wish := global_transform.basis * local * speed + _knock
	_knock = _knock.move_toward(Vector3.ZERO, 20.0 * dt)
	velocity.x = wish.x
	velocity.z = wish.z
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
	_animate(local, speed, dt)


## Charge: rush to the target, stun it for 1.5 s.
func _do_charge(dt: float) -> void:
	var d := _charge_target.global_position - global_position
	d.y = 0
	rotation.y = atan2(-d.x, -d.z)
	if d.length() < MELEE_RANGE:
		_charge_until = 0.0
		_charge_target.stats.stun_until = Combatant.now() + 1.5
		_charge_target.engage()
		World.float_text(_charge_target.global_position + Vector3(0, 1.6, 0), "Stunned", Color(1, 0.8, 0.3), 36, _charge_target)
		return
	# Over the ground, whatever its slope: the height followed directly (at 22 m/s a bump
	# lifted the hero off a slope, and in the air the slope stopped him like a wall).
	velocity = d.normalized() * 22.0
	var ahead := global_position + velocity * dt
	velocity.y = clampf((World.height_at(ahead.x, ahead.z) - global_position.y) / maxf(dt, 0.001), -30.0, 30.0)
	move_and_slide()
	model.anim.set_move("run", 2.0)


var _air_time := 0.0
var _last_yaw := 0.0
var _yaw_rate := 0.0                ## rad/s the hero turned (keys, mouse steering)


func _animate(local: Vector3, speed: float, dt: float) -> void:
	var moving := local.length() > 0.01
	var yaw_step := angle_difference(_last_yaw, global_rotation.y)
	_last_yaw = global_rotation.y
	_yaw_rate = lerpf(_yaw_rate, absf(yaw_step) / maxf(dt, 0.001), 1.0 - exp(-10.0 * dt))
	# Strafing like WoW: the legs run toward where the hero moves (the model turned up to 75
	# degrees that way), the upper body turned back so the chest and head keep facing ahead: no
	# back shown to an enemy in front while running sideways.
	var target_yaw := 0.0
	if moving:
		var a := atan2(-local.x, -local.z) if local.z <= 0.01 else atan2(local.x, local.z)
		target_yaw = clampf(a, -deg_to_rad(75), deg_to_rad(75))
	if not whirling and not _unwinding:
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-12.0 * dt))
		model.set_torso_twist(-model.rotation.y)
	else:
		model.set_torso_twist(0.0)
	var st := "idle"
	var rate := 1.0
	if moving:
		var v := speed * local.length()
		st = "run" if v > 2.2 else "walk"
		rate = v / float(CharAnimator.CLIP_SPEED[st])
		if local.z > 0.01:
			rate = -rate   # walking backward plays the cycle in reverse
	# In the air (jumping or falling more than a moment): the jump clip, held while falling.
	if not is_on_floor():
		_air_time += dt
		if velocity.y > 0.5 or _air_time > 0.15:
			st = "jump"
			rate = CharAnimator.JUMP_RATE
	else:
		_air_time = 0.0
	# Turning on the spot: small shuffling steps (the walk cycle, slowly), like WoW.
	if not moving and is_on_floor() and st == "idle" and _yaw_rate > 0.6:
		st = "walk"
		rate = clampf(_yaw_rate / TURN_SPEED, 0.4, 1.0) * 0.9
	if camp:
		st = "sit"
		rate = 1.0
	elif st == "idle" and (auto_attacking or stats.in_combat()) and not stealthed:
		st = "ready"            # combat stance: sword up, knees bent
	model.anim.set_move(st, rate)
	if bear and _bear_model:
		_bear_phase += dt * speed * local.length() * 2.0
		_bear_model.position.y = absf(sin(_bear_phase)) * 0.08 if moving else 0.0
		_bear_model.rotation.y = PI + model.rotation.y


func _process(dt: float) -> void:
	model.anim.set_cast(not casting.is_empty(), dt)
	_cast_fx_process()
	if cls == "hunter":
		# The bow turns to its shooting hold in combat (and for any shot), slanted at rest.
		model.set_bow_aim(auto_attacking or stats.in_combat() or not casting.is_empty(), dt)
	# A two-hander is carried like a one-hander; in combat both hands take it (Humanoid).
	model.set_two_hand_stance(auto_attacking or stats.in_combat(), dt)
	if _whirl_fx:
		_whirl_fx.set_on(whirling)
		model.anim.set_whirl(whirling, dt)
		if model.trail:
			model.trail.sustain = whirling
		if whirling:
			_spin -= TAU * WHIRL_SPIN * dt
			model.rotation.y = wrapf(_spin, -PI, PI)
		elif _unwinding:
			# Finishes the turn (same direction) until it faces forward again; then the model
			# is _animate's again (it turns it toward strafe directions).
			var left := fposmod(model.rotation.y, TAU)
			var step := TAU * WHIRL_SPIN * dt
			_spin -= minf(step, left)
			model.rotation.y = 0.0 if step >= left else wrapf(_spin, -PI, PI)
			_unwinding = step < left
		_whirl_fx.turn = _spin / TAU
	_pivot.global_position = global_position + Vector3(0, 1.6, 0)
	_pivot.rotation.y = rotation.y + cam_yaw
	_pitch.rotation.x = cam_pitch
	_arm.spring_length = lerpf(_arm.spring_length, zoom, 0.25)


# --- items (scripts/items/items.gd) ------------------------------------------------------

signal inventory_changed


## Drops (items.md section 7): trash 7% gear and 12% a potion; elites 60% gear; always into
## the bag (auto loot). 60% of the gear fits the hero's class.
func _loot(e: Enemy) -> void:
	var elite := e.stats.tier != "trash"
	var champ := e.stats.tier == "champion"
	if champ or randf() < (0.6 if elite else 0.07):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var rarity := Items.roll_rarity(e.stats.tier if elite else "trash", rng)
		var item := Items.generate(e.stats.level, rarity, cls if randf() < 0.6 else "", rng)
		if add_item(item):
			message.emit("You receive: %s" % item.name)
			World.float_text(global_position + Vector3(0, 2.8, 0), item.name, Items.color(item), 36, self)
	if randf() < (0.3 if elite else 0.12):
		if add_item(Items.POTION.duplicate(true)):
			message.emit("You receive: Healing Potion")


func add_item(item: Dictionary) -> bool:
	if item.slot == "potion":
		for it in bag:
			if it.slot == "potion":
				it.count = int(it.count) + int(item.get("count", 1))
				inventory_changed.emit()
				return true
	if bag.size() >= Items.BAG_SIZE:
		message.emit("Your bags are full.")
		return false
	bag.append(item)
	inventory_changed.emit()
	return true


func potion_count() -> int:
	for it in bag:
		if it.slot == "potion":
			return int(it.count)
	return 0


func use_potion() -> void:
	var t := Combatant.now()
	if stats.dead:
		return
	if t < potion_ready:
		message.emit("Potion not ready (%d s)" % ceili(potion_ready - t))
		return
	for i in bag.size():
		var it: Dictionary = bag[i]
		if it.slot == "potion":
			it.count = int(it.count) - 1
			if int(it.count) <= 0:
				bag.remove_at(i)
			potion_ready = t + Items.POTION_CD
			var amount := roundi(stats.max_hp * Items.POTION_HEAL)
			stats.heal(amount)
			World.float_text(global_position + Vector3(0, 2.2, 0), "+%d" % amount, Color(0.4, 1, 0.4), 44, self)
			Audio.sfx("heal")
			inventory_changed.emit()
			return
	message.emit("No potions")


## Equips bag item i (the old item goes back to the bag); potions are drunk.
func equip(i: int) -> void:
	if i < 0 or i >= bag.size():
		return
	var it: Dictionary = bag[i]
	if it.slot == "potion":
		use_potion()
		return
	var p := Items.problem(it, cls, stats.level)
	if p != "":
		message.emit(p)
		return
	# Two hands: a two-handed weapon takes the off-hand item off (into the bag), an off-hand item
	# the two-handed weapon.
	var clash := ""
	if it.slot == "main" and Items.two_handed(String(it.kind)) and equipped.has("off"):
		clash = "off"
	elif it.slot == "off" and Items.two_handed(String(equipped.get("main", {}).get("kind", ""))):
		clash = "main"
	if clash != "" and bag.size() >= Items.BAG_SIZE and not equipped.has(it.slot):
		message.emit("Your bags are full.")
		return
	bag.remove_at(i)
	if equipped.has(it.slot):
		bag.insert(i, equipped[it.slot])
	if clash != "":
		bag.append(equipped[clash])
		equipped.erase(clash)
	equipped[it.slot] = it
	Audio.sfx("stat_up", -6.0)
	apply_gear()


func unequip(slot: String) -> void:
	if not equipped.has(slot):
		return
	if bag.size() >= Items.BAG_SIZE:
		message.emit("Your bags are full.")
		return
	bag.append(equipped[slot])
	equipped.erase(slot)
	apply_gear()


func near_merchant() -> bool:
	return Combatant.now() < merchant_until


func sell(i: int) -> void:
	if i < 0 or i >= bag.size() or not near_merchant():
		return
	var it: Dictionary = bag[i]
	var price := Items.sell_price(it)
	if it.slot == "potion" and int(it.count) > 1:
		it.count = int(it.count) - 1
	else:
		bag.remove_at(i)
	money += price
	Audio.sfx("coins", -4.0)
	inventory_changed.emit()


func buy(item: Dictionary) -> bool:
	var price := Items.buy_price(item, stats.level)
	if money < price:
		message.emit("Not enough money")
		return false
	if not add_item(item.duplicate(true)):
		return false
	money -= price
	Audio.sfx("coins", -4.0)
	inventory_changed.emit()
	return true


## Puts the class's starting items (Items.starter_kit) into the empty slots: a new hero, or a
## save from before there were starting items (once: kit_given).
var kit_given := 0                    ## the version of the starting kit given (KIT)
const KIT := 2                         ## 2: gloves, boots, trousers etc. joined the kits


func give_starter_kit() -> void:
	if kit_given >= KIT:
		return
	kit_given = KIT
	var kit := Items.starter_kit(cls)
	for slot in kit:
		if not equipped.has(slot):
			equipped[slot] = kit[slot]
	apply_gear()


## Puts the equipped items' stats onto the combat numbers and the weapons into the hands.
func apply_gear() -> void:
	stats.gear = Items.totals(equipped)
	stats.gear.erase("damage")                  # not a stat: the weapon's own (weapon_damage)
	stats.weapon_damage = float(Items.weapon_damage(equipped.get("main", {})))
	stats.recompute()
	if bear:
		stats.attack = stats.magic
		stats.weapon_mult = Rules.weapon_mult(Rules.weapon_ref(stats.level))
	_show_weapons()
	inventory_changed.emit()


## Head item armor type -> headgear model.
const HEADGEAR := {
	"plate": "res://assets/characters/warrior/helmet.glb", "mail": "res://assets/gear/coif.glb",
	"leather": "res://assets/gear/cowl.glb", "cloth": "res://assets/gear/hood.glb",
}

## Armor layers worn over the body (tools/pipeline/armor.py).
const LEG_LAYERS := {"plate": "res://assets/characters/warrior/plate_legs.glb"}
const SHOULDER_LAYERS := {"plate": "res://assets/characters/warrior/plate_shoulders.glb"}

## Weapon kind -> model. The class's own model wins when it is of the same kind (the warlock's
## green staff, the warrior's sword).
const WEAPON_MODELS := {
	"sword": "res://assets/characters/warrior/sword.glb", "axe": "res://assets/weapons/axe.glb",
	"mace": "res://assets/weapons/mace.glb", "dagger": "res://assets/weapons/dagger.glb",
	"staff": "res://assets/weapons/staff.glb",
	"greatsword": "res://assets/characters/warrior/sword.glb", "greataxe": "res://assets/weapons/axe.glb",
	"maul": "res://assets/weapons/mace.glb",
}
## Two-handed weapons are the one-handed models, larger (a 1H sword a bit smaller than the
## warrior's greatsword model).
const WEAPON_SIZE := {"sword": 0.85, "greatsword": 1.2, "greataxe": 1.62, "maul": 1.68}


## The hero's look follows what is worn (the starting items explain the class look): the main
## hand's weapon (empty hands without one; the class's own model when it is of the same kind),
## a bow, the off hand's shield or dagger, headgear by armor type, plate legs and pauldrons with
## plate pieces, a robe with a cloth chest.
func _show_weapons() -> void:
	var c: Dictionary = CLASSES[cls]
	var main: Dictionary = equipped.get("main", {})
	var kind := String(main.get("kind", ""))
	if WEAPON_MODELS.has(kind):
		var path: String = WEAPON_MODELS[kind]
		if c.has("weapon") and String(c.weapon).get_file().begins_with(kind):
			path = c.weapon
		model.equip_model("weapon", path, Vector3.ZERO if kind == "staff" else null, float(WEAPON_SIZE.get(kind, 1.0)))
		model.set_two_handed(Items.two_handed(kind))
	else:
		model.equip_model("weapon", "")
		model.set_two_handed(false)
	model.equip_model("bow", "res://assets/weapons/bow.glb" if kind == "bow" else "")
	var off_kind := String(equipped.get("off", {}).get("kind", ""))
	model.equip_model("shield", "res://assets/weapons/shield.glb" if off_kind == "shield" else "")
	model.equip_model("offhand", "res://assets/weapons/dagger.glb" if off_kind == "offdagger" else "")
	var head: Dictionary = equipped.get("head", {})
	var helm := String(HEADGEAR.get(head.get("kind", ""), "")) if not head.is_empty() else ""
	model.equip_model("helmet", helm if ResourceLoader.exists(helm) else "")
	var legs_kind := String(equipped.get("legs", {}).get("kind", ""))
	model.set_layer("legs", LEG_LAYERS.plate if legs_kind == "plate" else "")
	var chest_kind := String(equipped.get("chest", {}).get("kind", ""))
	model.set_layer("shoulders", SHOULDER_LAYERS.plate if chest_kind == "plate" else "")
	var robe: Array = ROBES.get(cls, ROBE_PLAIN)
	model.set_robe(robe[0] if chest_kind == "cloth" else Color.TRANSPARENT, robe[1], robe[2])
	# The class outfit shows where armor is worn; elsewhere the plain shirt, cloth trousers and
	# shoes under it. Every class has the base body's face (the outfits' baked heads came out
	# smeared: wrong skin tones, faces off their place).
	var pick := [0.0]
	for slot in ["chest", "hands", "legs", "feet"]:
		# Cloth handwraps and slippers: bare hands and the plain shoes (the casters' outfits
		# had coloured gloves and shoes that clashed with their robes).
		var it: Dictionary = equipped.get(slot, {})
		var cloth_extremity: bool = slot in ["hands", "feet"] and it.get("kind", "") == "cloth"
		pick.append(1.0 if not it.is_empty() and not cloth_extremity else 0.0)
	model.set_pick(pick)


# --- quests (scripts/items/quests.gd) ----------------------------------------------------

signal quests_changed


## Reached the inn of zone z: hand in finished quests (rewards), take on new ones.
func visit_inn(z: Zone) -> void:
	for q in quests.visit_inn(z):
		var gained := Quests.reward_xp(q, stats.level)
		var cash := Quests.reward_money(q)
		money += cash
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var item := Items.generate(int(q.level), "rare" if rng.randf() < 0.15 else "uncommon", cls, rng)
		add_item(item)
		message.emit("%s done: %d XP, %s, %s" % [q.title, gained, Items.money_text(cash), item.name])
		Audio.sfx("level_up", -4.0)
		_gain_xp(gained)
	if quests.posted:
		message.emit("New quests on the notice board of %s" % z.zone_name)
	quests_changed.emit()
	saved_point.emit()

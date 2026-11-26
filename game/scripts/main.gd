extends Node3D
## Builds the v1 world: environment, Grassland terrain, vegetation, the hero and the HUD.
##
## Command line (after `--`):
##   --seed N          world seed (default 1)
##   --shot <png>      save a screenshot after --frame frames (default 120), then quit
##   --frame N
##   --autowalk        the hero runs forward (test runs)
##   --sprint          ... and sprints (test runs)
##   --cam-yaw DEG     camera angle around the hero (test runs)
##   --zoom M          camera distance (2–15, default 6)
##   --class C         warrior (default), mage, rogue, priest, paladin, warlock, hunter, shaman, druid
##   --level N         start at level N (test the warrior's later abilities)
##   --no-enemies      an empty world
##   --mute            no sound
##   --lineup          test: all classes side by side
##   --kill-at F       test: the nearest enemy dies at frame F
##   --swing CLIP      test: play a one-shot (attack1, strike, hit, cast...) every 50 frames
##   --burst N         test: also save N pictures every --burst-step frames before the shot
##   --fight KIND      test: start next to the nearest group of KIND and fight automatically
##   --strip           test: no armor worn (the plain clothes under it)
##   --nohelp          the HUD without the controls list (screenshots)
##   --slot6 ID        test: put ability ID on key 6 (with --press 6)
##   --nobot           test (--fight): target the group but don't fight (use --press)
##   --hold M          test (--fight): the group stands stunned, the hero M m away
##   --gear RARITY     test: wear a full set of generated gear of the hero's level
##   --whirl           test: Whirlwind at frame --press-at (default 100), full rage (--level 12)
##   --chase-from X,Z  test: the nearest enemy starts at X,Z and chases the hero (pathfinding)
##   --strafe-at F     test: from frame F strafe left (ending a Whirlwind first)
##   --pos X,Z         start position (default: in front of the plaza)
##   --hill-chase      test: on a slope near the start the nearest enemy chases the hero up it
##                     (--hill-min/--hill-max: the slope as normal.y; --hill-charge: the hero
##                     below charges the enemy up the hill); prints distance and heights
##   --cam-pitch DEG   test: camera pitch (positive looks up; the moon: --time 0.02 --cam-pitch 35)
##   --lineup-move S   test (--lineup): every class plays gait S (run, walk) on the spot, side-on
##   --to-north        test: run through the start zone's north crossing
##   --zone X,Z        start in that zone of the grid (e.g. 0,-1: north of the start)
##   --bench SECONDS   run forward with vsync off and print the average FPS, then quit
## Quality (defaults tuned for the Vega 8 laptop, see design/tech-stack.md):
##   --scale F         3D render scale with FSR upscaling (default 0.75; 1.0 = native)
##   --shadow-dist M   sun shadow distance (default 45)
##   --view M          view range of trees, bushes and rocks (default 160)

var args := {}
var player: Player
var hud: Hud
var _frame := 0
var _fighting := false
var _min_hp := 1.0            ## test fights: the hero's lowest health (fraction)
var _chaser: Enemy                ## test (--chase-from)
var _chase_start := 0.0
var _taken := {}              ## test fights: source -> [damage, hits, biggest hit]; "healed"
var zones: ZoneManager
var _env: Environment
var _menu: GameMenu
var _sky: ProceduralSkyMaterial
var _daynight: DayNight
var _bags: Inventory
var _sun: DirectionalLight3D
var _last_save := 0.0
var _saved_pos := Vector3.ZERO
var _bench_start := -1.0
var _bench_frames := 0


func _ready() -> void:
	_parse_args()
	_setup_input()
	Enemy.steering = not args.has("no-steer")
	if args.has("staff-grip"):          # test: "x,y,z,rx,ry,rz" (the staff's hold)
		var g: PackedStringArray = String(args["staff-grip"]).split(",")
		Humanoid.STAFF_GRIP = Vector3(float(g[0]), float(g[1]), float(g[2]))
		Humanoid.STAFF_TILT = Vector3(float(g[3]), float(g[4]), float(g[5]))
	if args.has("whirl-at"):
		CharAnimator.WHIRL_AT = float(args["whirl-at"])     # test: the Whirlwind pose's frame
	var seed := int(args.get("seed", Game.seed))
	Game.seed = seed
	_setup_environment()
	_setup_quality()
	var audio := Audio.new()
	audio.name = "Audio"
	add_child(audio)
	if args.has("shot") or args.has("bench") or args.has("mute"):
		AudioServer.set_bus_mute(0, true)     # test runs are silent

	World.root = self
	World.enemies.clear()
	var vq: Dictionary = GameMenu.QUALITY[String(args.get("quality", GameMenu.load_quality()))]
	World.view_range = float(args.get("view", vq.view))
	zones = ZoneManager.new()
	zones.name = "Zones"
	zones.world_seed = seed
	zones.with_enemies = not args.has("no-enemies")
	add_child(zones)
	World.zones = zones

	# The start zone: chosen on the title screen (a new game), from the save, or a test's --start.
	if args.has("start"):
		Game.home = ZoneTypes.nearest(String(args.start), seed)
	var hm: Array = Game.loaded.get("home", [])
	if hm.size() == 2:
		Game.home = Vector2i(int(hm[0]), int(hm[1]))
	elif not Game.loaded.is_empty():
		Game.home = Vector2i.ZERO          # saves from before start zones existed
	ZoneTypes.home = Game.home
	# Where the hero starts: in front of the start zone's inn, a saved position, or a test spot.
	var start := Vector3(Game.home.x * Terrain.SIZE, 0, Game.home.y * Terrain.SIZE - 16)
	if args.has("zone"):
		var zc: PackedStringArray = String(args.zone).split(",")
		start += Vector3(float(zc[0]) * Terrain.SIZE, 0, float(zc[1]) * Terrain.SIZE)
	if args.has("pos"):
		var p: PackedStringArray = String(args.pos).split(",")
		start = Vector3(float(p[0]), 0, float(p[1]))
	var sp: Array = Game.loaded.get("pos", [])
	if sp.size() == 3:
		start = Vector3(sp[0], 0, sp[2])
	# Our own loading screen first (world generation blocks for a second or two): the picture of
	# the zone that is loading, and "Loading...".
	var loading := _loading_screen(ZoneTypes.type_at(Vector2i(roundi(start.x / Terrain.SIZE), roundi(start.z / Terrain.SIZE)), seed))
	add_child(loading)
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var first := zones.ensure(zones.cell_of(start))
	print("world generated in %d ms: %s, %d lakes" % [Time.get_ticks_msec() - t0, first.scatter.counts, first.terrain.lakes.size()])
	if args.has("lake") and not first.terrain.lakes.is_empty():
		var l: Dictionary = first.terrain.lakes[0]
		var q: Vector2 = l.center + Vector2(float(l.radius) + 8.0, 0)
		start = Vector3(q.x + first.position.x, 0, q.y + first.position.z)

	var face := PI
	if args.has("landmark") and not first.landmarks.is_empty():
		# Test: 75 m in front of the zone's first pyramid group, looking at it.
		var c: Vector3 = first.landmarks[0]
		var dir := Vector3(-c.x, 0, -c.z).normalized()
		var at := c + dir * 75.0
		start = Vector3(at.x + first.position.x, 0, at.z + first.position.z)
		face = atan2(dir.x, dir.z)
	if args.has("chest") and not first.chests.is_empty():
		var cp := first.chests[clampi(int(args.chest) if args.chest is String else 0, 0, first.chests.size() - 1)].position + Vector3(5, 0, 0)
		start = Vector3(cp.x + first.position.x, 0, cp.z + first.position.z)
		face = PI / 2                 # facing -X, toward the chest
	if args.has("to-north"):
		# Test: 40 m in front of the start zone's north crossing, running north through it.
		for c in first.terrain.crossings:
			if c.y < -100.0:
				start = Vector3(c.x + first.position.x, 0, c.y + 40.0 + first.position.z)
				face = 0.0
				args["autowalk"] = true

	player = Player.new()
	player.name = "Player"
	player.cls = String(args.get("class", Game.cls))
	add_child(player)
	World.player = player
	# Ground clutter, amount by the graphics quality (test runs: --quality Low|Medium|High).
	var cq: Array = GameMenu.QUALITY[String(args.get("quality", GameMenu.load_quality()))].clutter
	Clutter.radius = float(cq[0])
	Clutter.density = float(cq[1])
	add_child(Clutter.new())
	if args.has("level"):
		player.set_level(int(args.level))
	if args.has("gear"):
		# Test: a full set of generated gear of the hero's level and this rarity.
		var gr := RandomNumberGenerator.new()
		for slot in ["head", "chest", "legs", "hands", "feet", "main", "off", "neck", "ring"]:
			var it := Items.make(slot, player.stats.level, String(args.gear), player.cls, gr)
			if Items.problem(it, player.cls, player.stats.level) == "":
				player.add_item(it)
				player.equip(player.bag.size() - 1)
	player.global_position = Vector3(start.x, World.height_at(start.x, start.z) + 0.2, start.z)
	player.checkpoint = player.global_position
	player.rotation.y = face          # facing the plaza (south)
	_apply_save(Game.loaded)
	if args.has("strip"):
		# Test: all armor off (the plain clothes under it); weapons stay.
		for slot in ["head", "chest", "legs", "hands", "feet"]:
			player.equipped.erase(slot)
		player.apply_gear()
	player.leveled_up.connect(func(_l): Game.write_save(player))
	player.saved_point.connect(func(): Game.write_save(player))
	print("enemies: %d" % World.enemies.size())
	player.auto_forward = args.has("autowalk")
	player.auto_sprint = args.has("sprint")
	if args.has("cam-yaw"):
		player.cam_yaw = deg_to_rad(float(args["cam-yaw"]))
	if args.has("zoom"):
		player.zoom = float(args.zoom)
	if args.has("cam-pitch"):
		player.cam_pitch = deg_to_rad(float(args["cam-pitch"]))     # test: positive looks up
	player.camera.current = true
	World.set_view(World.view_range, float(vq.far))
	_daynight.apply()

	hud = Hud.new()
	add_child(hud)
	hud.player = player
	if args.has("fight"):
		_setup_fight(String(args.fight))
	if args.has("creatures"):
		_creature_lineup(String(args.creatures), float(args.get("creature-t", -1)))
	if args.has("lineup"):
		_lineup()
	if args.has("heads"):
		_heads()
	if args.has("heads-goblin"):
		_heads_goblin()
	player.message.connect(hud.show_message)
	player.hint.connect(hud.show_hint)
	if args.has("nohud"):
		hud.visible = false            # test: clean pictures (title background)
	if args.has("nohelp"):
		hud._help.visible = false      # test: screenshots with the HUD but not the controls
		hud._info.visible = false      # nor the frame rate and position
	_bags = Inventory.new()
	_bags.player = player
	add_child(_bags)
	if args.has("loot"):
		# Test: fill the bag with random drops of the hero's level.
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in int(args.loot):
			player.add_item(Items.generate(player.stats.level, Items.roll_rarity("elite", rng), player.cls, rng))
		if args.has("equip"):
			for i in range(player.bag.size() - 1, -1, -1):
				if player.bag[i].slot != "potion" and not player.equipped.has(player.bag[i].slot):
					player.equip(i)
	if args.has("head"):
		# Test: equip a generated head item of this armor type.
		var hr := RandomNumberGenerator.new()
		for i in 300:
			var h := Items.make("head", player.stats.level, "common", "", hr)
			if h.kind == args.head:
				player.add_item(h)
				player.bag.back().ilvl = 1
				player.equip(player.bag.size() - 1)
				break
	if args.has("weapon"):
		# Test: equip a generated main-hand weapon of this kind.
		var wr := RandomNumberGenerator.new()
		for i in 200:
			var w := Items.make("main", player.stats.level, "uncommon", player.cls, wr)
			if w.kind == args.weapon:
				player.add_item(w)
				player.equip(player.bag.size() - 1)
				break
	if args.has("bags"):
		_bags.toggle()
	var book := SpellBook.new()
	book.player = player
	add_child(book)
	if args.has("spellbook"):
		book.visible = true            # test: show the abilities menu (not paused, so the shot runs)
		book._refresh()
	var wmap := WorldMap.new()
	wmap.player = player
	wmap.seed = Game.seed
	add_child(wmap)
	if args.has("time"):
		_daynight.time = float(args.time)     # test: time of day 0..1 (0.5 noon)
		_daynight.enabled = true
	elif args.has("shot") or args.has("bench"):
		_daynight.enabled = false             # tests: the fixed morning light, comparable shots
	if args.has("map"):
		wmap.visible = true          # test: open the map with the cells around the start explored
		for dz in range(-2, 3):
			for dx in range(-1, 3):
				player.visited[Quests.key_of(Vector2i(dx, dz))] = true
	if args.has("merchant"):
		player.merchant_until = 1e9
	if args.has("quests-done"):
		# Test: take on the start inn's quests and finish them; the inn visit hands them in.
		player.quests.visit_inn(zones.zone_at(Vector3.ZERO))
		for q in player.quests.active:
			q.have = q.need
	_menu = GameMenu.new()
	_menu.player = player
	_menu.sun = _sun
	_menu.daynight = _daynight
	add_child(_menu)
	if args.has("menu"):
		_menu.visible = true          # test: show the menu (not paused, so the screenshot runs)
		_menu._options = String(args.menu) == "options"
		_menu._refresh()
	zones.streaming = not args.has("no-stream")
	zones.entered_zone.connect(_on_entered_zone)
	zones.loading.connect(hud.show_message)
	zones.update(player.global_position)
	if not args.has("loading"):
		loading.queue_free()      # test: --loading keeps the loading screen up for a screenshot


## Full-screen loading picture of the zone type (the title screen's), with "Loading..." on it.
func _loading_screen(type: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var path := "res://assets/ui/title_%s.jpg" % type
	if not ResourceLoader.exists(path):
		path = "res://assets/ui/title_bg.jpg"
	var pic := TextureRect.new()
	pic.texture = load(path)
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	layer.add_child(pic)
	var text := Label.new()
	text.text = "Loading..."
	text.add_theme_font_size_override("font_size", 40)
	text.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	text.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02))
	text.add_theme_constant_override("outline_size", 10)
	text.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	text.offset_top = -110
	text.offset_bottom = -60
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(text)
	return layer


## Test: all classes side by side in front of the hero, facing the camera.
## Test: the headgear in a row facing the camera (hood over a robe, hood, coif, leather cap,
## plate helm); --heads-turn DEG turns them (90: from the side).
func _heads() -> void:
	var looks := [["mage", "hood"], ["rogue", "hood"], ["paladin", "coif"], ["hunter", "cowl"], ["warrior", "helmet"]]
	for i in looks.size():
		var h := Humanoid.new()
		add_child(h)
		var look := Player.look_of(looks[i][0])
		look.erase("helmet")
		h.build(look)
		var hp: String = Player.HEADGEAR.get({"hood": "cloth", "coif": "mail", "cowl": "leather", "helmet": "plate"}[looks[i][1]])
		h.equip_model("helmet", hp)
		var x := (i - (looks.size() - 1) / 2.0) * 0.9
		var p := player.global_position + Vector3(x, 0, 2.2)
		h.global_position = Vector3(p.x, World.height_at(p.x, p.z), p.z)
		h.rotation.y = PI + deg_to_rad(float(args.get("heads-turn", 0)))
	player.visible = false


## Test: a goblin from the front, the side and behind (its build, head and ears).
func _heads_goblin() -> void:
	var d: Dictionary = EnemyData.get_kind("goblin")
	for i in 3:
		var h := Humanoid.new()
		add_child(h)
		var cfg := {"pick": [1, 1, 1, 1, 1], "outfit": "res://assets/characters/goblin/goblin"}
		for k in ["tatter", "skin", "legs", "head_size", "head_egg", "ears", "build", "fur", "fur_color", "skin_hands", "head_tint"]:
			if d.has(k):
				cfg[k] = d[k]
		if d.has("head_tint"):
			cfg.pick = [0, 1, 1, 1, 1]
		h.build(cfg)
		h.scale = Vector3.ONE * float(d.get("scale", 1.0)) * (d.get("build", Vector3.ONE) as Vector3)
		var p := player.global_position + Vector3((i - 1) * 0.9, 0, 1.6)
		# Raised to the camera's height (--heads-goblin-lift m): the faces at eye level.
		h.global_position = Vector3(p.x, World.height_at(p.x, p.z) + float(args.get("heads-goblin-lift", 0.0)), p.z)
		h.rotation.y = [0.0, PI / 2, PI][i]
	player.visible = false


## The ground's normal at x, z from height differences (tests).
func _ground_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := World.height_at(x + e, z) - World.height_at(x - e, z)
	var dz := World.height_at(x, z + e) - World.height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func _lineup() -> void:
	var names := Player.CLASSES.keys()
	for i in names.size():
		var c: Dictionary = Player.CLASSES[names[i]]
		var h := Humanoid.new()
		add_child(h)
		var look := {"outfit": c.outfit, "pick": c.pick}
		for k in ["weapon", "offhand", "shield", "bow", "weapon_rot"]:
			if c.has(k):
				look[k] = c[k]
		if c.helmet:
			look["helmet"] = "res://assets/characters/warrior/helmet.glb"
		h.build(look)
		var x := (i - (names.size() - 1) / 2.0) * 1.3
		var p := player.global_position + Vector3(x, 0, 0)
		h.global_position = Vector3(p.x, World.height_at(p.x, p.z), p.z)
		h.rotation.y = PI       # facing south, toward the camera in front of the hero
		if args.has("lineup-move"):
			# Test: a gait on the spot, side-on (the sword arm toward the camera).
			h.anim.set_move(String(args["lineup-move"]))
			h.rotation.y = PI / 2
	player.visible = false


## Test: every rigged creature in a row in front of the hero playing `clip` (held at time t
## when t >= 0); "walkattack" walks them on the spot through the AnimationTree and attacks.
func _creature_lineup(clip: String, t: float) -> void:
	var names := ["wolf", "direwolf", "snowwolf", "boar", "bear", "crab", "spider", "scorpion", "scarab", "cobra", "sandsnake"]
	if args.has("creature-only"):
		names = String(args["creature-only"]).split(",")
	var fwd := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	for i in names.size():
		var path := "res://assets/creatures/%s_rig.glb" % names[i]
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = load(path).instantiate()
		Enemy._matte(n, path)
		add_child(n)
		var p := player.global_position + fwd * ((9.0 + (i % 2) * 3.0) if names.size() > 3 else 5.0) + right * (i - (names.size() - 1) / 2.0) * 2.2
		n.global_position = Vector3(p.x, World.height_at(p.x, p.z), p.z)
		n.rotation.y = player.rotation.y + PI * 0.75   # three-quarter view, facing the camera's left
		var ca := CreatureAnim.attach(n, path, clip == "walkattack")
		if ca == null:
			continue
		if clip == "walkattack":
			# Walking on the spot and attacking every 1.6 s: the legs must keep stepping.
			ca.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
			ca.move(float(ca.speeds.walk))
			var tm := Timer.new()
			tm.wait_time = 1.6
			tm.autostart = true
			tm.timeout.connect(ca.shot.bind("attack"))
			n.add_child(tm)
			continue
		ca.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		ca.player.play(clip)
		if t >= 0.0:
			ca.player.seek(minf(t, ca.player.current_animation_length), true)
			ca.player.pause()
	player.visible = false


## Test scenario: put the hero 7 m from the group of `kind` nearest to it and let it fight.
func _setup_fight(kind: String) -> void:
	var best: Enemy = null
	for e in World.enemies:
		if (e.kind == kind or (kind == "champion" and e.champion != "")) and (best == null or e.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = e
	if best == null:
		var kinds := {}
		for e in World.enemies:
			kinds[e.kind] = true
		print("FIGHT no %s here; kinds: %s" % [kind, kinds.keys()])
		return
	var p := best.global_position + Vector3(float(args.get("hold", 7.0)), 0, 0)
	if args.has("hold"):
		# Test: the group stays put (stunned) with the hero --hold m away (arrows in flight).
		for e in World.enemies:
			if e.kind == best.kind and e.global_position.distance_to(best.global_position) < 8.0:
				e.stats.stun_until = Combatant.now() + 120.0
	player.global_position = Vector3(p.x, World.height_at(p.x, p.z) + 0.2, p.z)
	player.look_at(Vector3(best.global_position.x, player.global_position.y, best.global_position.z))
	player.rotation.x = 0
	if args.has("notarget"):
		return              # test: the hero just stands there; does it target the attacker?
	player.set_target(best)
	if args.has("nobot"):
		return              # test: targeted, but the hero only does what --press says
	_fighting = true
	player.stats.damaged.connect(func(amount: int, _crit: bool, src: Combatant) -> void:
		var k := src.display_name if src else "ticks"
		_taken[k] = _taken.get(k, [0, 0, 0])
		_taken[k][0] += amount
		_taken[k][1] += 1
		_taken[k][2] = maxi(_taken[k][2], amount))
	player.stats.healed.connect(func(amount: int) -> void: _taken["healed"] = int(_taken.get("healed", 0)) + amount)
	var group := World.enemies.filter(func(e): return e.kind == best.kind and e.global_position.distance_to(best.global_position) < 8.0)
	print("FIGHT %s levels %s, hero level %d hp %d def %.0f" % [best.kind, group.map(func(e): return e.stats.level), player.stats.level, player.stats.max_hp, player.stats.defense])


func _fight_bot() -> void:
	if not _fighting or player.stats.dead:
		return
	_min_hp = minf(_min_hp, float(player.stats.hp) / player.stats.max_hp)
	if player.stats.hp < player.stats.max_hp * 0.35 and player.potion_count() > 0 and Combatant.now() >= player.potion_ready:
		player.use_potion()
	if player.target == null:
		player._tab_target()
	if player.target:
		var d := player.target.global_position - player.global_position
		player.rotation.y = atan2(-d.x, -d.z)
		var casters: Array = Player.CASTERS + ["hunter"]
		var reach := 24.0 if (player.cls in casters and not player.bear) else 2.2
		player.auto_forward = Vector2(d.x, d.z).length() > reach and player.casting.is_empty()
		var orders := {"warrior": [5, 2, 4, 3, 6, 1], "mage": [3, 4, 5, 2, 1], "rogue": [5, 4, 6, 1],
			"priest": [4, 5, 6, 1], "paladin": [6, 4, 2, 3, 1], "warlock": [3, 2, 5, 6, 4, 1],
			"hunter": [3, 4, 2, 5, 1], "shaman": [2, 5, 6, 3, 1], "druid": [6, 3, 4, 2, 5, 1]}
		var order: Array = orders.get(player.cls, [1])
		for key in order:
			if player.bear and key == 6:
				continue
			if player.ability_problem(player.ability_by_key(key)) == "":
				if (player.cls == "mage" and key != 3) or key != (4 if player.cls == "warrior" else 3) or World.enemies.filter(func(e): return not e.stats.dead and e.global_position.distance_to(player.global_position) < 8.0).size() >= 2:
					player.use_ability(key)
					break
		player.auto_attacking = not (player.cls in Player.CASTERS) or player.bear
	else:
		player.auto_forward = false


func _on_entered_zone(z: Zone) -> void:
	player.visited[Quests.key_of(z.cell)] = true
	# Quests belong to their zone: leaving it drops them (its board posts them again on return).
	var key := Quests.key_of(z.cell)
	var gone: Array = player.quests.active.filter(func(q): return q.zone != key)
	if not gone.is_empty():
		for q in gone:
			player.quests.active.erase(q)
		player.message.emit("Left %s: %d quest%s dropped." % [String(gone[0].get("zone_name", "the zone")), gone.size(), "" if gone.size() == 1 else "s"])
		player.quests_changed.emit()
	hud.show_zone(z.zone_name, "%s — difficulty %d" % [z.info.name, z.difficulty])
	_daynight.set_zone(z.info)
	if Audio.instance:
		Audio.instance.zone_music = z.info.music
		Audio.instance.village_music = z.info.village_music


func _apply_save(d: Dictionary) -> void:
	if d.is_empty():
		var start := Items.POTION.duplicate(true)
		start.count = 3
		player.add_item(start)
		player.give_starter_kit()
		return
	player.set_level(int(d.get("level", 1)))
	var bag = d.get("bag", [])
	player.bag = bag if bag is Array else []
	var eq = d.get("equipped", {})
	player.equipped = eq if eq is Dictionary else {}
	# Tips seen; a save from before tips counts as seen them all (it's no new player).
	var tips = d.get("tips", ["camp"])
	for k in (tips if tips is Array else []):
		player.tips_shown[String(k)] = true
	var kit = d.get("kit", 0)
	player.kit_given = (1 if kit else 0) if kit is bool else int(kit)
	player.give_starter_kit()          # saves from before the starting items: into empty slots
	player.apply_gear()
	_daynight.time = float(d.get("time", 0.3))
	var oc = d.get("chests", [])
	if oc is Array:
		for k in oc:
			player.opened_chests[String(k)] = true
	var vis = d.get("visited", [])
	if vis is Array:
		for k in vis:
			player.visited[String(k)] = true
	var qs = d.get("quests", {})
	if qs is Dictionary:
		player.quests.load_save(qs)
	var lo = d.get("loadout", [])
	if lo is Array:
		player.set_loadout(lo)
	var pl = d.get("passives", null)
	if pl is Array:
		player.set_passive_loadout(pl)
	player.xp = int(d.get("xp", 0))
	player.money = int(d.get("money", 0))
	player.stats.hp = clampi(int(d.get("hp", player.stats.max_hp)), 1, player.stats.max_hp)
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		# Never under the ground (a save from an older version, whose terrain was different).
		player.global_position = Vector3(p[0], maxf(p[1], World.height_at(p[0], p[2])) + 0.3, p[2])
	player.rotation.y = float(d.get("yaw", PI))
	var c: Array = d.get("checkpoint", [])
	if c.size() == 3:
		player.checkpoint = Vector3(c[0], c[1], c[2])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if player and not args.has("shot") and not args.has("bench"):
			Game.write_save(player)
		Game.quit(get_tree())


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = a[i].trim_prefix("--")
		if i + 1 < a.size() and not a[i + 1].begins_with("--"):
			args[k] = a[i + 1]
			i += 2
		else:
			args[k] = true
			i += 1


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"turn_left": [KEY_A, KEY_LEFT], "turn_right": [KEY_D, KEY_RIGHT],
		"strafe_left": [KEY_Q], "strafe_right": [KEY_E],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "menu": [KEY_ESCAPE], "help": [KEY_F1],
		"target_next": [KEY_TAB], "auto_attack": [KEY_F], "bags": [KEY_B, KEY_I], "map": [KEY_M], "spellbook": [KEY_N], "camp": [KEY_C], "autorun": [KEY_F2],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.5, 0.78)
	sm.sky_horizon_color = Color(0.7, 0.78, 0.86)
	sm.ground_bottom_color = Color(0.25, 0.3, 0.2)
	sm.ground_horizon_color = Color(0.6, 0.66, 0.6)
	sky.sky_material = sm
	_sky = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.76, 0.85)
	env.fog_density = 0.002
	env.fog_aerial_perspective = 0.35
	# Color grade: generated textures and the filmic curve come out greyish; a little more
	# saturation and contrast gives the brighter, painted look of the older MMOs.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.06
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.88)
	var quality: Dictionary = GameMenu.QUALITY[String(args.get("quality", GameMenu.load_quality()))]
	sun.shadow_enabled = quality.get("shadows", true)   # Low: none, blob shadows under units instead
	BlobShadow.enabled = not sun.shadow_enabled
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = float(args.get("shadow-dist", GameMenu.QUALITY[GameMenu.load_quality()].shadow))
	_sun = sun
	_daynight = DayNight.new()
	_daynight.name = "DayNight"
	_daynight.sun = sun
	_daynight.env = env
	_daynight.sky = _sky
	_daynight.enabled = GameMenu.load_daynight()
	add_child(_daynight)
	add_child(sun)


func _setup_quality() -> void:
	var vp := get_viewport()
	var scale := float(args.get("scale", GameMenu.QUALITY[GameMenu.load_quality()].scale))
	vp.scaling_3d_scale = scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	if args.has("bench") or args.has("shot"):
		# Hidden test windows get no frame callbacks; without vsync they run at full speed.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if args.has("bench"):
		args["autowalk"] = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if player.target:
			player.set_target(null)
		elif args.has("shot") or args.has("bench"):
			get_tree().quit()
		elif not _menu.visible:
			_menu.open()


func _process(_dt: float) -> void:
	_frame += 1
	if args.has("jump") and _frame == 30 and player.is_on_floor():
		player.velocity.y = Player.JUMP_VELOCITY      # test: a jump (screenshot it mid-air)
	BushEyes.test = args.has("eyes")
	if args.has("keys") and _frame >= 40 and (_frame - 40) % 4 == 0:
		# Test: press keys one after another (--keys down,down,space).
		var list: PackedStringArray = String(args["keys"]).split(",")
		var i := (_frame - 40) / 4
		if i < list.size():
			var ev := InputEventKey.new()
			ev.keycode = {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "space": KEY_SPACE,
				"esc": KEY_ESCAPE, "p": KEY_P}.get(list[i], KEY_NONE)
			ev.physical_keycode = ev.keycode
			ev.pressed = true
			Input.parse_input_event(ev)
	if args.has("chase-from") and player:
		# Test: an enemy starts at X,Z (behind an obstacle) and chases the hero standing still;
		# prints when it arrives (pathfinding).
		if _frame == 60:
			var c: PackedStringArray = String(args["chase-from"]).split(",")
			var near: Enemy = null
			for e in World.enemies:
				if near == null or e.global_position.distance_to(player.global_position) < near.global_position.distance_to(player.global_position):
					near = e
			_chaser = near
			var at := Vector3(float(c[0]), 0, float(c[1]))
			near.global_position = Vector3(at.x, World.height_at(at.x, at.z) + 0.3, at.z)
			near.home = near.global_position
			near.stats.slow_until = 0.0
			near.engage()
			_chase_start = Time.get_ticks_msec() / 1000.0
		elif _chaser and _chase_start > 0.0 and _chaser.global_position.distance_to(player.global_position) < 3.0:
			print("CHASE reached in %.1f s" % (Time.get_ticks_msec() / 1000.0 - _chase_start))
			_chase_start = -1.0
	if args.has("hill-chase") and player:
		# Test: on a slope near the start (25-35 degrees), the hero up the hill, the nearest enemy
		# below it chasing; prints distance and heights each second (enemies climbing hills).
		if _frame == 40:
			var best := Vector3.INF
			for r in range(20, 160, 4):
				for k in 24:
					var q := player.global_position + Vector3(cos(TAU * k / 24), 0, sin(TAU * k / 24)) * r
					var nrm := _ground_normal(q.x, q.z)
					if nrm.y > float(args.get("hill-min", 0.82)) and nrm.y < float(args.get("hill-max", 0.9)):
						best = q
						break
				if best != Vector3.INF:
					break
			if best == Vector3.INF:
				print("HILL none found")
			else:
				var n := _ground_normal(best.x, best.z)
				var downhill := Vector3(n.x, 0, n.z).normalized()
				var top := best - downhill * 7.0
				var low := best + downhill * 7.0
				if args.has("hill-charge"):
					var tmp := top
					top = low + downhill * 6.0          # the hero below, the enemy up the hill (charge)
					low = tmp
				player.global_position = Vector3(top.x, World.height_at(top.x, top.z) + 0.3, top.z)
				var near: Enemy = null
				for e in World.enemies:
					if near == null or e.global_position.distance_to(player.global_position) < near.global_position.distance_to(player.global_position):
						near = e
				_chaser = near
				near.global_position = Vector3(low.x, World.height_at(low.x, low.z) + 0.3, low.z)
				near.home = near.global_position
				if args.has("hill-charge"):
					near.stats.stun_until = Combatant.now() + 1.0
					player.set_target(near)
					player.rotation.y = atan2(-(near.global_position.x - player.global_position.x), -(near.global_position.z - player.global_position.z))
				else:
					near.engage()
				print("HILL slope %.0f deg, hero %.1f m above the enemy" % [rad_to_deg(acos(n.y)), player.global_position.y - near.global_position.y])
		elif args.has("hill-charge") and _chaser and _frame == 45:
			print("HILL charge: ", player.ability_problem(player.ability_by_id("charge")))
			player.use_ability(player.slot_of("charge") + 1)
		elif _chaser and _frame > 40 and _frame % 25 == 0:
			print("HILL f%d dist %.1f enemy y %.2f hero y %.2f" % [_frame, _chaser.global_position.distance_to(player.global_position), _chaser.global_position.y, player.global_position.y])
	if args.has("strafe-at") and player and _frame >= int(args["strafe-at"]):
		# Test: Whirlwind (if on) ends, then the hero strafes left.
		if _frame == int(args["strafe-at"]):
			player._stop_whirl()
		Input.action_press("strafe_left")
	if args.has("turn") and player:
		player.rotation.y += 0.05                   # test: turning on the spot
	if args.has("flee") and _frame == 200:
		_fighting = false                  # test: run away so the enemy evades (leash)
		var away := player.global_position + Vector3(70, 0, 0)
		player.global_position = Vector3(away.x, World.height_at(away.x, away.z) + 0.3, away.z)
	if args.has("menu-click") and _frame == int(args["menu-click"]):
		# Test: a click at 30% of the music bar (the second volume bar).
		var bars := _menu.find_children("*", "Control", true, false).filter(func(c): return c.custom_minimum_size.x == GameMenu.BAR_W)
		if bars.size() >= 2:
			var r: Rect2 = bars[1].get_global_rect()
			print("MUSIC before ", GameMenu.load_volume("music"))
			for down in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = down
				ev.position = r.position + r.size * Vector2(0.3, 0.5)
				ev.global_position = ev.position
				get_viewport().push_input(ev)
			print("MUSIC after ", GameMenu.load_volume("music"))
	if args.has("sink-at") and player and _frame == int(args["sink-at"]):
		player.global_position.y -= 20.0           # test: under the ground (an old save)
	if args.has("sink-at") and player and _frame == int(args["sink-at"]) + 30:
		print("SINK above ground: ", player.global_position.y >= World.height_at(player.global_position.x, player.global_position.z) - 0.1)
	if args.has("kill-at") and player and _frame == int(args["kill-at"]):
		# Test: the nearest enemy dies (death animations).
		var near: Enemy = null
		for e in World.enemies:
			if not e.stats.dead and (near == null or e.global_position.distance_to(player.global_position) < near.global_position.distance_to(player.global_position)):
				near = e
		if near:
			near.stats.take_damage(near.stats.hp + 1, false, player.stats)
	if args.has("kill-at") and player and _frame == int(args["kill-at"]) + 110:
		for e in World.enemies:
			if e.stats.dead and e.global_position.distance_to(player.global_position) < 30.0:
				print("CORPSE %s visible %s scale %s in view %s" % [e.kind, e.visible, e._model.scale, Enemy._in_view(e.global_position)])
	if args.has("swing") and player and _frame >= 60 and _frame % 50 == 10:
		player.model.anim.play_shot(String(args.swing))   # test: a one-shot clip on the spot
	if args.has("whirl") and player and _frame == int(args.get("press-at", 100)):
		# Test: Whirlwind on slot 6 with full rage.
		player.loadout[5] = "whirlwind"
		player.loadout_changed.emit()
		player.stats.rage = 100.0
		player.gcd_until = 0.0
		player.use_ability(6)
	if args.has("slot6") and _frame == 50:
		player.loadout[5] = String(args.slot6)       # test: an ability on key 6 (--press 6)
		player.loadout_changed.emit()
	if args.has("press") and _frame == int(args.get("press-at", 450)):
		player.use_ability(int(args.press))           # test: press an ability key
	if args.has("camp") and _frame == 30:
		player.stats.hp = player.stats.max_hp / 4                 # test: rest at a fire
		player.toggle_camp()
		if args.has("dot"):
			player.stats.add_dot("poison", 8.0, 1.0 / 64.0, null)   # test: poisoned while resting
	_fight_bot()
	if _frame % 20 == 0 and Audio.instance:
		Audio.instance.update_music(player)
	if _frame % 30 == 0 and zones and player:
		zones.update(player.global_position)
	# Autosave the position at most every 30 s, and only when the hero moved.
	if player and not args.has("shot") and not args.has("bench"):
		var t := Time.get_ticks_msec() / 1000.0
		if t - _last_save > 30.0 and player.global_position.distance_to(_saved_pos) > 2.0 and not player.stats.dead:
			_last_save = t
			_saved_pos = player.global_position
			Game.write_save(player)
	if args.has("trace") and player and _frame % 10 == 0:
		print("trace f%d pos %s vel %s floor %s" % [_frame, player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), player.velocity.snapped(Vector3(0.1, 0.1, 0.1)), player.is_on_floor()])
	if args.has("bench") and player != null:
		var now := Time.get_ticks_msec() / 1000.0
		if _bench_start < 0.0 and _frame > 30:
			_bench_start = now
			_bench_frames = 0
		elif _bench_start >= 0.0:
			_bench_frames += 1
			if now - _bench_start >= float(args.bench):
				print("BENCH avg_fps=%.1f frames=%d seconds=%.1f renderer=%s" % [_bench_frames / (now - _bench_start), _bench_frames, now - _bench_start, ProjectSettings.get_setting("rendering/renderer/rendering_method")])
				get_tree().quit()
	# Test: --burst N --burst-step K also saves N pictures every K frames before the shot
	# (out_0.png ...), for checking animations in the game.
	if args.has("shot") and args.has("burst"):
		var k := int(args.get("burst-step", 3))
		var i := (_frame - int(args.get("frame", 120))) / k + int(args.burst)
		if i >= 0 and i < int(args.burst) and (_frame - int(args.get("frame", 120))) % k == 0:
			get_viewport().get_texture().get_image().save_png(String(args.shot).replace(".png", "_%d.png" % i))
	if args.has("shot") and _frame == int(args.get("frame", 120)):
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(args.shot))
		if args.has("save-on-exit"):
			Game.write_save(player)      # test: leave a save behind (test runs use their own user dir)
		print("screenshot: %s  fps: %d" % [args.shot, Engine.get_frames_per_second()])
		print("STATE time %.0fs hero %s level %d hp %d/%d xp %d kills %d dead %s deaths %d pos %s target %s auto %s camp %s minhp %d%%" % [Time.get_ticks_msec() / 1000.0, player.cls, player.stats.level, player.stats.hp, player.stats.max_hp, player.xp, player.kills, player.stats.dead, player.deaths, player.global_position.snapped(Vector3.ONE), player.target.kind if player.target else "none", player.auto_attacking, player.camp != null, roundi(_min_hp * 100.0)])
		if not _taken.is_empty():
			print("TAKEN %s" % _taken)
		var under := World.enemies.filter(func(e): return e.global_position.y < World.height_at(e.global_position.x, e.global_position.z) - 3.0)
		print("UNDER %d of %d enemies below the ground%s" % [under.size(), World.enemies.size(), (": " + ", ".join(under.map(func(e): return "%s %s" % [e.kind, e.global_position.snapped(Vector3.ONE)]))) if not under.is_empty() else ""])
		print("BAG money %s items %s" % [Items.money_text(player.money), ", ".join(player.bag.map(func(it): return "%s (%s)" % [it.name, it.rarity]))])
		get_tree().quit()

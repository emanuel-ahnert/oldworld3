class_name Audio
extends Node
## Music and sound effects (synthesized by tools/audio/makeaudio.py, from Oldworld2).
## Music follows the situation with a crossfade: combat, near the settlement, the zone; a sad
## tune on death. Sound effects are short one-shots.

const MUSIC := "res://assets/audio/music/%s.ogg"
const SOUND := "res://assets/audio/sounds/%s.wav"
const FADE := 1.5

static var instance: Audio
var zone_music := "grassland"
var village_music := "village"

var _players: Array[AudioStreamPlayer] = []
var _current := 0
var _track := ""
var _sfx: Array[AudioStreamPlayer] = []
var _cache := {}
var _last_play := {}


func _ready() -> void:
	instance = self
	GameMenu.apply_volumes()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80
		p.bus = "Music"
		add_child(p)
		_players.append(p)
	for i in 8:
		var s := AudioStreamPlayer.new()
		s.volume_db = -4
		s.bus = "SFX"
		add_child(s)
		_sfx.append(s)


## On quit or leaving the game: streams still playing at exit leak their playback objects
## (engine warnings on stdout), so stop and release them.
func _exit_tree() -> void:
	for p in _players + _sfx:
		p.stop()
		p.stream = null
	_cache.clear()
	if instance == self:
		instance = null


static func sfx(name: String, volume_db := 0.0) -> void:
	if instance:
		instance._play_sfx(name, volume_db)


## A blow landing: the weapon's impact (sword, axe, mace, club, staff, dagger, claw, bite, arrow;
## hit_<kind>1..3, one take at random), a crit with the crit ring over it.
static func hit(kind: String, crit := false, volume_db := 0.0) -> void:
	if instance == null:
		return
	instance._play_sfx("hit_%s%d" % [kind, randi() % 3 + 1], volume_db + (2.0 if crit else 0.0))
	if crit:
		instance._play_sfx("crit", volume_db - 8.0)


static func music(track: String) -> void:
	if instance:
		instance._play_music(track)


func _play_sfx(name: String, volume_db: float) -> void:
	var t := Time.get_ticks_msec()
	if t - int(_last_play.get(name, -1000)) < 60:     # the same sound twice in one frame
		return
	_last_play[name] = t
	var path := SOUND % name
	if not ResourceLoader.exists(path):
		return
	for s in _sfx:
		if not s.playing:
			s.stream = load(path)
			s.volume_db = -4 + volume_db
			s.play()
			return


func _play_music(track: String) -> void:
	if track == _track:
		return
	var path := MUSIC % track
	if not ResourceLoader.exists(path):
		return
	_track = track
	var stream: AudioStream = _cache.get(track)
	if stream == null:
		stream = load(path)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = track != "sad"
		_cache[track] = stream
	var old := _players[_current]
	_current = 1 - _current
	var new := _players[_current]
	new.stream = stream
	new.volume_db = -40
	new.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(new, "volume_db", -8.0, FADE)
	tw.tween_property(old, "volume_db", -60.0, FADE)
	tw.chain().tween_callback(old.stop)


## Picks the music for the hero's situation (called a few times per second).
func update_music(p: Player) -> void:
	if p == null:
		return
	if p.stats.dead:
		_play_music("sad")
		return
	var fight := ""
	for e in World.enemies:
		if e.state == Enemy.State.CHASE and e.global_position.distance_to(p.global_position) < 40.0:
			fight = "fight_elite" if e.stats.tier == "elite" else ("fight" if fight == "" else fight)
	if fight != "":
		_play_music(fight)
	else:
		var z := World.zones.zone_at(p.global_position) if World.zones else null
		var near_village := z != null and z.to_local2(p.global_position).length() < 70.0
		if near_village:
			_play_music(village_music)
		elif not (_track in ["fight", "fight_elite"]) or not p.stats.in_combat():
			_play_music(zone_music)

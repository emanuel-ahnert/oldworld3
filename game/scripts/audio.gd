class_name Audio
extends Node
## Music and sound effects. Music: generated takes (ACE-Step on the GPU box,
## tools/audio/master_music.sh), several per track, one after another. Sound effects: generated
## (MOSS-SoundEffect) or synthesized (tools/audio/makeaudio.py).
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
var _take := ""                ## the path of the take playing
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
		p.finished.connect(_on_take_finished.bind(p))
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
## `surface`: what the blow lands on (flesh, metal, bone, chitin, spirit; Enemy.surface(),
## Player.surface()): hit_<kind>_<surface>1..3 when there is one, the weapon's own otherwise.
static func hit(kind: String, crit := false, volume_db := 0.0, surface := "") -> void:
	if instance == null:
		return
	var n := randi() % 3 + 1
	var name := "hit_%s%d" % [kind, n]
	if surface != "" and ResourceLoader.exists(SOUND % ("hit_%s_%s%d" % [kind, surface, n])):
		name = "hit_%s_%s%d" % [kind, surface, n]
	instance._play_sfx(name, volume_db + (5.0 if crit else 0.0))      # crits clearly louder
	if crit:
		instance._play_sfx("crit", volume_db - 3.0)


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
	var takes := _takes(track)
	if takes.is_empty():
		return
	_track = track
	_start_take(takes[randi() % takes.size()], FADE)


## The takes of a track (generated music, tools/audio/master_music.sh): <track>.ogg,
## <track>_2.ogg, ... Any of them plays; after one ends, another (see _on_take_finished).
func _takes(track: String) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, 10):
		var path := MUSIC % (track if i == 1 else "%s_%d" % [track, i])
		if not ResourceLoader.exists(path):
			break
		out.append(path)
	return out


func _start_take(path: String, fade: float) -> void:
	_take = path
	var stream: AudioStream = _cache.get(path)
	if stream == null:
		stream = load(path)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = false      # the next take follows instead
		_cache[path] = stream
	var old := _players[_current]
	_current = 1 - _current
	var new := _players[_current]
	new.stream = stream
	new.volume_db = -40
	new.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(new, "volume_db", -8.0, fade)
	tw.tween_property(old, "volume_db", -60.0, fade)
	tw.chain().tween_callback(old.stop)


## A take played to its end: another take of the same track (not the same one again when there
## are more); the lament on death plays once.
func _on_take_finished(player: AudioStreamPlayer) -> void:
	if player != _players[_current] or _track == "" or _track == "sad":
		return
	var takes := _takes(_track)
	if takes.size() > 1:
		takes.erase(_take)
	if not takes.is_empty():
		_start_take(takes[randi() % takes.size()], 0.5)


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

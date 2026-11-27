class_name Quests
extends RefCounted
## Notice-board quests (design/quests.md): every inn posts three hunting quests for the
## enemies of its zone, and a bounty on the zone's champion (a named elite) while it has one. Reaching the inn takes them on; killing the enemies (anywhere) counts;
## coming back to the inn of that zone hands them in for XP, money and an item. When all three
## are done, the board posts the next round.

const PER_ZONE := 3
const CHAMPION_TITLES := ["Bounty: %s", "Slay %s", "Wanted: %s", "The end of %s"]
const TITLES := [
	"Thin out the %s", "Bounty: %s", "Clear out the %s", "Trouble with %s", "Hunt the %s",
]

var active: Array = []            ## {zone: "x,z", zone_name, kind, name, title, need, have, level, round}
var rounds := {}                  ## "x,z" -> number of rounds handed in
var posted := false               ## the last visit_inn posted new quests
var champions := {}               ## "x,z" -> the last round a champion's bounty was posted in


static func key_of(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


## The hero reached the inn of zone z: hand in finished quests, then take on the board's quests.
## Returns the finished quests (the caller gives the rewards).
func visit_inn(z: Zone) -> Array:
	var key := key_of(z.cell)
	posted = false
	var done := active.filter(func(q): return q.zone == key and int(q.have) >= int(q.need))
	for q in done:
		active.erase(q)
	var left := active.filter(func(q): return q.zone == key and not q.has("champion"))     # (the hunts' rounds don't wait for the champion)
	if left.is_empty() and (not done.is_empty() or not _offered(key)):
		if not done.is_empty():
			rounds[key] = int(rounds.get(key, 0)) + 1
		_post(z)
		posted = true
	elif _post_champion(z, int(rounds.get(key, 0))):
		posted = true
	return done


func _offered(key: String) -> bool:
	return rounds.has(key)


func _post(z: Zone) -> void:
	var key := key_of(z.cell)
	if not rounds.has(key):
		rounds[key] = 0
	var round := int(rounds[key])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([key, round, 31])
	var kinds: Array = z.info.enemies.keys()
	# Shuffle deterministically, then take the first three.
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	var lo := 5 * z.difficulty - 4
	for k in kinds.slice(0, PER_ZONE):
		var d := EnemyData.get_kind(k)
		var elite: bool = d.tier != "trash"
		var plural := _plural(String(d.name))
		active.append({
			"zone": key, "zone_name": z.zone_name, "kind": k,
			"title": TITLES[rng.randi() % TITLES.size()] % plural,
			"need": rng.randi_range(3, 5) if elite else rng.randi_range(6, 10),
			"have": 0, "level": lo + 2 + round, "round": round, "plural": plural,
		})
	_post_champion(z, round)


## The champion's bounty: this zone's named elite, once a round (posted with the round, or on
## a later visit for a round already running).
func _post_champion(z: Zone, round: int) -> bool:
	var key := key_of(z.cell)
	if int(champions.get(key, -1)) >= round:
		return false
	for e: Enemy in z.enemies:
		if is_instance_valid(e) and e.champion != "":
			champions[key] = round
			active.append({
				"zone": key, "zone_name": z.zone_name, "kind": e.kind, "champion": e.champion,
				"title": CHAMPION_TITLES[absi(hash([key, round])) % CHAMPION_TITLES.size()] % e.champion,
				"need": 1, "have": 0, "level": 5 * z.difficulty - 4 + 4 + round, "round": round, "plural": e.champion,
			})
			return true
	return false


static func _plural(n: String) -> String:
	if n.ends_with("f"):
		return n.substr(0, n.length() - 1) + "ves"
	if n.ends_with("s") or n.ends_with("x") or n.ends_with("ch") or n.ends_with("sh"):
		return n + "es"
	if n.ends_with("y") and not n.ends_with("ay") and not n.ends_with("ey"):
		return n.substr(0, n.length() - 1) + "ies"
	return n + "s"


## An enemy of this kind died to the hero (`champion`: its name if it was one; a champion's
## bounty counts only that champion, a hunt any of its kind). Returns the quests that just
## became complete.
func on_kill(kind: String, champion := "") -> Array:
	var finished := []
	for q in active:
		if q.has("champion") and q.champion != champion:
			continue
		if q.kind == kind and int(q.have) < int(q.need):
			q.have = int(q.have) + 1
			if int(q.have) == int(q.need):
				finished.append(q)
	return finished


## Rewards of a finished quest: XP like five kills of its level (at most half a level), money,
## and an uncommon (15%: rare) item.
static func reward_xp(q: Dictionary, hero_level: int) -> int:
	var by_level := Rules.enemy_xp(int(q.level), hero_level, "trash") * 5
	if q.has("champion"):
		# A champion's bounty: three times as much, at most four fifths of a level.
		return maxi(15, mini(by_level * 3, Rules.xp_to_next(hero_level) * 4 / 5))
	return maxi(5, mini(by_level, Rules.xp_to_next(hero_level) / 2))


static func reward_money(q: Dictionary) -> int:
	return int(q.level) * (100 if q.has("champion") else 25)


func to_save() -> Dictionary:
	return {"active": active, "rounds": rounds, "champions": champions}


func load_save(d: Dictionary) -> void:
	var a = d.get("active", [])
	active = a if a is Array else []
	var r = d.get("rounds", {})
	rounds = r if r is Dictionary else {}
	var c = d.get("champions", {})
	champions = c if c is Dictionary else {}

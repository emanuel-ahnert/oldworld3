class_name Icons
## Ability, passive and effect icons (assets/ui/icons/<id>.png, generated: tools/icons). An id is
## the snake_case of the name ("Thunder Clap" -> thunder_clap); a few effects have names of
## their own (Slowed, Dazed, Chilled -> slowed). get() returns null when there is no icon, and
## the caller shows the name instead.

const DIR := "res://assets/ui/icons/%s.png"
const ALIASES := {"dazed": "slowed", "chilled": "slowed", "frozen": "slowed", "slow": "slowed",
	"stun": "stunned", "root": "rooted"}

static var _cache := {}


static func id_of(name: String) -> String:
	var id := name.to_lower().strip_edges().replace("'", "").replace("-", "_").replace(" ", "_")
	return String(ALIASES.get(id, id))


static func get_icon(name_or_id: String) -> Texture2D:
	var id := id_of(name_or_id)
	if _cache.has(id):
		return _cache[id]
	var path := DIR % id
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[id] = tex
	return tex

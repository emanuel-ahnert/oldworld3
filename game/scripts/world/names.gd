class_name ZoneNames
extends RefCounted
## Generated zone names (from Oldworld2's procgen/names.go). Patterns pick words from lists;
## the seed decides, so a zone always has the same name.

const LISTS := {
	"gstart": ["Bramble", "Willow", "Oak", "Ash", "Thorn", "Mead", "Fern", "Hazel", "Clover", "Elder",
		"Briar", "Moss", "Barley", "Rowan", "Sorrel", "Alder", "Heather", "Linden", "Marigold", "Primrose",
		"Thistle", "Yarrow", "Bracken", "Cress", "Mallow", "Sedge", "Tansy", "Wheat", "Rye", "Larch",
		"Holly", "Ivy", "Juniper", "Laurel", "Myrtle", "Pine", "Quince", "Sage", "Teasel", "Vetch"],
	"gend": ["wick", "dale", "ford", "mere", "stead", "holm", "brook", "vale", "ley", "combe", "field",
		"hollow", "bury", "ton", "worth", "ham", "thorpe", "by", "well", "moor", "shaw", "hurst", "den",
		"stow", "cote", "garth", "hythe", "lowe", "mead", "wold"],
	"gplace": ["Meadows", "Fields", "Downs", "Heath", "Lowlands", "Greens", "Commons", "Pastures", "Wolds",
		"Glades", "Hills", "Vale", "Moors", "Leas", "Hollows", "Brooklands", "Marches", "Uplands", "Shires",
		"Copses"],
	"gadj": ["Quiet", "Golden", "Rolling", "Windy", "Gentle", "Verdant", "Misty", "Sunlit", "Emerald",
		"Whispering", "Hidden", "Wild", "Old", "Bright", "Drowsy", "Amber", "Silver", "Lonely", "Merry",
		"Dappled", "Hazy", "Blooming", "Weeping", "Crooked", "Far"],
	"gperson": ["Aldric", "Bertha", "Cedric", "Edith", "Godwin", "Hilda", "Osric", "Wynn", "Alma", "Brand",
		"Elric", "Freya", "Gareth", "Mabel", "Oswin", "Rowena", "Tilda", "Wulf", "Agnes", "Edmund",
		"Aelfric", "Beornot", "Cuthbert", "Dunstan", "Eadgyth", "Hereward", "Leofric", "Mildred",
		"Ethel", "Wilfred", "Alwin", "Bede", "Hugh", "Isolde", "Maud", "Odo", "Rosamund", "Walter"],
	"dplace": ["Sands of", "Dunes of", "Wastes of", "Oasis of", "Winds of", "Mirage of", "Plains of",
		"Expanse of", "Steppe of", "Wells of", "Gate of", "Shadow of"],
	"dplace2": ["Sands", "Dunes", "Wastes", "Expanse", "Flats", "Barrens", "Reach", "Basin"],
	"ds1": ["Qa", "Ra", "Ma", "Sa", "Za", "Ha", "Ka", "Ja", "Na", "Fa", "Ba", "Ta", "Da", "Sha", "Kha",
		"Ya", "Ghu", "Dhu", "Su", "Mu", "Nu", "Zu", "Bi", "Fi", "Hi", "Ri"],
	"ds2": ["", "", "li", "ra", "ma", "di", "ha", "zi", "bi", "ya", "si", "ru"],
	"ds3": ["dir", "mal", "fir", "sim", "rah", "kal", "bar", "zan", "hir", "rif", "sar", "mun", "dun", "jar",
		"bek", "qim", "sul", "lan", "zir", "hab", "nar", "tah", "far", "wan", "rak", "sab"],
	"ms1": ["Kal", "Myr", "Thal", "Ae", "Lyk", "Ner", "Phi", "Ari", "Kor", "Del", "Xan", "Zak", "Eu", "Ky", "Pel", "Ser",
		"Theo", "Ist", "Mel", "Ol", "Par", "Sky", "Tri", "Hel", "Ach", "Ly"],
	"ms2": ["", "", "a", "o", "i", "e", "an", "es"],
	"ms3": ["os", "ia", "is", "on", "essa", "ene", "ados", "inthos", "ora", "aia", "ikos", "ope", "eia", "assos", "ymna",
		"ithra", "ae", "ymos"],
	"mplace": ["Olive Groves of", "Shores of", "Hills of", "Vineyards of", "Ruins of", "Bay of", "Cliffs of", "Plains of",
		"Gardens of", "Temple Fields of", "Isles of", "Springs of"],
	"mplace2": ["Coast", "Hills", "Groves", "Heights", "Shallows", "Terraces", "Headlands", "Meadows"],
	"mepithet": ["the Golden", "the Wine-Dark", "the Sunlit", "the Blessed", "of the Muses", "of the Oracle", "the Fair",
		"of the Winds", "the White", "the Old"],
	"ustart": ["Raven", "Grim", "Dread", "Black", "Ash", "Bone", "Wolf", "Mourn", "Shade", "Gloam", "Thorn", "Hollow", "Blood",
		"Crow", "Grave", "Night", "Wither", "Dusk", "Morrow", "Vex", "Mor", "Drak", "Vlad", "Stryx", "Kar", "Nos"],
	"uend": ["moor", "wald", "mire", "holt", "vale", "fell", "grave", "keep", "mora", "vania", "stein", "burg", "gard",
		"hollow", "reach", "dun", "skar", "vod"],
	"uplace": ["Woods", "Moors", "Marshes", "Barrows", "Hollows", "Crypts", "Wastes", "Heights", "Gloom", "Thickets", "Graves",
		"Ruins"],
	"uadj": ["Cursed", "Withered", "Silent", "Weeping", "Forsaken", "Shadowed", "Bleak", "Bloodmoon", "Haunted", "Rotting",
		"Black", "Dreadful", "Moonlit", "Accursed"],
	"uperson": ["Count Draven", "Lady Morwen", "Baron Vlakos", "Mother Hesk", "Lord Malgrim", "Countess Szara", "Old Ivo",
		"the Pale Duke", "Abbot Krell", "Margravine Ilsa", "Sir Corvin", "Witch Agnet"],
	"nstart": ["Frost", "Ulf", "Rav", "Thor", "Skog", "Hvit", "Jarn", "Bjorn", "Kald", "Snae", "Hrim", "Ask",
		"Stein", "Dal", "Fjall", "Isa", "Svart", "Grim", "Hald", "Ormr", "Brekk", "Lind", "Vind", "Myrk",
		"Sigr", "Holt", "Eik", "Kol", "Rand", "Sval"],
	"nend": ["heim", "vik", "fjord", "dal", "gard", "holm", "stad", "nes", "berg", "by", "mark", "vang",
		"land", "fell", "voll", "haug", "skar", "botn", "rud", "mo"],
	"nplace": ["Fells", "Wastes", "Reaches", "Wilds", "Marches", "Woods", "Heights", "Barrows", "Shores",
		"Holds", "Peaks", "Hollows", "Fjords", "Moors"],
	"nadj": ["Frozen", "Silent", "Grey", "White", "Howling", "Bitter", "Iron", "Pale", "Wolfhaunted",
		"Starlit", "Deep", "Endless", "Black", "Windswept", "Shrouded", "Old", "Hoarfrost", "Bleak"],
	"nperson": ["Sigrun", "Ragnar", "Astrid", "Halvard", "Ingrid", "Bjarki", "Solveig", "Eirik", "Gudrun",
		"Thorvald", "Hilde", "Ketil", "Ylva", "Orm", "Runa", "Leif", "Sigmund", "Torunn", "Ulfar", "Vigdis",
		"Arne", "Brynja", "Dagny", "Gunnar", "Hakon", "Kari"],
	"eplace": ["Valley of", "Sands of", "Necropolis of", "Dunes of", "Tombs of", "Plains of", "Gates of",
		"Shadow of", "Temple Fields of", "Throne of", "Eye of", "Steps of"],
	"es1": ["Kheper", "Neb", "Sekh", "Amen", "Hat", "Mer", "Sen", "Ankh", "Ptah", "Nefer", "Tef", "Khon",
		"Seth", "Hor", "Wadj", "Ra", "Iset", "Khaf", "Mut", "Sob", "Ten", "Djed", "Heq", "Wser", "Taw"],
	"es2": ["", "", "", "em", "en", "et", "i", "ab"],
	"es3": ["u", "et", "hotep", "mose", "ankh", "ra", "ti", "ka", "nut", "su", "ib", "ses", "ef", "ari",
		"at", "aten", "ep", "is", "mes", "kare"],
	"eepithet": ["the Eternal", "the Golden", "the Silent", "the Forgotten", "the Buried", "the Radiant",
		"the Undying", "the Sunborn", "the Veiled", "the Exalted", "the Lost", "the Mighty"],
}

const PATTERNS := {
	"ancient": [
		"{eplace} {es1}{es2}{es3}",
		"{eplace} {es1}{es2}{es3} {eepithet}",
		"{es1}{es2}{es3}'s {dplace2}",
		"{eplace} {es1}{es3}-{es1}{es3}",
	],
	"grassland": [
		"{gstart}{gend} {gplace}",
		"{gadj} {gplace} of {gstart}{gend}",
		"{gplace} of {gstart}{gend}",
		"{gadj} {gstart}{gend}",
		"{gperson}'s {gstart}{gend}",
		"{gperson}'s {gadj} {gplace}",
	],
	"desert": [
		"{dplace} Al-{ds1}{ds2}{ds3}",
		"{dplace} {ds1}{ds2}{ds3}",
		"{ds1}{ds2}{ds3} {dplace2}",
		"Al-{ds1}{ds2}{ds3} {dplace2}",
	],
	"mediterranean": [
		"{mplace} {ms1}{ms2}{ms3}",
		"{ms1}{ms2}{ms3} {mplace2}",
		"{mplace} {ms1}{ms2}{ms3} {mepithet}",
		"{ms1}{ms3} {mepithet}",
	],
	"unholy": [
		"{ustart}{uend} {uplace}",
		"{uadj} {uplace} of {ustart}{uend}",
		"{uplace} of {ustart}{uend}",
		"{uadj} {ustart}{uend}",
		"{uperson}'s {ustart}{uend}",
	],
	"north": [
		"{nstart}{nend} {nplace}",
		"{nadj} {nplace} of {nstart}{nend}",
		"{nplace} of {nstart}{nend}",
		"{nadj} {nstart}{nend}",
		"{nperson}'s {nstart}{nend}",
		"{nperson}'s {nadj} {nplace}",
	],
}


static func make(zone_type: String, seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([zone_type, seed, 500])
	var pats: Array = PATTERNS.get(zone_type, PATTERNS.grassland)
	var p: String = pats[rng.randi() % pats.size()]
	var out := ""
	var i := 0
	while i < p.length():
		if p[i] == "{":
			var j := p.find("}", i)
			var words: Array = LISTS[p.substr(i + 1, j - i - 1)]
			out += words[rng.randi() % words.size()]
			i = j + 1
		else:
			out += p[i]
			i += 1
	return out

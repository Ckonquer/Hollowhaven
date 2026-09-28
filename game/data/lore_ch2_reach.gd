extends RefCounted
## Chapter Two lore of Hallowmere Reach's surface (docs/CHAPTER_TWO_SPEC.md §10), shaped like
## src/world/below/lore.gd: ORDER (journal order) + LORE {id: {title, text, optional alt_title / alt_text}}.
## Read through src/core/lore_db.gd (LoreDB.get_lore(id)); discovered with GameState.discover_lore(id).
## Owner: the Reach region module (C1). The district notes (garden, groundskeeper, quarry log, manor
## invitation) are written here and only discovered by id by the district modules that place them.
## MP §17 lines are used verbatim (festival board, Conservatory, garden note, manor invitation).

const ORDER := [
	"lore_ch2_festival_board",
	"lore_ch2_conservatory",
	"lore_ch2_true_light",
	"lore_ch2_preparations",
	"lore_ch2_bellhouse",
	"lore_ch2_garden_note",
	"lore_ch2_groundskeeper_1",
	"lore_ch2_groundskeeper_2",
	"lore_ch2_quarry_log",
	"lore_ch2_manor_invitation",
]

const LORE := {
	# --- Region (Lanternwake Commons, the Conservatory, the Sunken Bellhouse) -------------------------
	"lore_ch2_festival_board": {
		"title": "The Festival Board",
		"text": "Lanternwake: a lamp at every gate, a sweet upon every table, a place for every traveler.",
	},
	"lore_ch2_conservatory": {
		"title": "The Ward-Keeper's Words",
		"text": "We did not build the lanterns to drive out every dark. We built them so a traveler could always find a kindness.",
	},
	"lore_ch2_true_light": {
		"title": "A Worn Festival Plaque",
		"text": "Mind the true light. A real lamp warms the ground it stands on and keeps its place. A light that lights nothing, or follows your step, is only pretending. Look down before you follow.",
	},
	"lore_ch2_preparations": {
		"title": "Made for the Journey",
		"text": "For whoever takes the Bellhouse stair: the deep works are old and patient, and they do not mind if you take your time. A little armour helps. A padded hood or a pair of copper boots is plenty to begin with, and the seam by the door will teach your pickaxe iron. Pack something warm to eat, keep your lantern lit, and come back up whenever you like. The road home is never locked from this side.",
	},
	"lore_ch2_bellhouse": {
		"title": "The Bell That Sank",
		"text": "Ashbell hung its bell here to call the shifts home. When the ground went soft the bell cracked and the house sank to its knees, but somebody always kept the lamp in the upper window lit, so anyone climbing the service stair could see which way was up.",
	},
	# --- District notes (displayed by the district modules) -------------------------------------------
	"lore_ch2_garden_note": {
		"title": "A Note in the Seed Box",
		"text": "Plant the round ones for supper. Carve the crooked ones for company. Do not feed the one that feeds itself.",
	},
	"lore_ch2_groundskeeper_1": {
		"title": "Groundskeeper's Note",
		"text": "Every night I light a candle for the moon, so she is not the only lamp awake up there. Swept the paths, trimmed the moonflowers, a candle on every stone. One dish sits empty. I keep meaning to.",
	},
	"lore_ch2_groundskeeper_2": {
		"title": "Groundskeeper's Second Note",
		"text": "If I don't get round to it, would you? The empty dish by the south-west wall. The moon won't mind whose hand lights it. A little light is all it wants.",
	},
	"lore_ch2_quarry_log": {
		"title": "Ashbell Winch Log",
		"text": "Day 12. Winch cable spliced, drum greased, shelf crew back up tomorrow. Day 13. The tall pillars on the third terrace hum whenever the old bell is struck, and the bell has been cracked since spring. Told the lads to keep clear of them after dusk. Day 14. Winch jammed again. Somebody moved a pillar.",
	},
	"lore_ch2_manor_invitation": {
		"title": "An Invitation",
		"text": "To the bearer of a proper light: you are expected. The house has practiced being welcoming.",
	},
}


static func has_lore(id: String) -> bool:
	return LORE.has(id)


static func get_lore(id: String) -> Dictionary:
	var e: Dictionary = LORE.get(id, {})
	return {"title": String(e.get("title", "")), "text": String(e.get("text", ""))}

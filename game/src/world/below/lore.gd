extends RefCounted
## Lore notes found in The Below (original writing). Used by the world (Events.say when read) and by
## the journal UI:  load("res://src/world/below/lore.gd").get_lore(id) -> {"title", "text"}
## Texts respect the arachnophobia setting (alt_text) where the wording would be spider-themed.

const ORDER := ["landing_notice", "miner_journal_1", "foreman_order", "miner_journal_2", "ward_keeper", "hollows_page"]

const LORE := {
	"landing_notice": {
		"title": "Notice by the Lift",
		"text": "LIFT OUT OF ORDER. The winch jammed at the bottom of the deep works and nobody is going down to fix it. Use the ladder. And stop singing on shift. The echoes sing back.",
	},
	"miner_journal_1": {
		"title": "Miner's Journal, page 11",
		"text": "Glowcaps are thick past the bend, bright enough to eat lunch by. Old Hask swears the rails hum at night. I told him it's only the wind. There is no wind down here.",
	},
	"foreman_order": {
		"title": "The Foreman's Order",
		"text": "The lower gate stays LOCKED. Nobody goes below after the bell. Something down there has learned our voices. If you hear a friend calling from the dark, do not answer. Look for your own light. I'm keeping the key.",
	},
	"miner_journal_2": {
		"title": "Miner's Journal, torn page",
		"text": "We broke into stonework older than any of us. Carved faces, all with their eyes shut. Tobin laughed at them and went back for his lantern. We found the lantern.",
	},
	"ward_keeper": {
		"title": "The Ward-Keeper's Carving",
		"text": "Here we set the seed of light into the stone above, and the deep went quiet. Keep it bright. What waits below cannot bear a kept flame, nor a home that is loved.",
	},
	"hollows_page": {
		"title": "A Page Caught in the Silk",
		"alt_title": "A Page Caught in the Roots",
		"text": "It clings high and weaves where it thinks the light can't reach. The old fire-bowls still take a flame. Light them and its threads burn away, and down it comes.",
		"alt_text": "It clings high, rooted where it thinks the light can't reach. The old fire-bowls still take a flame. Light them and its hold burns away, and down it comes.",
	},
}


static func has_lore(id: String) -> bool:
	return LORE.has(id)


static func all_ids() -> Array:
	return ORDER.duplicate()


## {"title": String, "text": String} (empty strings for unknown ids).
static func get_lore(id: String) -> Dictionary:
	if not LORE.has(id):
		return {"title": "", "text": ""}
	var d: Dictionary = LORE[id]
	var alt := bool(Settings.get_value("arachnophobia"))
	var title: String = String(d.get("alt_title", d["title"])) if alt else String(d["title"])
	var text: String = String(d.get("alt_text", d["text"])) if alt else String(d["text"])
	return {"title": title, "text": text}

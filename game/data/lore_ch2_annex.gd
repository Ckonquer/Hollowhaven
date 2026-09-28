extends RefCounted
## Lore notes of Tobin's Lost Shift (area "tobin_annex", module B10). Read through src/core/lore_db.gd
## (LoreDB.get_lore(id) / ids() / has_lore(id)); shaped like src/world/below/lore.gd (docs/CHAPTER_TWO_SPEC.md
## §10). Found in the annex (src/world/areas_ch2/tobin_annex_world.gd): discovering one calls
## GameState.discover_lore(id). Nothing here is spider-like, so no alt_title / alt_text is needed.
##   lore_ch2_shift_rules   the Foreman's chalk board in the entry: teaches the Hollow Drudge's two tells
##   lore_ch2_tobin_letter  Tobin's personal letter in his locker (flag c1x_tobin_letter_found)
##   lore_ch2_tobin_note    Tobin's service note at the sluice (MP §17 text, verbatim; grants rw_c1x_tobin)
##   lore_ch2_lantern_mark  the scrawled lantern mark in the sump: the early clue to Chapter Two

const ORDER := ["lore_ch2_shift_rules", "lore_ch2_tobin_letter", "lore_ch2_tobin_note", "lore_ch2_lantern_mark"]

const LORE := {
	"lore_ch2_shift_rules": {
		"title": "Side-Door Shift Rules",
		"text": "Sign in, sign out. Lamps lit before the lockers. If an empty coat stands up, do not argue with it: when it lifts its pick high, step aside; when it drags the pick along the floor, get out of its line or roll through. Strike while it catches its breath. And nobody answers voices in the sump. - The Foreman",
	},
	"lore_ch2_tobin_letter": {
		"title": "A Letter in Locker Nine",
		"text": "Mam, don't let them tell you I was lost. I was only late. The passage went quiet after the bell, then it answered in my own voice, and I ran till I found water. Hask brought me out, and the Foreman says there is work for us somewhere warmer. Keep a lamp in the window. I'll follow it home. Your Tobin.",
	},
	"lore_ch2_tobin_note": {
		"title": "Tobin's Service Note",
		"text": "I dropped the lantern when the passage answered me. Hask found me at the sluice. Tell whoever comes after us: the garden below is real.",
	},
	"lore_ch2_lantern_mark": {
		"title": "A Lantern Scratched in Stone",
		"text": "Someone scratched a lantern deep into the rock, three little flames beneath it and an arrow pointing north, past the woods. Under it, in Tobin's cramped hand: \"Where the lanterns wake, the road is kind.\"",
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
	return {"title": String(d["title"]), "text": String(d["text"])}

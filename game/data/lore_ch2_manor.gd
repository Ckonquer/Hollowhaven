extends RefCounted
## Moonveil Manor notes (docs/CHAPTER_TWO_SPEC.md §10; MP §9, §13.1, §14, §15, §17). Found inside the
## manor (area "moonveil_manor"); read through LoreDB.get_lore(id). Shaped like src/world/below/lore.gd.
## The front-door invitation (lore_ch2_manor_invitation) belongs to the Reach districts file
## (data/lore_ch2_reach.gd): the manor module only discovers it. Nothing here is spider-themed, so no
## alt_title / alt_text is needed.

const ORDER := [
	"lore_ch2_manor_guest_list",
	"lore_ch2_manor_looking_glass",
	"lore_ch2_manor_dance_card",
	"lore_ch2_manor_dancing_rail",
	"lore_ch2_manor_tailor_note",
	"lore_ch2_manor_count_diary",
	"lore_ch2_manor_lantern_plaque",
]

const LORE := {
	"lore_ch2_manor_guest_list": {
		"title": "The Guest List",
		"text": "Every name on the Masquerade list has been crossed out, carefully, in violet ink. At the bottom, in a different hand, one line was added: Someone with a proper light.",
	},
	"lore_ch2_manor_looking_glass": {
		"title": "A Card by the Looking-Glasses",
		"text": "House rule of Moonveil: our looking-glasses were silvered with festival wax, and they answer only TRUE light. A candle, a lantern, a kind face holding either. Painted flames and borrowed glows show nothing at all. Our host wears a little gold collar for the Masquerade; in any looking-glass, and in any candle's light, it is the brightest thing in the room.",
	},
	"lore_ch2_manor_dance_card": {
		"title": "A Dance Card",
		"text": "The first dance belongs to the hearth candle: light it, and its flame will walk the gilt ribbons like a guest looking for a partner. Each candelabrum turns its little brass hand toward the ribbon it prefers. Guide the flame to the crescent on the Gallery doors. Should the dance go wrong, pull the brass lever and everyone returns to their places.",
	},
	"lore_ch2_manor_dancing_rail": {
		"title": "Note Pinned to the Rail",
		"text": "For the Masquerade: partners on the clockwork rail, for guests too shy to take the floor. The rail turns them at the end of every waltz, so they bow. Wind the key twice. Do not wind it a third time. It takes offence.",
	},
	"lore_ch2_manor_tailor_note": {
		"title": "The Count's Tailoring Note",
		"text": "Three scraps of my best velvet went astray before the festival: one to the powder room, one to the musicians, and one I tucked away myself and promptly forgot. A proper cape wants all three. The Loom knows the rest.",
	},
	"lore_ch2_manor_count_diary": {
		"title": "A Page from the Count's Diary",
		"text": "The invitation arrived in my own handwriting. I do not remember writing it. I find I cannot stop reading it aloud, to empty chairs, every evening. The candles do not like it. Neither, I think, do I.",
	},
	"lore_ch2_manor_lantern_plaque": {
		"title": "The Moonveil Lantern",
		"text": "Lit each Lanternwake from the ward candles in the Gallery, so the orchard and the quarry could see that the manor was keeping its promise: a lamp at every gate, and a warm welcome behind each.",
	},
}


static func has_lore(id: String) -> bool:
	return LORE.has(id)

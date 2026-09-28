extends RefCounted
## Lore of the Hushed Works (Chapter Two, works modules). Shaped like src/world/below/lore.gd and read through
## src/core/lore_db.gd (LoreDB.get_lore(id) -> {"title", "text"}; arachnophobia-aware via alt_title / alt_text).
## Rooms 1-8 place their notes from data/works_layout.gd LORE_SPOTS; the deep module (rooms 9-14) shows
## lore_ch2_bell_throat_note (Bell Throat, room 13) and lore_ch2_before_choir (above the Choir Vault) by id.
## The MP §17 lines are used verbatim: Hask's rail note (lore_ch2_hask_note, room 3), the Foreman's refuge record
## (lore_ch2_refuge_record, room 7) and "Before the Choir". Tobin's MP §17 note itself belongs to Tobin's annex
## (data/lore_ch2_annex.gd lore_ch2_tobin_note: reading it there pays rw_c1x_tobin; "The Miner Who Came Back" asks
## for Tobin's separate letter, lore_ch2_tobin_letter), so the Works never places or redefines that id; the Sluice
## Gallery carries its context instead (lore_ch2_sluice_chalk: Hask's chalk note about bringing Tobin down).
## "Find Hask's note in the refuge" (ch2_hask_note_found) is the refuge planter note lore_ch2_hask_refuge_note: it
## sets that flag directly, and the story tracker (src/world/story_ch2/story_ch2.gd LORE_FLAGS) repairs it from
## that lore id. Hask's rail lamp-post note (lore_ch2_hask_note, room 3) is lore only and ticks no objective.

const ORDER := [
	"lore_ch2_service_notice", "lore_ch2_service_diagram", "lore_ch2_lockers_note", "lore_ch2_hask_note",
	"lore_ch2_closed_eyes", "lore_ch2_eyes_route", "lore_ch2_bell_order", "lore_ch2_sluice_plaque",
	"lore_ch2_sluice_chalk", "lore_ch2_lightwell_plaque", "lore_ch2_refuge_record", "lore_ch2_hask_refuge_note",
	"lore_ch2_bell_throat_note", "lore_ch2_before_choir",
]

const LORE := {
	"lore_ch2_service_notice": {
		"title": "Notice at the Service Landing",
		"text": "HUSHED WORKS - SERVICE ACCESS. Hang every lamp on its hook. A lamp that lights the floor around it is one of ours. Anything down here that glows and lights nothing is not. Tools to the lockers, voices to yourself. - The Foreman",
	},
	"lore_ch2_service_diagram": {
		"title": "Service Diagram",
		"text": "Landing, Lockers, Rail Hall, then the Garden Refuge. From the Refuge: WATER at the sluice gallery, BELL at the bellmaker's floor, LIGHT at the well. All three lines lit opens the lower ward door. (In pencil, beside the Refuge: \"the bench is comfy\".)",
	},
	"lore_ch2_lockers_note": {
		"title": "Note in a Locker",
		"text": "To whoever keeps borrowing my good gloves: the old coats in these lockers get up and walk about sometimes. They lift the pick slow and swing it narrow, then scrape the floor. Step aside, let it finish, and give it a good knock while it is still bent over. Put the gloves BACK. - Wren",
	},
	"lore_ch2_hask_note": {
		"title": "Hask's Note on the Rail Post",
		"text": "The knock came back a beat too late. I put my lamp beside the rail. A true light stays with what holds it.",
	},
	"lore_ch2_closed_eyes": {
		"title": "Carving in the Hall of Closed Eyes",
		"text": "The carvers shut every eye in stone, so nothing in the dark could borrow them. One face was left without its lamp. Give it back, and it will show you where the carvers rested.",
	},
	"lore_ch2_eyes_route": {
		"title": "The Carvers' Rest",
		"text": "We shut the faces' eyes so the deep had none to borrow. If ever a friend looks at you from a place no friend could stand, look at the floor beneath it. Our lamps always light the floor.",
	},
	"lore_ch2_bell_order": {
		"title": "The Bellmaker's Plaque",
		"text": "Our bells do not play tunes. They keep an order: the Leaf, the Moon, the Key, the Flame. Strike them so, and the line remembers what it carries. Strike wrong, and they simply fall quiet and wait for you to begin again.",
	},
	"lore_ch2_sluice_plaque": {
		"title": "Sluice Gallery",
		"text": "Water for the ward line runs along the middle channel and into the ward basin. Each wheel shows which way it sends the water. Wet boots are not a failure, only a lesson.",
	},
	"lore_ch2_sluice_chalk": {
		"title": "Chalk by the Sluice Wheels",
		"text": "Both wheels to the basin and the ward line drinks. Brought T. down this way from the old sump sluice, soaked to the knees and still talking. The garden is warm and the lad is fed. Mind the wet flags. - H.",
	},
	"lore_ch2_lightwell_plaque": {
		"title": "The Light Well",
		"text": "Guide the well's daylight to the ward crystal. Each mirror turns a quarter at a time. Lost your way? The brass lever sets them back just as they were.",
	},
	"lore_ch2_refuge_record": {
		"title": "The Foreman's Refuge Record",
		"text": "Three of us made the garden. Tobin, Hask, and me. We left by the drainage stair at dawn. The voices stayed behind.",
	},
	"lore_ch2_hask_refuge_note": {
		"title": "Hask's Note in the Planter",
		"text": "Planted the last glowcaps by the bench, so the next one down has light to eat by. Tobin wants to give the garden a name. I told him a garden that saved us needs no name, only watering. - Hask",
	},
	"lore_ch2_bell_throat_note": {
		"title": "Miners' Note in the Bell Throat",
		"text": "Last supplies are here. Past this bell, the Choir sings with voices it took from us. It learned our signals and our welcomes, but it cannot make a light of its own. When three shapes come, raise your lamp at a fixed post: the true one lights the floor beneath it. When it rings, answer with the bellmaker's order. When the cosy lights crowd in, stand by the flame that is fastened to something. - H., T., and the Foreman",
	},
	"lore_ch2_before_choir": {
		"title": "Carved Above the Vault Door",
		"text": "It has learned a welcome. It has not learned a home.",
	},
}


static func has_lore(id: String) -> bool:
	return LORE.has(id)


static func all_ids() -> Array:
	return ORDER.duplicate()

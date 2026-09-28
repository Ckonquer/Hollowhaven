extends RefCounted
## Every recipe unlock flag (data/recipes.gd RECIPES and SPECIAL_RECIPES `unlock`) and the system that sets it.
## A recipe with unlock "" is known from the start. Starter structural essentials (stairs, upper floor, railings,
## half walls, posts, windows, roofs) and basic furniture are all known early: basic building never waits for
## the story. Story and optional rewards only add styles, patterns and keepsakes on top.
## Who sets a flag: the quest layer / optional log set the flags of their own step / goal rewards
## (data/quests_ch2.gd, data/optional_goals.gd); a content module either sets its event flag directly or grants
## its "content" bundle of data/sources.gd REWARDS (GameState.grant_once), never a step / goal reward id.
## Read through ItemDB.unlock_flags() / ItemDB.unlock_setter(flag). Tests check that every flag used by a recipe
## is listed here and that every flag listed here is used.

const UNLOCK_FLAGS := {
	# --- Chapter One (legacy) ---
	"ward_restored": "legacy: Game.complete_chapter() when the Heartseed returns to the Ward Stone (Heartbloom Lamp)",
	# --- Chapter One optional additions (c1x) ---
	"c1x_tailor_cache": "surface module: opening the Tailor's Cache near the Old Oak (optional 'The Tailor's Cache'); unlocks the Loom and the ribbon bow pattern",
	"c1x_elder_defeated": "enemies/surface module: the Knotted Elder at Bramblewatch is defeated (optional 'Bramblewatch'); unlocks the Sturdy Planter and the leaf cape pattern",
	"c1x_tobin_shift": "annex module: reading Tobin's service note in Tobin's Lost Shift ('The Miner Who Came Back'); unlocks the Miner's Lamp",
	# --- Chapter Two story (ch2 quest layer / area modules) ---
	"ch2_orchard_restored": "ch2 quest layer: step ch2_orchard completed (garden lamp lit, reward rw_ch2_orchard); carving, pumpkin cooking and scarecrow recipes",
	"ch2_quarry_restored": "ch2 quest layer: step ch2_quarry completed (reward rw_ch2_quarry); Ironwood knowledge (sword, tools, armor)",
	"ch2_winch_repaired": "Hallowmere quarry module: the Ashbell mineral winch is repaired (upper Moon Crystal shelf reachable); Moonsteel knowledge",
	"ch2_manor_restored": "ch2 quest layer: step ch2_manor completed (reward rw_ch2_manor); Ribbon Witch and Velvet Vampire tailoring patterns",
	"ch2_crossing_cleared": "works module: Weaver's Crossing cleared (spec flag, reward rw_ch2_crossing); Thread Veil drape",
	"ch2_choir_defeated": "works module: the Borrowed Choir is defeated (spec flag); Expedition Board for Lanternwake Expeditions",
	"ch2_homecoming": "ch2 quest layer: step ch2_homecoming completed (reward rw_ch2_homecoming also gives one Wardlight); Wardlight recipe",
	"ch2_feast": "ch2 quest layer: step ch2_feast completed (The Lanternwake celebration); Lanternwake dress pattern",
	# --- Chapter Two optional goals and trials ---
	"ch2_pumpkin_face": "optional goal 'A Pumpkin With a Face' completed (grow, harvest and carve a pumpkin); Pumpkin Patch pattern",
	"ch2_count_wardrobe": "optional goal 'The Count's Wardrobe' completed (three velvet_scrap found in the manor side rooms); Velvet cape pattern",
	"ch2_candleyard_pattern": "Candleyard module: the hidden dress pattern is picked up in the Candleyard; Ghostlight party dress pattern",
	"ch2_groundskeeper_candle": "optional goal 'A Candle for the Groundskeeper' completed; Ghost Lantern recipe",
	"ch2_harvest_table": "optional goal 'The Harvest Table' completed (two different seasonal recipes cooked); festival candy and Lanternwake Table",
	"ch2_trial_matron": "echo trial module: first clear of the Matron echo trial (isolated trial state); Moon Moth shawl pattern",
}

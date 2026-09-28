extends RefCounted
## Optional goals (MP §7 "Optional Chapter One content", MP §15 "Side activities" and the two legacy
## free_play goals). Driven by src/core/optional_log.gd; saved as GameState "optional"
## {goal_id: {"done": bool, "done_at": total_minutes}}. Never part of the main story: nothing requires them.
##
## Objectives use the ChapterLog objective types (see data/quests_ch2.gd header) and are STATE checks:
## a goal completes (latches) the first time all its objectives hold while it is visible, and stays done.
## "visible_if": conditions (same schema as objectives) that must ALL hold for the goal to be shown and
## evaluated ([] = always). "reward": {"give": {item: n}, "flags": [...], "patterns": [wardrobe ids],
## "message": ""} granted once through GameState.grant_once("rw_" + goal id, ...).
## "chapter": 1 or 2 (journal grouping). "legacy": true = the two goals of the legacy free_play step
## (a save whose free_play step is already completed marks them done silently on load).
##
## FLAGS the content modules set for these goals (the optional log only reads them):
## | goal                    | flags / state read                                                        | set by (module)          |
## |-------------------------|---------------------------------------------------------------------------|--------------------------|
## | opt_look_of_your_own    | c1x_look_chosen (a look confirmed at creation, a mirror or the wardrobe)  | appearance / wardrobe    |
## | opt_brave_little_steps  | c1x_ribbon_given (Comfort Ribbon given to Mochi), c1x_mochi_courage       | companions               |
## | opt_copper_courage      | placed furnace; any armor equipped (GameState.equipment)                  | crafting / equipment     |
## | opt_tailors_cache       | c1x_tailor_cache (opening the cache; also the Loom unlock flag)            | Chapter One additions    |
## | opt_bramblewatch        | c1x_bramblewatch_found, c1x_elder_defeated (Knotted Elder; unlock flag)    | Chapter One additions    |
## | opt_gardeners_afternoon | c1x_found_new_crops (wild sunflax/roseberries), c1x_grew_new_crop          | farming / world          |
## | opt_tobins_shift        | c1x_annex_entered, c1x_drudge_defeated, c1x_tobin_shift (note read; the     | Tobin's annex            |
## |                         | Miner's Lamp unlock flag), ta_hatch_open                                  |                          |
## | opt_upstairs            | placed wood_stairs, placed upper_floor                                    | building                 |
## | opt_pumpkin_face        | ch2_pumpkin_harvested (a pumpkin CROP harvested; also derived by the      | farming / story tracker  |
## |                         | story tracker from Events.crop_harvested), placed pumpkin_lantern (a      | building                 |
## |                         | carved pumpkin always has a face: data.face, default the first face)      |                          |
## | opt_counts_wardrobe     | ch2_velvet_scrap_1, ch2_velvet_scrap_2, ch2_velvet_scrap_3                | manor                    |
## | opt_groundskeeper       | ch2_groundskeeper_note_1, ch2_groundskeeper_note_2,                       | reach (Candleyard)       |
## |                         | ch2_groundskeeper_light_placed (a light placed at the empty marker)       |                          |
## | opt_hat_too_large       | ch2_witch_hat_found                                                       | reach                    |
## | opt_long_way_home       | ta_hatch_open (annex hatch), ch2_shortcut_manor (mirrored by the story    | annex / manor / works    |
## |                         | tracker from the manor's mm_balcony_shortcut), ch2_refuge_shortcut        | (+ story tracker)        |
## | opt_harvest_table       | counter ch2_seasonal_dishes (distinct seasonal dishes cooked: the story    | story tracker (crafted)  |
## |                         | tracker keeps one ch2_dish_<id> flag each and set_counter_max; a kitchen  | + crafting (kitchen)     |
## |                         | module may raise it too), ch2_table_decorated (a table or Lanternwake     | story tracker (placed) / |
## |                         | Table placed; a table-decoration choice may set it too)                   | building                 |
## | opt_room_for_friends    | a companion record with home_spot; placed companion_bed or companion_perch | companions / building    |
## | opt_miner_came_back     | c1x_tobin_letter_found, ch2_hask_note_found: set by the story tracker when | annex / works lore       |
## |                         | lore lore_ch2_tobin_note (annex) / lore_ch2_hask_note (refuge) is found   | (+ story tracker)        |
## |                         | (or directly by those modules)                                            |                          |
## | opt_legacy_bond         | counter max_bond >= 5 (legacy)                                            | GameState.add_bond       |
## | opt_legacy_heartbloom   | placed heartbloom_lamp (legacy)                                           | building                 |
## The five cross-area goals (pumpkin face, long way home, harvest table, room for friends, miner who came back) are
## owned by the story module C9: src/world/story_ch2/activity_tracker.gd derives their flags from other modules'
## events and repairs them from saved state on load (src/world/story_ch2/story_ch2.gd sync_state).
## Reward flags set HERE on completion (recipe unlock flags declared in data/unlocks.gd, plus one extra):
## ch2_pumpkin_face (opt_pumpkin_face), ch2_count_wardrobe (opt_counts_wardrobe), ch2_groundskeeper_candle
## (opt_groundskeeper), ch2_harvest_table (opt_harvest_table), ch2_map_pins_upgraded (opt_long_way_home).
## Patterns come from recipes gated by those flags; a reward may also list "patterns" (wardrobe ids added
## to GameState.wardrobe.owned) when a pattern is granted directly (pat_witch_hat: data/appearance.gd).
## Reward rules (tests check both against data/sources.gd REWARDS): a bundle there with the same id
## ("rw_" + goal id) must match exactly; and a goal never gives an item kind that the content bundle
## setting one of its own objective flags already gives (e.g. rw_c1x_tobin gives the miner lamp when
## c1x_tobin_shift is set, so opt_tobins_shift does not give a second one for the same activity).

const CH2_VISIBLE := [{"type": "flag", "flag": "ch2_accepted"}]

const GOALS := [
	# --- Chapter One: optional activities (MP §7) -------------------------------------------------------
	{"id": "opt_look_of_your_own", "chapter": 1, "title": "A Look of Your Own",
		"text": "Pick an outfit and hairstyle that feel like you. Any mirror or wardrobe at home will do.",
		"visible_if": [],
		"objectives": [{"type": "flag", "flag": "c1x_look_chosen", "label": "Choose your own look"}],
		"reward": {"message": "Your wardrobe is always open at a mirror."}},
	{"id": "opt_brave_little_steps", "chapter": 1, "title": "Brave Little Steps",
		"text": "Mochi is scared of the dark below. A comfort ribbon and a lit, safe landing might help.",
		"visible_if": [{"type": "befriended", "creature": "mochi"}],
		"objectives": [
			{"type": "flag", "flag": "c1x_ribbon_given", "label": "Give Mochi a Comfort Ribbon"},
			{"type": "flag", "flag": "c1x_mochi_courage", "label": "Walk Mochi to a lit, safe landing"}],
		"reward": {"message": "Mochi feels brave enough to follow you underground."}},
	{"id": "opt_copper_courage", "chapter": 1, "title": "Copper, Not Just Courage",
		"text": "A furnace turns ore into bars, and bars into armor. Armor protects you; your look stays your own.",
		"visible_if": [{"type": "placed", "structure": "workbench", "count": 1}],
		"objectives": [
			{"type": "placed", "structure": "furnace", "count": 1, "label": "Build a Furnace"},
			{"type": "equipped", "slots": ["head", "body", "boots"], "count": 1, "label": "Wear your first piece of armor"}],
		"reward": {"give": {"copper_bar": 2}, "message": "Two spare copper bars, for the next piece."}},
	{"id": "opt_tailors_cache", "chapter": 1, "title": "The Tailor's Cache",
		"text": "Ribbons flutter on low branches near the Old Oak, as if someone wanted them followed.",
		"visible_if": [],
		"objectives": [{"type": "flag", "flag": "c1x_tailor_cache", "label": "Find the Tailor's Cache"}],
		"reward": {"give": {"woven_cloth": 2}, "message": "The cache held cloth and a loom pattern."}},
	{"id": "opt_bramblewatch", "chapter": 1, "title": "Bramblewatch",
		"text": "Past the Thornthicket, something big and knotted guards a sticky old tree.",
		"visible_if": [{"type": "flag", "flag": "ruin_cleared"}],
		"objectives": [
			{"type": "flag", "flag": "c1x_bramblewatch_found", "label": "Find Bramblewatch"},
			{"type": "flag", "flag": "c1x_elder_defeated", "label": "Face the Knotted Elder"}],
		"reward": {"give": {"sturdy_planter": 1}, "message": "Bramblewatch is quiet. A sturdy planter for your garden."}},
	{"id": "opt_gardeners_afternoon", "chapter": 1, "title": "A Gardener's Afternoon",
		"text": "Wild sunflax and roseberries grow in the Sunny Meadow. They would grow at home, too.",
		"visible_if": [{"type": "placed", "structure": "crop_plot", "count": 1}],
		"objectives": [
			{"type": "flag", "flag": "c1x_found_new_crops", "label": "Find wild Sunflax or Roseberries"},
			{"type": "flag", "flag": "c1x_grew_new_crop", "label": "Grow and harvest one at home"}],
		"reward": {"give": {"sunflax_seeds": 3, "roseberry_seeds": 3}, "message": "Your garden has room for more."}},
	{"id": "opt_tobins_shift", "chapter": 1, "title": "Tobin's Lost Shift",
		"text": "A side door by the mine mouth, stamped with a miner's name. Tobin never finished his shift.",
		"visible_if": [{"type": "flag", "flag": "mine_opened"}],
		"objectives": [
			{"type": "flag", "flag": "c1x_annex_entered", "label": "Step through Tobin's side door"},
			{"type": "flag", "flag": "c1x_drudge_defeated", "label": "Deal with the Hollow Drudge"},
			{"type": "flag", "flag": "c1x_tobin_shift", "label": "Find Tobin's service note"},
			{"type": "flag", "flag": "ta_hatch_open", "label": "Open the shortcut hatch"}],
		"reward": {"message": "Tobin's shift is finally over. His lamp can light your home now."}},
	{"id": "opt_upstairs", "chapter": 1, "title": "A House With an Upstairs",
		"text": "A home can grow up as well as out. Stairs and an upper floor, in any shape you like.",
		"visible_if": [{"type": "placed", "structure": "workbench", "count": 1}],
		"objectives": [
			{"type": "placed", "structure": "wood_stairs", "count": 1, "label": "Build stairs"},
			{"type": "placed", "structure": "upper_floor", "count": 1, "label": "Add an upper floor you can reach"}],
		"reward": {"give": {"wood_railing": 4}, "message": "Some railings, for the view from upstairs."}},
	# --- Chapter Two: side activities (MP §15) --------------------------------------------------------
	{"id": "opt_pumpkin_face", "chapter": 2, "title": "A Pumpkin With a Face",
		"text": "Grow a pumpkin in your garden, carve it a face at the workbench and give it a place to glow.",
		"visible_if": CH2_VISIBLE,
		"objectives": [
			{"type": "flag", "flag": "ch2_pumpkin_harvested", "label": "Grow and harvest a pumpkin"},
			{"type": "placed", "structure": "pumpkin_lantern", "count": 1, "label": "Carve and place a Pumpkin Lantern"}],
		"reward": {"flags": ["ch2_pumpkin_face"], "message": "Your pumpkin grins at the whole Haven. New tailoring pattern at the Loom: Pumpkin Patch."}},
	{"id": "opt_counts_wardrobe", "chapter": 2, "title": "The Count's Wardrobe",
		"text": "Three scraps of velvet are hidden in the manor's side rooms. Each has a visual clue.",
		"visible_if": CH2_VISIBLE,
		"objectives": [{"type": "flags_all", "flags": ["ch2_velvet_scrap_1", "ch2_velvet_scrap_2", "ch2_velvet_scrap_3"],
			"label": "Find the velvet scraps"}],
		"reward": {"flags": ["ch2_count_wardrobe"], "message": "New tailoring pattern: the Count's velvet cape."}},
	{"id": "opt_groundskeeper", "chapter": 2, "title": "A Candle for the Groundskeeper",
		"text": "Two notes in the Candleyard ask for a light at an empty marker.",
		"visible_if": CH2_VISIBLE,
		"objectives": [
			{"type": "flags_all", "flags": ["ch2_groundskeeper_note_1", "ch2_groundskeeper_note_2"], "label": "Read the groundskeeper's notes"},
			{"type": "flag", "flag": "ch2_groundskeeper_light_placed", "label": "Place a light at the empty marker"}],
		"reward": {"give": {"ghost_lantern": 1}, "flags": ["ch2_groundskeeper_candle"],
			"message": "The Candleyard feels calmer. A ghostlight lantern is yours."}},
	{"id": "opt_hat_too_large", "chapter": 2, "title": "A Hat Too Large",
		"text": "Fluttering ribbons lead somewhere. Something pointy is stuck at the end of them.",
		"visible_if": CH2_VISIBLE,
		"objectives": [{"type": "flag", "flag": "ch2_witch_hat_found", "label": "Rescue the stranded witch hat"}],
		"reward": {"patterns": ["pat_witch_hat"], "message": "The witch hat is safe. New pattern: Ribbon Witch Hat."}},
	{"id": "opt_long_way_home", "chapter": 2, "title": "The Long Way Home",
		"text": "Tobin's hatch, the manor's balcony stair and the refuge's garden door: every deep place has a way back, if you open it.",
		"visible_if": CH2_VISIBLE,
		"objectives": [{"type": "flags_all", "flags": ["ta_hatch_open", "ch2_shortcut_manor", "ch2_refuge_shortcut"],
			"label": "Open three shortcuts home"}],
		"reward": {"flags": ["ch2_map_pins_upgraded"], "message": "You know every way home now. Your map pins are fancier, too."}},
	{"id": "opt_harvest_table", "chapter": 2, "title": "The Harvest Table",
		"text": "Cook two different seasonal dishes (pumpkin soup, biscuits, roseberry tart, moonpetal tea or a platter) and set a table for the festival.",
		"visible_if": CH2_VISIBLE,
		"objectives": [
			{"type": "counter", "counter": "ch2_seasonal_dishes", "count": 2, "label": "Cook different seasonal dishes"},
			{"type": "flag", "flag": "ch2_table_decorated", "label": "Set a table for the festival"}],
		"reward": {"flags": ["ch2_harvest_table"], "message": "New recipes: festival candy and the Lanternwake Table."}},
	{"id": "opt_room_for_friends", "chapter": 2, "title": "A Room for Friends",
		"text": "Your friends would love a spot of their own at home. Any room shape will do.",
		"visible_if": [{"type": "flag", "flag": "chapter_one_complete"}],
		"objectives": [
			{"type": "companion_home_spot", "count": 1, "label": "Give a friend a home spot"},
			{"type": "placed_any", "structures": ["companion_bed", "companion_perch"], "count": 1, "label": "Place a companion bed or perch"}],
		"reward": {"message": "Your friends feel very at home."}},
	{"id": "opt_miner_came_back", "chapter": 2, "title": "The Miner Who Came Back",
		"text": "Tobin and Hask left notes in two very different places: one in Tobin's old annex, one in the refuge below.",
		"visible_if": CH2_VISIBLE,
		"objectives": [
			{"type": "flag", "flag": "c1x_tobin_letter_found", "label": "Find Tobin's letter in the annex"},
			{"type": "flag", "flag": "ch2_hask_note_found", "label": "Find Hask's note in the refuge"}],
		"reward": {"give": {"miner_lamp": 1}, "message": "They came back after all. A miner's lamp for your home, to keep the story lit."}},
	# --- Legacy free_play goals (data/quests.gd step 15 stays as it is) ------------------------------------------
	{"id": "opt_legacy_bond", "chapter": 1, "title": "Best of Friends", "legacy": true,
		"text": "Spend time with a companion until your bond is as strong as it can be.",
		"visible_if": [],
		"objectives": [{"type": "counter", "counter": "max_bond", "count": 5, "label": "Reach max bond with a companion"}],
		"reward": {}},
	{"id": "opt_legacy_heartbloom", "chapter": 1, "title": "A Heartbloom for Home", "legacy": true,
		"text": "The restored Ward taught you the Heartbloom Lamp. Home deserves one.",
		"visible_if": [],
		"objectives": [{"type": "placed", "structure": "heartbloom_lamp", "count": 1, "label": "Build a Heartbloom Lamp"}],
		"reward": {}},
]

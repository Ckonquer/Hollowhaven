extends RefCounted
## Chapter Two: "The Lanterns of Hallowmere" (MP §11, docs/CHAPTER_TWO_SPEC.md §7-8).
## A stable-id quest layer beside the legacy data/quests.gd chain (which is never changed).
## Driven by src/core/chapter_log.gd; the layer is active once BOTH flags `chapter_one_complete` and
## `ch2_accepted` are set. Completed steps are remembered by id (GameState "chapter2".done), never by index.
##
## Objectives are STATE checks (so doing something before the step is reached still counts, and a step
## whose objectives are already met completes the moment it is reached). Types (same as data/quests.gd):
##   {"type": "flag", "flag": "x"}                         GameState.get_flag(x) is truthy
##   {"type": "flags_all", "flags": ["a", "b"]}             progress = how many are set, target = all
##   {"type": "item", "item": "wood", "count": 3}           backpack + key pouch + equipped >= count
##   {"type": "item_any", "items": [...], "count": 2}       sum of these items >= count
##   {"type": "placed", "structure": "workbench", "count": 1}
##   {"type": "placed_any", "structures": [...], "count": 1}
##   {"type": "befriended", "creature": "mochi"}
##   {"type": "counter", "counter": "c", "count": 2, "since_start": true}
##   {"type": "discovered", "area": "hallowmere_reach", "landmark": "hr_orchard"}   (or "count": n for any n)
##   {"type": "equipped", "slots": ["head", "body", "boots"], "count": 1}
##   {"type": "companion_home_spot", "count": 1}           companions with a home spot assigned
## Optional "alt_label" on an objective and "alt_<field>" on a step are used in arachnophobia mode.
## Step keys: id, title, text, hint (shown once when the step starts), target (landmark / zone id for the
## map and tracker, a String exactly like data/quests.gd; "" = none) + target_area (the area that landmark is
## in: surface ids are data/world_layout.gd LANDMARKS, Reach ids data/hallowmere_layout.gd LANDMARKS (spec
## §7.2), Works ids the spec §7.2 zone ids), group (steps sharing a group are shown TOGETHER and can be done
## in any order), skip_if_flag (once set the step counts as done and passes silently - a failsafe so a
## sequence break never stalls the chain), on_complete {"give": {item: n}, "flags": [...], "message"}.
## on_complete is granted through GameState.grant_once("rw_" + step id, ...): exactly once, ever. When
## data/sources.gd REWARDS declares the same reward id, its items / flags must be identical (a test checks
## it): Game.complete_chapter_two() grants rw_ch2_feast from this file too, and whichever path runs first
## is the one that counts.
##
## Flags the content modules set (the ChapterLog only READS them, except on_complete flags):
##   ch2_accepted (Ward Stone choice), ch2_waygate_repaired, ch2_arch_commons, ch2_read_festival_map,
##   ch2_found_orchard_lamp, ch2_found_quarry_lamp, ch2_found_manor_lamp, ch2_garden_lamp_lit,
##   ch2_quarry_lamp_lit, ch2_manor_lamp_lit, ch2_read_preparations, ch2_lamps_linked,
##   ch2_service_gate_open, ch2_true_signal, ch2_refuge_reached, ch2_refuge_shortcut, ch2_refuge_record,
##   ch2_line_water, ch2_line_bell, ch2_line_light, ch2_crossing_cleared, ch2_false_home_revealed,
##   ch2_choir_defeated, ch2_returned_to_reach, ch2_homecoming, chapter_two_complete (set by the ending flow).
## The seals / furnishings below are granted HERE (content modules must not grant them again), and so are
## the recipe unlock flags of data/unlocks.gd that belong to this layer: ch2_orchard_restored,
## ch2_quarry_restored, ch2_manor_restored (lamp steps) and ch2_feast (final step).

const REACH := "hallowmere_reach"
const WORKS := "hushed_works"
const MANOR := "moonveil_manor"

## The step whose completion means the whole chapter is complete (Events.chapter2_completed).
const FINAL_STEP := "ch2_feast"

## Display data for steps shown together (see "group").
const GROUPS := {
	"lamps": {"title": "Three Roads, Three Lamps",
		"text": "Orchard, quarry and manor each keep a sleeping festival lamp. Wake them in any order you like."},
}

const STEPS := [
	{"id": "ch2_light_beyond", "title": "A Light Beyond", "target": "haven", "target_area": "surface",
		"text": "The Ward Stone remembers an older road: the Lanternwake trail, leading to a festival that never finished.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_accepted", "label": "Accept the Ward Stone's new inscription"}],
		"on_complete": {"message": "An old trail glimmers north of the Moonlit Ruin."}},
	{"id": "ch2_waygate", "title": "The Hallowmere Way", "target": "ruin", "target_area": "surface",
		"skip_if_flag": "ch2_arch_commons",
		"text": "North of the Moonlit Ruin, an overgrown waygate sleeps under vines. Familiar materials should wake it.",
		"hint": "Bring wood, stone and copper ore to the waygate and press {interact} to repair it.",
		"objectives": [{"type": "flag", "flag": "ch2_waygate_repaired", "label": "Repair the Lanternwake waygate"}],
		"on_complete": {"message": "The waygate hums. The road to Hallowmere Reach is open both ways."}},
	{"id": "ch2_commons", "title": "A Festival Waiting", "target": "hr_commons", "target_area": REACH,
		"text": "Lanternwake Commons waits under paper lanterns and autumn leaves, as if the festival paused mid-breath.",
		"hint": "Light the arrival arch with {interact}: lit arches are safe places and part of the Lantern Road home.",
		"objectives": [
			{"type": "flag", "flag": "ch2_arch_commons", "label": "Light the Commons arch"},
			{"type": "flag", "flag": "ch2_read_festival_map", "label": "Read the festival map"}],
		"on_complete": {"give": {"pumpkin_seeds": 3, "sunflax_seeds": 2, "roseberry_seeds": 2},
			"message": "A stallkeeper's seed pouch was left for whoever lit the arch."}},
	{"id": "ch2_outer_lamps", "title": "Three Lamps, Three Roads", "target": "hr_conservatory", "target_area": REACH,
		"skip_if_flag": "ch2_lamps_linked",
		"text": "The festival map marks three lamps: one in the orchard, one at the quarry, one at the manor.",
		"hint": "Open the map with {map}. You can take the three roads in any order.",
		"objectives": [
			{"type": "flag", "flag": "ch2_found_orchard_lamp", "label": "Find the orchard lamp"},
			{"type": "flag", "flag": "ch2_found_quarry_lamp", "label": "Find the quarry lamp"},
			{"type": "flag", "flag": "ch2_found_manor_lamp", "label": "Find the manor lamp"}],
		"on_complete": {}},
	{"id": "ch2_orchard", "title": "Pumpkins With Opinions", "group": "lamps", "target": "hr_orchard", "target_area": REACH,
		"text": "Pumpkintide Orchard is overgrown and suspicious. Its garden lamp needs water, light and a little courage.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_garden_lamp_lit", "label": "Light the garden lamp"}],
		"on_complete": {"give": {"garden_seal": 1, "pumpkin_seeds": 3}, "flags": ["ch2_orchard_restored"],
			"message": "The Garden Seal glows warm in your pouch."}},
	{"id": "ch2_quarry", "title": "The Quarry's Pulse", "group": "lamps", "target": "hr_quarry", "target_area": REACH,
		"text": "Ashbell Quarry rings with a slow, heavy pulse. Something large guards the lamp shelf.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_quarry_lamp_lit", "label": "Light the quarry lamp"}],
		"on_complete": {"give": {"quarry_seal": 1}, "flags": ["ch2_quarry_restored"],
			"message": "The Quarry Seal hums like a far-off bell."}},
	{"id": "ch2_manor", "title": "A Most Peculiar Invitation", "group": "lamps", "target": "hr_manor_grounds", "target_area": REACH,
		"text": "Moonveil Manor's door stands open, candles lit, invitation written in someone else's handwriting.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_manor_lamp_lit", "label": "Light the manor lamp"}],
		"on_complete": {"give": {"manor_seal": 1}, "flags": ["ch2_manor_restored"],
			"message": "The Manor Seal is cool as moonlight."}},
	{"id": "ch2_prepare", "title": "Made for the Journey", "target": "hr_conservatory", "target_area": REACH,
		"skip_if_flag": "ch2_lamps_linked",
		"text": "The Ward-Keeper left notes on preparing for the deep places. A practice seam waits beside the Conservatory.",
		"hint": "Better armor and tools help, but nothing here demands a full set.",
		"objectives": [{"type": "flag", "flag": "ch2_read_preparations", "label": "Read the preparation notes"}],
		"on_complete": {}},
	{"id": "ch2_lamps_linked", "title": "A Thread of True Light", "target": "hr_conservatory", "target_area": REACH,
		"text": "Three restored lamps, one pedestal. Linking them should make the roads safe and wake whatever sleeps below.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_lamps_linked", "label": "Link the three lamps at the Conservatory"}],
		"on_complete": {"message": "True light runs along every road. A stair has appeared at the Sunken Bellhouse."}},
	{"id": "ch2_service_gate", "title": "The Key Still Fits", "target": "hr_bellhouse", "target_area": REACH,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "The Bellhouse stair ends at a service gate stamped with the old mine's mark. The Foreman's Key might remember it.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_service_gate_open", "label": "Open the service gate with the Foreman's Key"}],
		"on_complete": {}},
	{"id": "ch2_true_signal", "title": "Hask's Rail", "target": "hw_rails", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "Two lights blink down the rails. Only one of them is a real lantern.",
		"hint": "Real lanterns burn steady and warm. Lights that flicker to your rhythm are not your friends.",
		"objectives": [{"type": "flag", "flag": "ch2_true_signal", "label": "Follow the true signal to the rail junction"}],
		"on_complete": {}},
	{"id": "ch2_refuge", "title": "A Pocket of Day", "target": "hw_refuge", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "Somewhere below, the miners kept a garden under glass. It might still hold a little daylight.",
		"hint": "",
		"objectives": [
			{"type": "flag", "flag": "ch2_refuge_reached", "label": "Reach the Pocket Conservatory"},
			{"type": "flag", "flag": "ch2_refuge_shortcut", "label": "Open the shortcut home"}],
		"on_complete": {}},
	{"id": "ch2_miners", "title": "What They Left", "target": "hw_refuge", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "The refuge keeps a record. Maybe it says where Hask, Tobin and the Foreman went.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_refuge_record", "label": "Recover the refuge record"}],
		"on_complete": {"message": "They made it here, and they left by the drainage route. Together."}},
	{"id": "ch2_three_lines", "title": "Wake the Lines", "target": "hw_refuge", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "Water, bell and light: three old circuits keep the lower gate shut. Restore them in any order.",
		"hint": "",
		"objectives": [
			{"type": "flag", "flag": "ch2_line_water", "label": "Restore the water line"},
			{"type": "flag", "flag": "ch2_line_bell", "label": "Restore the bell line"},
			{"type": "flag", "flag": "ch2_line_light", "label": "Restore the light line"}],
		"on_complete": {}},
	{"id": "ch2_weaver_crossing", "title": "Weaver's Crossing", "alt_title": "The Hollow Crossing",
		"target": "hw_crossing", "target_area": WORKS, "skip_if_flag": "ch2_choir_defeated",
		"text": "Pale threads span the bridge ahead. The Matron escaped the Ward's light, and she remembers you.",
		"alt_text": "Pale roots choke the bridge ahead. The Hollow Mother escaped the Ward's light, and she remembers you.",
		"hint": "Light, patience and a clear path out worked once. They will work again.",
		"objectives": [{"type": "flag", "flag": "ch2_crossing_cleared", "label": "Clear the crossing"}],
		"on_complete": {"give": {"thread_veil": 1}, "message": "A pale veil drapes over your shoulders. Something to hang at home."}},
	{"id": "ch2_false_home", "title": "The House That Isn't", "target": "hw_porch", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "A porch that looks like home, lit the way home is lit. Home is not down here.",
		"hint": "You can always step back. Look for what is missing.",
		"objectives": [{"type": "flag", "flag": "ch2_false_home_revealed", "label": "Reveal the true stair"}],
		"on_complete": {}},
	{"id": "ch2_choir", "title": "No Welcome in That Voice", "target": "hw_vault", "target_area": WORKS,
		"text": "The Borrowed Choir sings with stolen echoes. Silence it, and let the echoes go home.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_choir_defeated", "label": "Banish the Borrowed Choir"}],
		"on_complete": {"message": "The stolen echoes drift upward, free."}},
	{"id": "ch2_routes_restored", "title": "Lanterns on Every Road", "target": "hr_commons", "target_area": REACH,
		"skip_if_flag": "chapter_two_complete",
		"text": "The festival routes are brightening. Walk them back to the Commons.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_returned_to_reach", "label": "Return to Hallowmere Reach"}],
		"on_complete": {}},
	{"id": "ch2_homecoming", "title": "Bring the Celebration Home", "target": "haven", "target_area": "surface",
		"skip_if_flag": "chapter_two_complete",
		"text": "The Haven's Ward Stone should hear how it all turned out.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ch2_homecoming", "label": "Speak to the Ward Stone at home"}],
		"on_complete": {"give": {"wardlight": 1}, "flags": ["ch2_homecoming"],
			"message": "The Ward Stone gives you a Wardlight for your home."}},
	{"id": "ch2_feast", "title": "The Lanternwake", "target": "haven", "target_area": "surface",
		"text": "Every lantern is lit. Time to celebrate, at home or at the Commons.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "chapter_two_complete", "label": "Celebrate the Lanternwake"}],
		"on_complete": {"give": {"candy": 6}, "flags": ["ch2_feast"]}},
]

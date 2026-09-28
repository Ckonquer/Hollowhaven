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
## Optional "display": true on an objective makes it a signpost row: shown (tracker / journal) with its real
## done state, but never required - completion reads only the other objectives (src/core/chapter_log.gd), so
## a save that meets them without the display row never stalls. Every step keeps at least one real objective.
## Step keys: id, title, text, hint (shown once when the step starts; the journal also shows it as the step's
## tip while it is current, so it must read true wherever Krystal is), hint_when (optional objective, same
## types as below: the hint waits until it holds while the step is current - a place-bound hint shown where
## it applies, e.g. when that lamp is found), target (landmark / zone id for the
## map and tracker, a String exactly like data/quests.gd; "" = none) + target_area (the area that landmark is
## in: surface ids are data/world_layout.gd LANDMARKS, Reach ids data/hallowmere_layout.gd LANDMARKS (spec
## §7.2), Works ids the spec §7.2 zone ids), group (steps sharing a group are shown TOGETHER and can be done
## in any order; they must be consecutive in STEPS), skip_if_flag (once set the step counts as done and passes
## silently - a failsafe so a sequence break never stalls the chain), on_complete {"give": {item: n}, "flags":
## [...], "message"}.
## The lamp group (MP §9 / §11 steps 4-7): the lamp search ch2_outer_lamps and the three lamp roads are current
## TOGETHER from the moment the Commons is done, so each lit lamp completes its own road at once (seal, recipe
## flags, message) and records it independently of the other lamps (MP §9). The search completes when all
## three lamps are found; it never holds a road back (CH2-001).
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
## Lamp prerequisites - the lamp refuses to light, with its reason, until they hold. The quarry ones are the
## display rows of step ch2_quarry (shown, never required: the step completes on ch2_quarry_lamp_lit alone):
##   hr_warden_defeated (Reach east: the Quarry Warden's spawner hr_sp_quarry_warden cleared, or the arena's
##     Events.boss_defeated("quarry_warden"); its no-Warden fallback sets it too) and
##   ch2_winch_repaired (the mineral winch; also data/unlocks.gd Moonsteel knowledge) before ch2_quarry_lamp_lit.
## More content flags that no step reads (listed so nobody reuses the names):
##   ch2_velour_defeated (manor: its arena sets it on Events.boss_defeated("count_velour")) before
##     ch2_manor_lamp_lit;
##   ch2_moment_empty_waltz (manor: "The Empty Waltz" authored moment, set first, once per save).
## Set by the Reach west module (C2) for its own world state, read by nobody else: ch2_orchard_irrigated,
##   ch2_orchard_mimics_cleared, ch2_moment_pumpkin_seen / _turned / _twitched, hr_sluice_junction_garden,
##   hr_sluice_gate_open, hr_festival_seed_planted, hr_read_garden_note, hr_chime_trail_found,
##   hr_chime_trail_done (with its content bundle rw_hr_chime_trail), hr_candleyard_bench_rested.
## The seals / furnishings below are granted HERE (content modules must not grant them again), and so are
## the recipe unlock flags of data/unlocks.gd that belong to this layer: ch2_orchard_restored,
## ch2_quarry_restored, ch2_manor_restored (lamp steps), ch2_homecoming (home decoration: the Wardlight) and
## ch2_feast (final step: the Lanternwake outfit pattern). Two non-recipe flags are set here too (story module
## C9): ch2_safe_light_routes (step ch2_lamps_linked: the persistent safe-light routes are a committed reward -
## the region's road lights, src/world/reach/road_lights.gd, stay lit; any system may read it) and
## ch2_trials_open (step ch2_routes_restored): a story marker; nothing gates on it - each echo trial opens when
## its boss is defeated (lead decision, pass 2).
## Texts, hints, targets and rewards follow MP §11 (story module C9). The ending (Game.complete_chapter_two)
## commits rw_ch2_feast = the final step's give + flags + Game.chapter_two_rewards()'s continued resources (the
## step's give already lists those same amounts, story_ch2.gd FEAST_EXTRAS, so both paths pay the same); the
## Lanternwake outfit is owned and the gothic / cottage furnishing finishes (dye palettes) are unlocked with that
## same ledger entry (src/world/story_ch2/story_ch2.gd sync_feast_unlocks). Hints may use the {tokens} of
## src/ui/ui_util.gd TOKEN_ACTIONS; alt_<field> = arachnophobia wording.

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
		"text": "The Ward Stone has a new inscription: an older road, lanterns beyond these woods, and a festival that never finished.",
		"hint": "Read the Ward Stone with {interact}. Stay as long as you like: the road will keep.",
		"objectives": [{"type": "flag", "flag": "ch2_accepted", "label": "Accept the Ward Stone's new inscription"}],
		"on_complete": {"message": "An old trail glimmers north of the Moonlit Ruin. Everything you won here stays won."}},
	{"id": "ch2_waygate", "title": "The Hallowmere Way", "target": "ruin", "target_area": "surface",
		"skip_if_flag": "ch2_arch_commons",
		"text": "North of the Moonlit Ruin, an overgrown waygate sleeps under vines. Familiar materials should wake it.",
		"hint": "Bring wood, stone and copper ore to the waygate and press {interact} to repair it.",
		"objectives": [{"type": "flag", "flag": "ch2_waygate_repaired", "label": "Repair the Lanternwake waygate"}],
		"on_complete": {"message": "The waygate hums. The road to Hallowmere Reach is open both ways."}},
	{"id": "ch2_commons", "title": "A Festival Waiting", "target": "hr_commons", "target_area": REACH,
		"text": "Lanternwake Commons waits under paper lanterns and copper leaves, as if the festival paused mid-breath.",
		"hint": "Light the arrival arch with {interact}: lit arches are safe places and part of the Lantern Road home.",
		"objectives": [
			{"type": "flag", "flag": "ch2_arch_commons", "label": "Light the Commons arch"},
			{"type": "flag", "flag": "ch2_read_festival_map", "label": "Read the festival map"}],
		"on_complete": {"give": {"pumpkin_seeds": 3, "sunflax_seeds": 2, "roseberry_seeds": 2},
			"message": "A stallkeeper's seed pouch was left for whoever lit the arch."}},
	# The lamp search: in the lamp group (shown with the three roads, never holding them back). Its target is the
	# Conservatory, the hub the three roads start from.
	{"id": "ch2_outer_lamps", "title": "Find the Three Lamps", "group": "lamps", "target": "hr_conservatory", "target_area": REACH,
		"skip_if_flag": "ch2_lamps_linked",
		"text": "The festival map marks three sleeping lamps: one in the orchard, one at the quarry, one at the manor.",
		"hint": "Open the map with {map}. The three roads start at the Conservatory; take them in any order.",
		"objectives": [
			{"type": "flag", "flag": "ch2_found_orchard_lamp", "label": "Find the orchard lamp"},
			{"type": "flag", "flag": "ch2_found_quarry_lamp", "label": "Find the quarry lamp"},
			{"type": "flag", "flag": "ch2_found_manor_lamp", "label": "Find the manor lamp"}],
		"on_complete": {"message": "All three festival lamps found. Wake any still sleeping, in whatever order you like."}},
	{"id": "ch2_orchard", "title": "Pumpkins With Opinions", "group": "lamps", "target": "hr_orchard", "target_area": REACH,
		"text": "Pumpkintide Orchard is overgrown and suspicious. Its garden lamp needs water, light and a little courage.",
		"hint": "Send the irrigation water back to the beds. Pumpkins in the marked pockets are not all pumpkins.",
		"hint_when": {"type": "flag", "flag": "ch2_found_orchard_lamp"},
		"objectives": [{"type": "flag", "flag": "ch2_garden_lamp_lit", "label": "Light the garden lamp"}],
		"on_complete": {"give": {"garden_seal": 1, "pumpkin_seeds": 3}, "flags": ["ch2_orchard_restored"],
			"message": "The Garden Seal glows warm in your pouch. New recipes: carved pumpkins and pumpkin cooking."}},
	{"id": "ch2_quarry", "title": "The Quarry's Pulse", "group": "lamps", "target": "hr_quarry", "target_area": REACH,
		"text": "Ashbell Quarry rings with a slow, heavy pulse. Something large guards the lamp shelf.",
		"hint": "The Quarry Warden guards the lamp. Mend the old winch to reach the upper terraces.",
		"hint_when": {"type": "flag", "flag": "ch2_found_quarry_lamp"},
		"objectives": [
			{"type": "flag", "flag": "hr_warden_defeated", "label": "Calm the Quarry Warden", "display": true},
			{"type": "flag", "flag": "ch2_winch_repaired", "label": "Mend the mineral winch", "display": true},
			{"type": "flag", "flag": "ch2_quarry_lamp_lit", "label": "Light the quarry lamp"}],
		"on_complete": {"give": {"quarry_seal": 1}, "flags": ["ch2_quarry_restored"],
			"message": "The Quarry Seal hums like a far-off bell. New recipes: Ironwood tools, sword and armor."}},
	{"id": "ch2_manor", "title": "A Most Peculiar Invitation", "group": "lamps", "target": "hr_manor_grounds", "target_area": REACH,
		"text": "Moonveil Manor's door stands open, candles lit, the invitation written in someone else's handwriting.",
		"hint": "Candles and mirrors tell the truth in Moonveil Manor. Follow the light, not the invitation.",
		"hint_when": {"type": "flag", "flag": "ch2_found_manor_lamp"},
		"objectives": [{"type": "flag", "flag": "ch2_manor_lamp_lit", "label": "Light the manor lamp"}],
		"on_complete": {"give": {"manor_seal": 1}, "flags": ["ch2_manor_restored"],
			"message": "The Manor Seal is cool as moonlight. New tailoring patterns: Ribbon Witch and Velvet Vampire."}},
	{"id": "ch2_prepare", "title": "Made for the Journey", "target": "hr_conservatory", "target_area": REACH,
		"skip_if_flag": "ch2_lamps_linked",
		"text": "The Ward-Keeper left notes on preparing for the deep places. A practice seam waits beside the Conservatory.",
		"hint": "Better armor and tools help, but nothing here demands a full set. See what you can make with {craft}.",
		"objectives": [{"type": "flag", "flag": "ch2_read_preparations", "label": "Read the preparation notes"}],
		"on_complete": {"message": "One good upgrade goes a long way. Friends and a lantern go further."}},
	{"id": "ch2_lamps_linked", "title": "A Thread of True Light", "target": "hr_conservatory", "target_area": REACH,
		"text": "Three restored lamps, one pedestal. Linking them should make the roads safe and wake whatever sleeps below.",
		"hint": "Bring the three seals to the Conservatory pedestal and press {interact}.",
		"objectives": [{"type": "flag", "flag": "ch2_lamps_linked", "label": "Link the three lamps at the Conservatory"}],
		"on_complete": {"flags": ["ch2_safe_light_routes"],
			"message": "True light runs along every road. A stair has appeared at the Sunken Bellhouse."}},
	{"id": "ch2_service_gate", "title": "The Key Still Fits", "target": "hr_bellhouse", "target_area": REACH,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "The Bellhouse stair ends at a service gate stamped with the old mine's mark. The Foreman's Key might remember it.",
		"hint": "The Foreman's Key is in your key pouch ({inventory}). Opening the gate with it does not use it up.",
		"objectives": [{"type": "flag", "flag": "ch2_service_gate_open", "label": "Open the service gate with the Foreman's Key"}],
		"on_complete": {"message": "The Foreman's Key turns once, then goes back into your pouch."}},
	{"id": "ch2_true_signal", "title": "Hask's Rail", "target": "hw_rails", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "Two lights blink down the rails. Only one of them is a real lantern.",
		"hint": "Real lanterns burn steady and warm. Lights that flicker to your rhythm are not your friends.",
		"objectives": [{"type": "flag", "flag": "ch2_true_signal", "label": "Follow the true signal to the rail junction"}],
		"on_complete": {"message": "A true light stays with what holds it."}},
	{"id": "ch2_refuge", "title": "A Pocket of Day", "target": "hw_refuge", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "Somewhere below, the miners kept a garden under glass. It might still hold a little daylight.",
		"hint": "The refuge is safe: rest, save, and open the shortcut home before going deeper.",
		"objectives": [
			{"type": "flag", "flag": "ch2_refuge_reached", "label": "Reach the Pocket Conservatory"},
			{"type": "flag", "flag": "ch2_refuge_shortcut", "label": "Open the shortcut home"}],
		"on_complete": {"message": "A way home from the deep, any time you need it."}},
	{"id": "ch2_miners", "title": "What They Left", "target": "hw_refuge", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "The refuge keeps a record. Maybe it says where Hask, Tobin and the Foreman went.",
		"hint": "Look around the refuge garden and read what you find with {interact}. Nothing hunts here.",
		"objectives": [{"type": "flag", "flag": "ch2_refuge_record", "label": "Recover the refuge record"}],
		"on_complete": {"message": "They made it here, and they left by the drainage route. Together."}},
	{"id": "ch2_three_lines", "title": "Wake the Lines", "target": "hw_refuge", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "Water, bell and light: three old circuits keep the lower gate shut. Restore them in any order.",
		"hint": "Each line works differently. Big symbols and captions show when a line wakes, even with the sound off.",
		"objectives": [
			{"type": "flag", "flag": "ch2_line_water", "label": "Restore the water line"},
			{"type": "flag", "flag": "ch2_line_bell", "label": "Restore the bell line"},
			{"type": "flag", "flag": "ch2_line_light", "label": "Restore the light line"}],
		"on_complete": {"message": "Three lines hum together. The lower gate is listening."}},
	{"id": "ch2_weaver_crossing", "title": "Weaver's Crossing", "alt_title": "The Hollow Crossing",
		"target": "hw_crossing", "target_area": WORKS, "skip_if_flag": "ch2_choir_defeated",
		"text": "Pale threads span the bridge ahead. The Matron escaped the Ward's light, and she remembers you.",
		"alt_text": "Pale roots choke the bridge ahead. The Hollow Mother escaped the Ward's light, and she remembers you.",
		"hint": "Light, patience and a clear path out worked once. They will work again. A checkpoint lantern waits just before the bridge.",
		"objectives": [{"type": "flag", "flag": "ch2_crossing_cleared", "label": "Clear the crossing"}],
		"on_complete": {"give": {"thread_veil": 1}, "message": "The crossing is clear. A pale veil drape is yours to hang at home, and your Heartseed stays in its stone."}},
	{"id": "ch2_false_home", "title": "The House That Isn't", "target": "hw_porch", "target_area": WORKS,
		"skip_if_flag": "ch2_choir_defeated",
		"text": "A porch that looks like home, lit the way home is lit. Home is not down here.",
		"hint": "You can always step back. Look for what is missing: its lamps cast no light.",
		"objectives": [{"type": "flag", "flag": "ch2_false_home_revealed", "label": "Reveal the true stair"}],
		"on_complete": {"message": "Only a facade. Your real home is exactly where you left it."}},
	{"id": "ch2_choir", "title": "No Welcome in That Voice", "target": "hw_vault", "target_area": WORKS,
		"text": "It has learned a welcome. It has not learned a home. The Borrowed Choir sings with stolen echoes: silence it, and let the echoes go home.",
		"hint": "Rest at the Bell Throat first; you can still turn back from there. True light shows what the Choir hides.",
		"objectives": [{"type": "flag", "flag": "ch2_choir_defeated", "label": "Banish the Borrowed Choir"}],
		"on_complete": {"message": "The stolen echoes drift upward, free. The outer ward shines again."}},
	{"id": "ch2_routes_restored", "title": "Lanterns on Every Road", "target": "hr_commons", "target_area": REACH,
		"skip_if_flag": "chapter_two_complete",
		"text": "The quiet below is quiet again. Up in the Reach, the festival lamps are waking along every road.",
		"hint": "Ride the vault's bell-lift up to the Sunken Bellhouse, back in Hallowmere Reach. The refuge shortcut works too.",
		"objectives": [{"type": "flag", "flag": "ch2_returned_to_reach", "label": "Return to Hallowmere Reach"}],
		"on_complete": {"flags": ["ch2_trials_open"],
			"message": "The festival roads are bright again. Old echoes stir, should you ever want a trial."}},
	{"id": "ch2_homecoming", "title": "Bring the Celebration Home", "target": "haven", "target_area": "surface",
		"skip_if_flag": "chapter_two_complete",
		"text": "The Haven's Ward Stone should hear how it all turned out.",
		"hint": "Any lit arch takes you home on the Lantern Road ({interact}). Then speak to the Ward Stone.",
		"objectives": [{"type": "flag", "flag": "ch2_homecoming", "label": "Speak to the Ward Stone at home"}],
		"on_complete": {"give": {"wardlight": 1}, "flags": ["ch2_homecoming"],
			"message": "The Ward Stone gives you a Wardlight for your home, and the pattern to make more."}},
	{"id": "ch2_feast", "title": "The Lanternwake", "target": "haven", "target_area": "surface",
		"text": "Every lantern is lit. Celebrate the Lanternwake: at home with the Ward Stone, or at the Commons.",
		"hint": "Choose Celebrate at the Ward Stone or at the Commons festival lantern ({interact}). Nothing is placed in your house.",
		"objectives": [{"type": "flag", "flag": "chapter_two_complete", "label": "Celebrate the Lanternwake"}],
		"on_complete": {"give": {"candy": 6, "pumpkin": 4, "lantern_wax": 4, "sugarcap": 3, "moonpetal": 3}, "flags": ["ch2_feast"],
			"message": "The Lanternwake's gifts are yours: a festival outfit, new furniture finishes and a few supplies."}},
]

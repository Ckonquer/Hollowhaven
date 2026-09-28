extends RefCounted
## Chapter Two story glue (module C9; docs/CHAPTER_TWO_SPEC.md §3.5 / §8, MP §9 / §11 steps 18-20 / §15 / §17).
## Static helpers shared by the Ward Stone, the Commons festival lantern, Game's ending presentation, the
## Reach / Haven dressings and the cross-area activity tracker. Everything here is derived from saved
## GameState (flags, ledger, lore, structures), so a reload or a crash never loses or repeats anything:
##   * returning to the Reach after the Choir: ch2_returned_to_reach (step 18) + the festival roads brighten
##     and the Commons pole becomes the Lanternwake lantern (reach_dressing.gd reads the flags when the region
##     is built);
##   * the homecoming (step 19) is set by the Ward Stone; this adds its journal note and the celebrate hint;
##   * the Lanternwake (step 20): celebrate() -> Game.complete_chapter_two(Game.chapter_two_rewards()); the
##     ledger entry rw_ch2_feast also carries the Lanternwake festival outfit pattern and the gothic / cottage
##     furnishing finishes (dye palettes), unlocked by sync_feast_unlocks() whenever that entry exists (the
##     tracker does it synchronously inside grant_once, i.e. before the ending's save);
##   * cross-area optional goals (data/optional_goals.gd): derived flags / counters from other modules' events.
## Rewards themselves only ever go through GameState.grant_once (the chapter log and Game.complete_chapter_two).

const Reach := preload("res://data/hallowmere_layout.gd")

# --- Story flags ------------------------------------------------------------------------------------------
const ACCEPTED_FLAG := "ch2_accepted"
const CHOIR_FLAG := "ch2_choir_defeated"
const RETURNED_FLAG := "ch2_returned_to_reach"
const HOMECOMING_FLAG := "ch2_homecoming"
const COMPLETE_FLAG := "chapter_two_complete"
const SAFE_ROUTES_FLAG := "ch2_safe_light_routes"     # step ch2_lamps_linked on_complete: persistent safe-light routes
const TRIALS_FLAG := "ch2_trials_open"                # step ch2_routes_restored on_complete (optional trials)
const REACH_AREA := "hallowmere_reach"
const HAVEN_AREA := "surface"
const ACCEPT_CHOICE := "ch2_lantern_road"             # Events.choice_made id of the Ward Stone invitation

# --- The Lanternwake rewards (MP §17) ------------------------------------------------------------------------
const FEAST_REWARD := "rw_ch2_feast"
const FEAST_PATTERN := "pat_lanternwake"              # Lanternwake festival outfit (dress, bodice, crown, ...)
## Gothic and cottage furnishing finishes: dye palettes that recolour any tintable furniture in place.
const FEAST_PALETTES := ["midnight", "cream"]
## "Continued resources" committed with rw_ch2_feast (Game.chapter_two_rewards merges them per item with max). The
## final step's give (data/quests_ch2.gd ch2_feast) and data/sources.gd REWARDS rw_ch2_feast list these same
## amounts next to the candy, so the ledger entry pays the same whichever path grants it first.
const FEAST_EXTRAS := {"pumpkin": 4, "lantern_wax": 4, "sugarcap": 3, "moonpetal": 3}

# --- Cross-area optional goals (data/optional_goals.gd) ------------------------------------------------------
## Lore notes found by other modules -> the objective flags of "The Miner Who Came Back": Tobin's personal letter
## (annex locker nine) and Hask's note in the refuge planter. Those modules set the flags themselves; this repairs
## them from the journal. (Tobin's service note and Hask's rail lamp-post note are other notes: they never tick
## these objectives. A flag an older build already set from them simply stays set.)
const LORE_FLAGS := {"lore_ch2_tobin_letter": "c1x_tobin_letter_found", "lore_ch2_hask_refuge_note": "ch2_hask_note_found"}
## Flags set by other modules -> the (namespaced) objective flag this module mirrors them to.
const FLAG_ALIASES := {"mm_balcony_shortcut": "ch2_shortcut_manor"}
## "The Harvest Table": different seasonal dishes cooked (one flag each, counted into the counter).
const SEASONAL_DISHES := ["pumpkin_soup", "pumpkin_biscuit", "roseberry_tart", "moonpetal_tea", "lanternwake_platter"]
const DISH_FLAG_PREFIX := "ch2_dish_"
const DISH_COUNTER := "ch2_seasonal_dishes"
## ... and the festival table dressed: the Kitchen's festival-table choice (Crafting.decorate_table sets the flag and
## remembers the choice in GameState.stations[TABLE_DECOR_KEY]) or a placed Lanternwake Table. A plain Chapter One
## table no longer counts (MP 15: choose a table decoration). A flag already set stays set.
const TABLE_STRUCTURES := ["lanternwake_table"]
const TABLE_FLAG := "ch2_table_decorated"
const TABLE_DECOR_KEY := "table_decor"
## "A Pumpkin With a Face": a pumpkin grown and harvested from a crop plot.
const PUMPKIN_CROP := "pumpkin"
const PUMPKIN_FLAG := "ch2_pumpkin_harvested"

# --- Journal (data/lore_ch2_story.gd) ------------------------------------------------------------------------
const LORE_ROUTES := "lore_ch2_every_road"
const LORE_HOMECOMING := "lore_ch2_homecoming"
const LORE_LANTERNWAKE := "lore_ch2_lanternwake"
## Step reward flags this module added to data/quests_ch2.gd on_complete after those steps could already have
## been completed in a save (the ledger entry rw_<step> then exists, so grant_once refuses them): repaired from
## that ledger entry on load - the chapter log's own proof that the step was paid.
const STEP_FLAG_REPAIRS := {"ch2_lamps_linked": SAFE_ROUTES_FLAG, "ch2_routes_restored": TRIALS_FLAG}
## flag -> the journal note that tells its story (repaired from the flag on load).
const STORY_LORE := {"ch2_returned_to_reach": "lore_ch2_every_road", "ch2_homecoming": "lore_ch2_homecoming",
	"chapter_two_complete": "lore_ch2_lanternwake"}

# --- Presentation --------------------------------------------------------------------------------------------
const CARD_TITLE := "Chapter Two"
const CARD_SUBTITLE := "The Lanterns of Hallowmere"
const ROUTES_NOTICE := "Every festival lamp along the roads is lit again."
const CELEBRATE_HINT := "The Ward Stone will celebrate the Lanternwake with you: press {interact} and choose Celebrate. The festival lantern at the Commons works too."
const REACH_DRESSING := "res://src/world/story_ch2/reach_dressing.gd"
const HAVEN_DRESSING := "res://src/world/story_ch2/haven_dressing.gd"
const CELEBRATION := "res://src/world/story_ch2/celebration.gd"
const TRACKER := "res://src/world/story_ch2/activity_tracker.gd"

## Tests / QA: the venue of the last celebrate() call ("haven" | "commons").
static var last_venue: String = ""
## Length of the in-world celebration before the ending card (tests shorten it; players can skip it).
static var celebration_seconds: float = 9.0


static func flag(name: String) -> bool:
	return true if GameState.get_flag(name) else false


# --- The ending ------------------------------------------------------------------------------------------------

## The final beat can be chosen: the homecoming happened and the chapter is not complete yet.
static func can_celebrate() -> bool:
	return flag(HOMECOMING_FLAG) and not flag(COMPLETE_FLAG)


## Runs the Lanternwake (MP §11 step 20) from the Ward Stone ("haven") or the Commons lantern ("commons"):
## Game.complete_chapter_two() commits the rewards and saves FIRST, then plays the celebration and the
## ending. Awaitable; true when this call completed the chapter.
static func celebrate(venue: String) -> bool:
	if not can_celebrate():
		return false
	last_venue = venue
	var rewards: Dictionary = Game.chapter_two_rewards() if Game.has_method("chapter_two_rewards") else {}
	return bool(await Game.complete_chapter_two(rewards))


## Items committed with rw_ch2_feast on top of the final step's give (known item ids only).
static func feast_extras() -> Dictionary:
	var out := {}
	for id in FEAST_EXTRAS:
		if ItemDB.has_item(String(id)):
			out[String(id)] = int(FEAST_EXTRAS[id])
	return out


## The wardrobe / furnishing unlocks that belong to the rw_ch2_feast ledger entry: the Lanternwake outfit
## pattern and the gothic (Midnight) / cottage (Cream) finishes. Idempotent; true when something was new.
## Called by the tracker from Events.reward_granted (inside grant_once, before the ending's save), by the
## ending presentation (fallback) and on every load (repair).
static func sync_feast_unlocks() -> bool:
	if not GameState.has_reward(FEAST_REWARD):
		return false
	var changed := false
	if not ItemDB.pattern(FEAST_PATTERN).is_empty() and GameState.unlock_pattern(FEAST_PATTERN):
		changed = true
	var pal: Array = []
	var cur: Variant = GameState.wardrobe.get("palettes", [])
	if cur is Array:
		pal = cur
	for p in FEAST_PALETTES:
		if not ItemDB.dye_palette(String(p)).is_empty() and not pal.has(String(p)):
			pal.append(String(p))
			changed = true
	GameState.wardrobe["palettes"] = pal
	if changed:
		Events.appearance_changed.emit()
	return changed


## A short recap of what the Lanternwake leaves at home (shown by the ending screen). Only what is true
## for this save is listed.
static func feast_recap() -> Array:
	var out: Array = []
	var owned: Variant = GameState.wardrobe.get("owned", [])
	if owned is Array and (owned as Array).has(FEAST_PATTERN):
		out.append("the Lanternwake festival outfit")
	var pal: Variant = GameState.wardrobe.get("palettes", [])
	if pal is Array and (pal as Array).has("midnight") and (pal as Array).has("cream"):
		out.append("Gothic Midnight and Cottage Cream finishes for your furniture")
	if GameState.has_reward("rw_ch2_homecoming") or GameState.count_item("wardlight") > 0 or GameState.count_structures("wardlight") > 0:
		out.append("a Wardlight for your home")
	if GameState.has_reward(FEAST_REWARD):
		out.append("festival treats and supplies")
	return out


# --- Returning, homecoming -------------------------------------------------------------------------------------

## Area arrival bookkeeping: back in the Reach after the Choir = ch2_returned_to_reach (+ journal note, a
## notice). Returns true when the flag was set by this call.
static func note_area(area_id: String) -> bool:
	if area_id != REACH_AREA or not flag(CHOIR_FLAG) or flag(RETURNED_FLAG):
		return false
	GameState.set_flag(RETURNED_FLAG, true)
	GameState.discover_lore(LORE_ROUTES)
	Events.notify.emit(ROUTES_NOTICE, "info")
	return true


## Called by the Ward Stone right after it sets ch2_homecoming (the MP §17 return line is its own).
static func on_homecoming() -> void:
	GameState.discover_lore(LORE_HOMECOMING)
	if can_celebrate():
		Events.hint.emit("ch2_celebrate", CELEBRATE_HINT)


## After the ending presentation: the journal note and the lasting festival dressing in this area.
static func after_ending() -> void:
	GameState.discover_lore(LORE_LANTERNWAKE)
	var area: Node = Game.area
	if area != null and is_instance_valid(area) and area is Node3D:
		ensure_dressing(area as Node3D, Game.area_id, true)


## Adds this module's dressing to an area that did not build it itself (idempotent). `rebuild` replaces an
## existing one (the flags changed while the area was loaded, e.g. right after the ending).
static func ensure_dressing(area: Node3D, area_id: String, rebuild: bool = false) -> Node:
	var path := ""
	if area_id == REACH_AREA:
		path = REACH_DRESSING
	elif area_id == HAVEN_AREA:
		path = HAVEN_DRESSING
	if path == "" or area == null or not is_instance_valid(area) or not ResourceLoader.exists(path):
		return null
	var s: Script = load(path)
	if s == null or not s.can_instantiate():
		return null
	var node_name := String(s.get_script_constant_map().get("NODE_NAME", ""))
	var old: Node = area.get_node_or_null(node_name) if node_name != "" else null
	if old != null:
		if not rebuild:
			return old
		area.remove_child(old)
		old.queue_free()
	return s.call("build", area)


## The celebration presentation node for the current area (null when there is no area to stage it in).
static func start_celebration() -> Node:
	var area: Node = Game.area
	if area == null or not is_instance_valid(area) or not (area is Node3D) or not area.is_inside_tree():
		return null
	if not ResourceLoader.exists(CELEBRATION):
		return null
	var s: Script = load(CELEBRATION)
	if s == null or not s.can_instantiate():
		return null
	var cel: Node = s.new()
	cel.call("setup", {"area": area, "area_id": Game.area_id, "player": Game.player, "duration": celebration_seconds})
	area.add_child(cel)
	return cel


# --- Cross-area activity tracking (pure state; the tracker node feeds events in) -------------------------------

## Derives every tracked flag / counter from saved state. Safe to call any time; true when something changed.
static func sync_state() -> bool:
	var changed := false
	for lid in LORE_FLAGS:
		if GameState.lore.has(lid) and not flag(String(LORE_FLAGS[lid])):
			GameState.set_flag(String(LORE_FLAGS[lid]), true)
			changed = true
	for src in FLAG_ALIASES:
		if flag(String(src)) and not flag(String(FLAG_ALIASES[src])):
			GameState.set_flag(String(FLAG_ALIASES[src]), true)
			changed = true
	var dishes := dish_count()
	if dishes > GameState.get_counter(DISH_COUNTER):
		GameState.set_counter_max(DISH_COUNTER, dishes)
		changed = true
	if not flag(TABLE_FLAG) and table_dressed():
		GameState.set_flag(TABLE_FLAG, true)
		changed = true
	if sync_feast_unlocks():
		changed = true
	for sid in STEP_FLAG_REPAIRS:
		if GameState.has_reward("rw_" + String(sid)) and not flag(String(STEP_FLAG_REPAIRS[sid])):
			GameState.set_flag(String(STEP_FLAG_REPAIRS[sid]), true)
			changed = true
	for f in STORY_LORE:
		if flag(String(f)) and not GameState.lore.has(String(STORY_LORE[f])):
			GameState.discover_lore(String(STORY_LORE[f]))
			changed = true
	return changed


static func note_lore(lore_id: String) -> void:
	if LORE_FLAGS.has(lore_id):
		GameState.set_flag(String(LORE_FLAGS[lore_id]), true)


static func note_flag(flag_name: String, value: Variant) -> void:
	if FLAG_ALIASES.has(flag_name) and value:
		GameState.set_flag(String(FLAG_ALIASES[flag_name]), true)


## A crafted / cooked item: a seasonal dish not cooked before counts once towards "The Harvest Table".
static func note_crafted(item_id: String) -> void:
	if not SEASONAL_DISHES.has(item_id):
		return
	var f := DISH_FLAG_PREFIX + item_id
	if not flag(f):
		GameState.set_flag(f, true)
	GameState.set_counter_max(DISH_COUNTER, dish_count())


static func note_structure(structure_id: String) -> void:
	if TABLE_STRUCTURES.has(structure_id) and not flag(TABLE_FLAG):
		GameState.set_flag(TABLE_FLAG, true)


static func note_crop(crop_id: String) -> void:
	if crop_id == PUMPKIN_CROP and not flag(PUMPKIN_FLAG):
		GameState.set_flag(PUMPKIN_FLAG, true)


## The saved state says the festival table was dressed: a Kitchen decoration choice or a placed Lanternwake Table.
static func table_dressed() -> bool:
	var choice: Variant = GameState.stations.get(TABLE_DECOR_KEY, "")
	if choice is String and String(choice) != "":
		return true
	for sid in TABLE_STRUCTURES:
		if GameState.count_structures(String(sid)) > 0:
			return true
	return false


## How many different seasonal dishes have been cooked (one flag each).
static func dish_count() -> int:
	var n := 0
	for id in SEASONAL_DISHES:
		if flag(DISH_FLAG_PREFIX + String(id)):
			n += 1
	return n


# --- Debug (never in release) --------------------------------------------------------------------------------

## Debug builds only (Debug.is_cheat_allowed()): jump a save to a closing beat to check the story glue by hand.
## beat "choir" = every Chapter Two objective flag up to the Choir; "home" = + back in the Reach; "celebrate" =
## + the homecoming (the Ward Stone / Commons lantern then offer "Celebrate"). The chapter log pays the step
## rewards as usual when it evaluates. Returns false (and does nothing) in release or for an unknown beat.
## Command line (read by the tracker on the first area load): -- --story-ch2=celebrate
static func debug_state(beat: String) -> bool:
	if not Debug.is_cheat_allowed():
		return false
	var last := {"choir": "ch2_choir", "home": "ch2_routes_restored", "celebrate": "ch2_homecoming"}
	if not last.has(beat):
		return false
	for f in ["ward_restored", "chapter_one_complete"]:
		GameState.set_flag(f, true)
	var quests: Script = load("res://data/quests_ch2.gd")
	for st in quests.get_script_constant_map().get("STEPS", []):
		for o in (st as Dictionary).get("objectives", []):
			if String((o as Dictionary).get("type", "")) == "flag":
				GameState.set_flag(String(o["flag"]), true)
			for f2 in (o as Dictionary).get("flags", []):
				GameState.set_flag(String(f2), true)
		if String((st as Dictionary)["id"]) == String(last[beat]):
			break
	GameState.request_quest_eval()
	return true


## Tests / debug: a tracker node (normally created once by Game, see the module report).
static func new_tracker() -> Node:
	if not ResourceLoader.exists(TRACKER):
		return null
	var s: Script = load(TRACKER)
	return s.new() if s != null and s.can_instantiate() else null

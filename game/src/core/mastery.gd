extends RefCounted
## Small masteries (MP 5.3, docs/CHAPTER_TWO_SPEC.md 4.7 / 9): three persistent five-rank tracks
## (gathering / hearthcraft / wayfinding) earned through ordinary play. Static and autoload-free; all state
## lives in GameState.mastery:
##   {"gathering": xp, "hearthcraft": xp, "wayfinding": xp,
##    "seen": {track: ["<rule>:<id>", ...]},             first-time kinds already rewarded (never repeat)
##    "daily": {"day": int, "xp": {"<track>:<rule>": n}},  repeatable xp used today (capped per in-game day)
##    "legacy_credit": false | {"applied": true, "at": total_minutes, "xp": {track: n}},
##    "spots": {area: {kind: [[x, z], ...]}}}           harvested resource spots (bounded, data SPOT_*)
## Numbers (xp per rule, caps, rank thresholds, rewards, legacy formula) are data: data/mastery.gd via ItemDB.
##
##   const Mastery := preload("res://src/core/mastery.gd")
##   Mastery.init()                                   once (GameState/Game _ready); connects Events listeners
##   Mastery.award("hearthcraft", "first_recipe:stone_axe") -> int   xp actually awarded (0 = deduped / capped)
##   Mastery.rank("gathering") -> int                0..5
##   Mastery.gather_power() / bonus_yield_chance() / furnace_queue_bonus() / station_time_mult() /
##   meal_buff_bonus() / sprint_stamina_save()        small effects for Stats / stations / food (data values)
##   Mastery.apply_legacy_credit() -> {track: xp}     once per save (recorded), conservative, capped; also records the
##                                                    Chapter One landmarks the save proves visited as seen (no xp)
##   Mastery.known_spots(area) -> [{"kind", "pos": Vector2}]   recorded resource spots (Wayfinding 2 map pins)
##   Mastery.cache_hints(area) -> [{"id", "pos": Vector2, "district"}]   unfound caches in discovered districts
##   Mastery.resource_pins_on() / cache_hints_on() / highlight_radius()   rank rewards the map / world read
##
## Exploit resistance (MP 5.3): first-time rules dedupe on "<rule>:<id>" (re-placing a dismantled piece,
## re-crafting, reloading never repeat them); repeatable rules are capped per in-game day; nothing listens to
## chest shuffling, equipping, restyling, loading or healing, and data NO_XP rules always award 0. No rank ever
## gates a story recipe (data/recipes.gd `mastery` gates only decorative pieces; tested).

const MasteryData := preload("res://data/mastery.gd")

## Flags that mark the first clear of a distinct authored encounter -> canonical encounter id (bosses use the
## same ids as Events.boss_defeated, so a boss counted by its flag and by the signal is still one encounter:
## award() dedupes on "encounter:<id>"). hr_warden_defeated = data/reach_east.gd FLAG_WARDEN (quarry_warden.gd
## BAR_ID), ch2_velour_defeated = data/manor_layout.gd FLAG_VELOUR_DEFEATED (count_velour.gd BOSS_ID).
const ENCOUNTER_FLAGS := {
	"ruin_cleared": "thornthicket", "weaver_defeated": "weaver_matron", "c1x_elder_defeated": "knotted_elder",
	"c1x_drudge_defeated": "hollow_drudge", "ch2_crossing_cleared": "crossing_matron",
	"ch2_choir_defeated": "borrowed_choir", "hr_warden_defeated": "quarry_warden",
	"ch2_velour_defeated": "count_velour",
}
## Return shortcuts (spec §1 / optional goal "The Long Way Home").
const SHORTCUT_FLAGS := ["ta_hatch_open", "ch2_shortcut_quarry", "ch2_shortcut_manor", "ch2_refuge_shortcut"]
## Workshop stations whose first use is worth hearthcraft xp (data rule first_station_use).
const WORKSHOP_STATIONS := ["furnace", "loom", "kitchen"]

static var _wired := false
static var _fx_code := -1
static var _fx_cache: Dictionary = {}
static var _last_harvest_frame := -1
static var _last_harvest_pos := Vector3.INF
static var _hint_pos: Dictionary = {}   # "layout|const|key" -> Vector2 or null (resolved once; values only)


# --- Wiring ----------------------------------------------------------------------------------------

## Connects the Events listeners (idempotent). Called once by GameState/Game (integrator) and by tests.
static func init() -> void:
	_wired = true
	for pair in _connections():
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if not sig.is_connected(cb):
			sig.connect(cb)


## Disconnects every listener (tests that must not leak listeners into other suites).
static func shutdown() -> void:
	_wired = false
	for pair in _connections():
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)


static func is_listening() -> bool:
	return _wired


static func _connections() -> Array:
	return [
		[Events.harvested, _on_harvested],
		[Events.crafted, _on_crafted],
		[Events.structure_placed, _on_structure_placed],
		[Events.crop_harvested, _on_crop_harvested],
		[Events.landmark_discovered, _on_landmark],
		[Events.lore_discovered, _on_lore],
		[Events.arch_lit, _on_arch],
		[Events.flag_set, _on_flag],
		[Events.boss_defeated, _on_boss],
		[Events.trial_ended, _on_trial],
		[Events.game_loaded, _on_loaded],
		[Events.area_loaded, _on_area_loaded],
	]


# --- Queries ----------------------------------------------------------------------------------------

static func tracks() -> Array:
	return MasteryData.TRACKS


static func xp(track: String) -> int:
	var v: Variant = _state().get(track, 0)
	return maxi(int(v), 0) if (v is int or v is float) else 0


static func rank(track: String) -> int:
	return ItemDB.mastery_rank_for_xp(xp(track))


static func max_xp() -> int:
	return int(MasteryData.RANK_XP[MasteryData.MAX_RANK])


## {"xp", "rank", "prev_xp" (threshold of the current rank), "next_xp" (-1 at max), "fraction" 0..1 toward next}
static func progress(track: String) -> Dictionary:
	var x := xp(track)
	var r := rank(track)
	var prev := int(MasteryData.RANK_XP[r])
	var nxt := int(MasteryData.RANK_XP[r + 1]) if r < MasteryData.MAX_RANK else -1
	var frac := 1.0 if nxt < 0 else clampf(float(x - prev) / float(maxi(nxt - prev, 1)), 0.0, 1.0)
	return {"xp": x, "rank": r, "prev_xp": prev, "next_xp": nxt, "fraction": frac}


static func track_name(track: String) -> String:
	return String(MasteryData.TRACK_NAMES.get(track, {}).get("name", track.capitalize()))


## True when this first-time kind ("<rule>:<id>") was already rewarded on that track.
static func has_seen(track: String, kind_id: String) -> bool:
	var seen: Variant = _state().get("seen", {})
	if not (seen is Dictionary):
		return false
	var list: Variant = (seen as Dictionary).get(track, [])
	return list is Array and (list as Array).has(kind_id)


## Repeatable xp already earned today for a rule (daily caps).
static func daily_used(track: String, rule: String) -> int:
	var d := _daily()
	var v: Variant = (d["xp"] as Dictionary).get(track + ":" + rule, 0)
	return int(v) if (v is int or v is float) else 0


# --- Effects (data/mastery.gd REWARDS: each value is the TOTAL from that rank on) ---------------------

## The reward value `key` currently in effect (highest reached rank of any track that defines it), else
## `default_value`. E.g. effect("gather_power") = 0.1 at gathering rank 3.
## Cached per combination of ranks, so Stats may poll it every frame without allocating.
static func effect(key: String, default_value: Variant = 0.0) -> Variant:
	var fx := _effects()
	return fx[key] if fx.has(key) else default_value


## {reward key: value in effect} for the current ranks (rebuilt only when a rank changes).
static func _effects() -> Dictionary:
	var code := 0
	for track in MasteryData.TRACKS:
		code = code * 8 + rank(String(track))
	if code == _fx_code:
		return _fx_cache
	_fx_code = code
	_fx_cache = {}
	for track in MasteryData.TRACKS:
		var r := rank(String(track))
		for k in range(1, r + 1):   # higher ranks overwrite: each value is the TOTAL from that rank on
			var rw: Dictionary = ItemDB.mastery_reward(String(track), k)
			for key in rw:
				if String(key) != "text" and String(key) != "recipes":
					_fx_cache[key] = rw[key]
	return _fx_cache


## Extra harvest power fraction (Stats combines it with charms under GATHER_BONUS_CAP).
static func gather_power() -> float:
	return float(effect("gather_power", 0.0))


## Chance of +1 main drop (Stats combines it under YIELD_CHANCE_CAP).
static func bonus_yield_chance() -> float:
	return float(effect("bonus_yield_chance", 0.0))


## Extra furnace queue slots.
static func furnace_queue_bonus() -> int:
	return int(effect("furnace_queue_bonus", 0))


## Furnace job time multiplier (1.0 = normal).
static func station_time_mult() -> float:
	return clampf(float(effect("station_time_mult", 1.0)), 0.25, 1.0)


## Fraction longer meal buffs (player eat path).
static func meal_buff_bonus() -> float:
	return float(effect("meal_buff_bonus", 0.0))


## Fraction less sprint stamina (Stats.stamina_cost_mult for sprinting).
static func sprint_stamina_save() -> float:
	return float(effect("sprint_stamina_save", 0.0))


## Combined caps from data (for Stats).
static func gather_bonus_cap() -> float:
	return float(MasteryData.GATHER_BONUS_CAP)


static func yield_chance_cap() -> float:
	return float(MasteryData.YIELD_CHANCE_CAP)


## Wayfinding 2: the map pins the recorded resource spots.
static func resource_pins_on() -> bool:
	return _truthy(effect("map_resource_pins", false))


## Wayfinding 4: the map hints at unfound caches in discovered districts.
static func cache_hints_on() -> bool:
	return _truthy(effect("map_cache_hints", false))


## Gathering 4: radius (metres) of the nearby-material sparkle; 0 = off.
static func highlight_radius() -> float:
	return maxf(float(effect("highlight_radius", 0.0)), 0.0)


# --- Map clarity: resource spots and cache hints (data/mastery.gd SPOT_* / MAP_CACHE_HINTS) ---------------

## Remembers where a node of `kind` was fully harvested (the Events.harvested listener calls it). Only in
## SPOT_AREAS, never for SPOT_SKIP_KINDS; a spot within SPOT_MIN_DIST of a known one of the same kind is the same
## spot; at most SPOT_MAX_PER_KIND per kind and area (the oldest is forgotten). Returns true when a spot was added.
static func record_spot(area_id: String, kind: String, pos: Vector3) -> bool:
	if not GameState.active or kind == "" or not MasteryData.SPOT_AREAS.has(area_id) \
			or MasteryData.SPOT_SKIP_KINDS.has(kind) or not pos.is_finite():
		return false
	var list := _spot_list(area_id, kind)
	var p := Vector2(snappedf(pos.x, 0.1), snappedf(pos.z, 0.1))
	var min_d2 := float(MasteryData.SPOT_MIN_DIST) * float(MasteryData.SPOT_MIN_DIST)
	for e in list:
		var q: Variant = _spot_vec(e)
		if q is Vector2 and (q as Vector2).distance_squared_to(p) < min_d2:
			return false
	list.append([p.x, p.y])
	while list.size() > int(MasteryData.SPOT_MAX_PER_KIND):
		list.remove_at(0)
	return true


## Recorded resource spots of an area: [{"kind", "pos": Vector2 (x, z metres)}], kinds in name order, each in
## recording order. Read-only (a damaged record reads as empty; bad entries are skipped).
static func known_spots(area_id: String) -> Array:
	var out: Array = []
	var spots: Variant = _state().get("spots")
	if not (spots is Dictionary):
		return out
	var per_area: Variant = (spots as Dictionary).get(area_id)
	if not (per_area is Dictionary):
		return out
	var kinds: Array = (per_area as Dictionary).keys()
	kinds.sort()
	for k in kinds:
		var kind := String(k)
		var list: Variant = (per_area as Dictionary)[k]
		if MasteryData.SPOT_SKIP_KINDS.has(kind) or not (list is Array):
			continue
		for e in list:
			var q: Variant = _spot_vec(e)
			if q is Vector2:
				out.append({"kind": kind, "pos": q})
	return out


## The item a spot pin shows for a node kind (its main drop in data/sources.gd NODES; "" when unknown).
static func spot_item(kind: String) -> String:
	var drops: Variant = ItemDB.node_kind(kind).get("drops", [])
	if drops is Array and not (drops as Array).is_empty() and (drops as Array)[0] is Dictionary:
		return String(((drops as Array)[0] as Dictionary).get("item", ""))
	return ""


## Optional caches the map may hint at in an area: [{"id", "pos": Vector2, "district"}] for every MAP_CACHE_HINTS
## entry whose district is discovered and whose owner flag is not set yet (position read from the owner's layout
## constant; entries whose layout or constant is missing are skipped). Independent of rank: the map also checks
## cache_hints_on().
static func cache_hints(area_id: String) -> Array:
	var out: Array = []
	for h in MasteryData.MAP_CACHE_HINTS:
		var hint: Dictionary = h
		if String(hint.get("area", "")) != area_id:
			continue
		if _truthy(GameState.get_flag(String(hint.get("flag", "")))):
			continue
		var district := String(hint.get("district", ""))
		if district != "" and not GameState.is_discovered(area_id, district):
			continue
		var pos: Variant = cache_hint_pos(hint)
		if pos is Vector2:
			out.append({"id": String(hint.get("id", "")), "pos": pos, "district": district})
	return out


## Position of a MAP_CACHE_HINTS entry, read from its layout constant (null when unavailable).
static func cache_hint_pos(hint: Dictionary) -> Variant:
	var path := String(hint.get("layout", ""))
	var key := String(hint.get("key", ""))
	var cache_key := "%s|%s|%s" % [path, String(hint.get("const", "")), key]
	if _hint_pos.has(cache_key):
		return _hint_pos[cache_key]
	var v: Variant = null
	if path != "" and ResourceLoader.exists(path):
		var sc := load(path) as Script
		if sc != null:
			v = sc.get_script_constant_map().get(String(hint.get("const", "")))
	if key != "" and v is Dictionary:
		v = (v as Dictionary).get(key)
	var out: Variant = v if v is Vector2 else null
	_hint_pos[cache_key] = out
	return out


## [x, z] (JSON arrays of numbers) -> Vector2, else null.
static func _spot_vec(e: Variant) -> Variant:
	if e is Array and (e as Array).size() >= 2:
		var x: Variant = (e as Array)[0]
		var z: Variant = (e as Array)[1]
		if (x is float or x is int) and (z is float or z is int) and is_finite(float(x)) and is_finite(float(z)):
			return Vector2(float(x), float(z))
	return null


## GameState.mastery["spots"][area][kind] (created; a damaged container is replaced, never an error).
static func _spot_list(area_id: String, kind: String) -> Array:
	var spots: Variant = GameState.mastery.get("spots")
	if not (spots is Dictionary):
		spots = {}
		GameState.mastery["spots"] = spots
	var per_area: Variant = (spots as Dictionary).get(area_id)
	if not (per_area is Dictionary):
		per_area = {}
		(spots as Dictionary)[area_id] = per_area
	var list: Variant = (per_area as Dictionary).get(kind)
	if not (list is Array):
		list = []
		(per_area as Dictionary)[kind] = list
	return list


# --- Awarding --------------------------------------------------------------------------------------------

## Awards xp for `kind_id` ("<rule>" or "<rule>:<id>") on `track`. Rules come from data/mastery.gd XP:
##  * once_per rules: only the FIRST time for each full kind id (needs an id), recorded in seen[track];
##  * daily_cap rules: at most daily_cap xp per in-game day;
##  * NO_XP rules and unknown tracks: 0.
## An unknown rule with an explicit `xp` > 0 is treated as a first-time kind (deduped on kind_id).
## `xp_amount` < 0 uses the rule's data value. Returns the xp actually added.
static func award(track: String, kind_id: String, xp_amount: int = -1) -> int:
	if not GameState.active or not MasteryData.TRACKS.has(track) or kind_id == "":
		return 0
	var parts := kind_id.split(":", true, 1)
	var rule: String = parts[0]
	var id: String = parts[1] if parts.size() > 1 else ""
	if MasteryData.NO_XP.has(rule):
		return 0
	var r: Dictionary = ItemDB.mastery_xp_rules(track).get(rule, {})
	var amount: int = xp_amount if xp_amount >= 0 else int(r.get("xp", 0))
	if amount <= 0:
		return 0
	var repeatable := r.has("daily_cap")
	if not repeatable:
		if r.has("once_per") and id == "":
			return 0
		if has_seen(track, kind_id):
			return 0
	var cap_left := -1
	if repeatable:
		cap_left = int(r["daily_cap"]) - daily_used(track, rule)
		amount = mini(amount, cap_left)
		if amount <= 0:
			return 0
	# Commit: remember first-time kinds / today's usage, then add the xp.
	if not repeatable:
		_seen_list(track).append(kind_id)
	else:
		var d := _daily()
		var key := track + ":" + rule
		(d["xp"] as Dictionary)[key] = daily_used(track, rule) + amount
	return _add_xp(track, amount, true)


## Adds raw xp (already validated). Emits Events.mastery_changed and a toast per rank reached.
static func _add_xp(track: String, amount: int, toast: bool) -> int:
	var before_xp := xp(track)
	var after_xp := mini(before_xp + amount, max_xp())
	var added := after_xp - before_xp
	if added <= 0:
		return 0
	var before := rank(track)
	GameState.mastery[track] = after_xp
	var after := rank(track)
	Events.mastery_changed.emit(track, after_xp, after)
	if after > before:
		for rk in range(before + 1, after + 1):
			var rw: Dictionary = ItemDB.mastery_reward(track, rk)
			var recipes: Variant = rw.get("recipes", [])
			if recipes is Array:
				for rid in recipes:
					Events.recipe_unlocked.emit(String(rid))
		if toast:
			var text := String(ItemDB.mastery_reward(track, after).get("text", ""))
			Events.notify.emit("%s mastery rank %d! %s" % [track_name(track), after, text], "success")
	return added


# --- Legacy credit (MP 5.3, spec 3.1) --------------------------------------------------------------------

## True once the one-time legacy credit was applied (any recorded value except false / null).
static func legacy_applied() -> bool:
	var lc: Variant = _state().get("legacy_credit", false)
	if lc == null:
		return false
	if lc is bool:
		return lc
	return true


## Conservative credit the current state would earn: {track: xp} (each source capped, each track capped by
## LEGACY_CAP_XP, which stays below rank 2). Pure: changes nothing.
static func legacy_credit_preview() -> Dictionary:
	var out := {}
	for track in MasteryData.TRACKS:
		var total := 0
		for src in MasteryData.LEGACY_CREDIT.get(track, []):
			total += _legacy_source_xp(src)
		out[track] = clampi(total, 0, int(MasteryData.LEGACY_CAP_XP))
	return out


static func _legacy_source_xp(src: Dictionary) -> int:
	var key := String(src.get("key", ""))
	var n := 0
	match String(src.get("source", "")):
		"counter":
			n = GameState.get_counter(key)
		"stat":
			var v: Variant = GameState.stats.get(key, 0)
			n = int(v) if (v is int or v is float) else 0
		"lore_count":
			n = GameState.lore.size()
		"flag":
			return int(src.get("xp", 0)) if _truthy(GameState.get_flag(key)) else 0
	var cap := int(src.get("cap", 0))
	var each := int(src.get("xp_each", 0))
	return clampi(maxi(n, 0) * each, 0, cap if cap > 0 else 1 << 30)


## Applies the legacy credit ONCE per save and records it (legacy_credit = {"applied", "at", "xp"}).
## Returns the xp added per track ({} when it was already applied). No toasts (it runs on load); emits
## Events.mastery_changed for tracks that changed.
## Only a mastery record WITHOUT progress is credited (a v1 save, or a v2 save written before masteries existed):
## a record that already has xp or first-time kinds was made by a build with masteries, whose own first area
## load already decided the credit, so it is left exactly as loaded (loading never changes it).
static func apply_legacy_credit() -> Dictionary:
	if not GameState.active or legacy_applied() or _has_progress():
		return {}
	var credit := legacy_credit_preview()
	var added := {}
	# Record FIRST (like the reward ledger): a failure below can never make it apply twice.
	GameState.mastery["legacy_credit"] = {"applied": true, "at": float(GameState.total_minutes), "xp": credit.duplicate()}
	mark_legacy_landmarks()
	for track in credit:
		var n := _add_xp(String(track), int(credit[track]), false)
		if n > 0:
			added[track] = n
	return added


## Records the Chapter One landmarks this save proves visited (data LEGACY_LANDMARKS: any listed flag set) as
## already-seen wayfinding "landmark" kinds: no xp, no toast - the legacy credit stands in for them (CH2-010). Called
## by apply_legacy_credit() only, so it runs once per save and never for a new journey's first area load (no flags).
## Returns the kinds newly recorded.
static func mark_legacy_landmarks() -> Array:
	var out: Array = []
	for entry in MasteryData.LEGACY_LANDMARKS:
		var kind := "landmark:" + String((entry as Dictionary).get("landmark", ""))
		if kind == "landmark:" or has_seen("wayfinding", kind):
			continue
		for f in (entry as Dictionary).get("flags", []):
			if _truthy(GameState.get_flag(String(f))):
				_seen_list("wayfinding").append(kind)
				out.append(kind)
				break
	return out


## Any xp or first-time kind recorded on any track.
static func _has_progress() -> bool:
	var st := _state()
	for track in MasteryData.TRACKS:
		if xp(String(track)) > 0:
			return true
	var seen: Variant = st.get("seen", {})
	if seen is Dictionary:
		for t in seen:
			if seen[t] is Array and not (seen[t] as Array).is_empty():
				return true
	return false


# --- Listeners (ordinary play only) ----------------------------------------------------------------------

static func _on_harvested(kind: String, item_id: String, _count: int, pos: Vector3) -> void:
	if not GameState.active:
		return
	record_spot(String(Game.area_id), kind, pos)   # map pins (Wayfinding 2); deduped by distance
	award("gathering", "first_node_kind:" + kind)
	award("gathering", "first_material:" + item_id)
	# One node emits one signal per dropped item type in the same frame: count it once.
	var frame := Engine.get_process_frames()
	if frame == _last_harvest_frame and pos.is_equal_approx(_last_harvest_pos):
		return
	_last_harvest_frame = frame
	_last_harvest_pos = pos
	award("gathering", "harvest")


static func _on_crafted(recipe_id: String, _item_id: String, _count: int) -> void:
	if not GameState.active:
		return
	if award("hearthcraft", "first_recipe:" + recipe_id) <= 0:
		award("hearthcraft", "craft")
	var station := _recipe_station(recipe_id)
	if WORKSHOP_STATIONS.has(station):
		award("hearthcraft", "first_station_use:" + station)


static func _recipe_station(recipe_id: String) -> String:
	if recipe_id.begins_with("dye:"):
		return String(ItemDB.dye_palette(recipe_id.substr(4)).get("station", ""))
	return String(ItemDB.recipe(recipe_id).get("station", ""))


static func _on_structure_placed(_uid: String, structure_id: String) -> void:
	award("hearthcraft", "first_structure:" + structure_id)


static func _on_crop_harvested(_uid: String, _crop: String, _count: int) -> void:
	award("hearthcraft", "crop_harvest")


static func _on_landmark(area_id: String, landmark_id: String) -> void:
	award("wayfinding", "landmark:%s/%s" % [area_id, landmark_id])


static func _on_lore(lore_id: String) -> void:
	award("wayfinding", "lore:" + lore_id)


static func _on_arch(arch_id: String) -> void:
	award("wayfinding", "arch:" + arch_id)


static func _on_flag(flag: String, value: Variant) -> void:
	if not _truthy(value):
		return
	if SHORTCUT_FLAGS.has(flag):
		award("wayfinding", "shortcut:" + flag)
	elif ENCOUNTER_FLAGS.has(flag):
		award("wayfinding", "encounter:" + String(ENCOUNTER_FLAGS[flag]))


static func _on_boss(boss_id: String) -> void:
	award("wayfinding", "encounter:" + boss_id)


static func _on_trial(trial_id: String, won: bool) -> void:
	if won:
		award("wayfinding", "encounter:trial_" + trial_id)   # first clear only (repeat clears are deduped)


## A loaded save gets its one-time legacy credit (before any new play is recorded).
static func _on_loaded() -> void:
	apply_legacy_credit()


## A brand-new journey records an empty credit on its first area load, so counters earned from now on are
## never credited a second time by a later load.
static func _on_area_loaded(_area_id: String) -> void:
	apply_legacy_credit()


# --- State helpers --------------------------------------------------------------------------------------

## Flag values are usually bools; saves may hold numbers or text. false / null / 0 / "" count as unset.
static func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	if v is String:
		return v != ""
	return true

static func _state() -> Dictionary:
	var m: Variant = GameState.get("mastery")
	if m is Dictionary:
		return m
	return {}


static func _seen_list(track: String) -> Array:
	var seen: Variant = GameState.mastery.get("seen")
	if not (seen is Dictionary):
		seen = {}
		GameState.mastery["seen"] = seen
	var list: Variant = (seen as Dictionary).get(track)
	if not (list is Array):
		list = []
		(seen as Dictionary)[track] = list
	return list


## Today's daily ledger (reset when the in-game day changes). JSON floats are tolerated.
static func _daily() -> Dictionary:
	var d: Variant = GameState.mastery.get("daily")
	var today := GameState.day()
	if not (d is Dictionary) or not ((d as Dictionary).get("day") is int or (d as Dictionary).get("day") is float) \
			or int((d as Dictionary)["day"]) != today or not ((d as Dictionary).get("xp") is Dictionary):
		d = {"day": today, "xp": {}}
		GameState.mastery["daily"] = d
	return d

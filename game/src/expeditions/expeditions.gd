extends RefCounted
## Lanternwake Expeditions - the static rules (module D2; MP §15; data/expeditions.gd).
##   const Expeditions := preload("res://src/expeditions/expeditions.gd")
## An optional board (src/building/structures/expedition_board.gd -> panel "expedition") offers three
## hand-authored routes through Hallowmere Reach. Starting one saves a run; the Reach's runner
## (src/expeditions/expedition_runner.gd) shows a ribbon lantern at the current stop, lets the stop's group
## appear out of sight when Krystal comes near, counts their defeats here, and finally places the route's
## cache, whose opening pays the run's rewards exactly once.
##
## SAVED STATE: GameState.extra["expeditions"] (Data.STATE_KEY). GameState keeps unknown top-level keys in
## `extra` and writes them back verbatim, so the section survives save/load, migration and older builds:
##   {"v": 1,
##    "active": {} | {"template": id, "seed": 1..9999, "stop": index (== stop count: the cache waits),
##                    "defeated": defeats at the current stop, "down": {enemy id: defeats at this stop},
##                    "started_at": GameState.total_minutes at start, "run": the run number},
##    "runs": runs started, "completed": {template id: completions}, "abandoned": runs set aside,
##    "last": {} | {"template", "run", "items": {id: n}, "keepsake": {}, "at": total_minutes}}
## Numbers come back from JSON as floats; every read normalises them (a damaged section is repaired, an
## unknown template or an out-of-range stop drops the run - never a crash).
##
## RULES: expeditions never write a flag (they only READ the template's `requires` flag), never touch the
## Chapter One / Chapter Two quest layers, the reward ledger or the tracker's chapter steps; rewards are
## renewable materials, candy and sometimes a keepsake (a new dye colour - its Loom palette is unlocked directly,
## a gift that skips the Loom cost - or a festival decoration) - never a story item. A route's FIRST completion
## also gives a little Wayfinding mastery xp (Mastery.award, deduped per route; MP 5.3). complete() records the
## completion BEFORE it gives anything, so a run pays once. Abandoning is free (the stop's living group goes
## home at once, even mid-fight: lead decision P43, player-chosen and harmless). No daily limit, no timer.
## (The one-time intro tip goes out through Events.hint; the HUD hint card then remembers it in its own UI flag
## "hint_expedition_intro", as it does for every tip. That is never a story flag, and nothing here writes one.)
##
## API: init()/shutdown()/is_listening() (Events.area_loaded -> the Reach gets its runner while a run is going), template_ids(),
## template(id), is_unlocked(id), lock_reason(id), preview(id), enemy_types(id), roll_seed(), plan(id, seed),
## state(), active(), is_active(), start(id, seed := -1) -> bool, abandon() -> bool, current_stop_index(),
## stop_count(id), in_cache_phase(), current_plan(), current_target(), record_defeat(id, run, stop, enemy := "") -> bool,
## complete() -> Dictionary, keepsake_for(id, plan, first), keepsake_text(keepsake), completions(id), last_result(),
## tracker_view(), map_marks(area_id), place_disc(place_id), summary_line(), attach_to_current_area().
## The views the HUD / map poll (is_active, current_plan, current_target, tracker_view, map_marks, place_disc)
## never create the saved section: without a saved run they answer "none", read-only.

const Data := preload("res://data/expeditions.gd")
const RUNNER_SCRIPT := "res://src/expeditions/expedition_runner.gd"
const RUNNER_NODE := "Expeditions"          # expedition_runner.gd NODE_NAME
const MASTERY_SCRIPT := "res://src/core/mastery.gd"
## "At the stop" radius for the tracker's where line / map discs (the spawn points ring the lantern at 3-9 m).
const PLACE_RADIUS := 8.0

static var _wired := false
static var _plan_key: String = ""
static var _plan_cache: Dictionary = {}


# --- Wiring ---------------------------------------------------------------------------------------------------

## Connects the Events listener that gives Hallowmere Reach its runner on every load while a run is going
## (idempotent). Game.wire_session_systems() calls it at start-up (its SESSION_INIT_SCRIPTS), so a saved run
## resumes on the first Reach load of a session; start(), the board's interact() and the panel call it again as
## a harmless safety net (idempotent).
static func init() -> void:
	_wired = true
	if not Events.area_loaded.is_connected(_on_area_loaded):
		Events.area_loaded.connect(_on_area_loaded)


static func shutdown() -> void:
	_wired = false
	if Events.area_loaded.is_connected(_on_area_loaded):
		Events.area_loaded.disconnect(_on_area_loaded)


static func is_listening() -> bool:
	return _wired and Events.area_loaded.is_connected(_on_area_loaded)


static func _on_area_loaded(area_id: String) -> void:
	if area_id == Data.AREA_ID:
		attach_to_current_area()


## Gives the current area its runner when it is the Reach and a run is going (safe-loaded; a broken runner never
## crashes). Without a run the Reach gets no runner node at all (the existing one, if any, is returned).
static func attach_to_current_area() -> Node:
	if Game.area_id != Data.AREA_ID or Game.area == null or not is_instance_valid(Game.area):
		return null
	if not is_active():
		return Game.area.get_node_or_null(RUNNER_NODE)
	if not ResourceLoader.exists(RUNNER_SCRIPT):
		return null
	var s: Variant = load(RUNNER_SCRIPT)
	if not (s is Script) or not (s as Script).can_instantiate():
		return null
	return (s as Script).call("attach", Game.area) as Node


# --- Templates ------------------------------------------------------------------------------------------------

static func template_ids() -> Array:
	return Data.ORDER


static func template(template_id: String) -> Dictionary:
	var t: Variant = Data.TEMPLATES.get(template_id)
	return t if t is Dictionary else {}


static func stop_count(template_id: String) -> int:
	return (template(template_id).get("stops", []) as Array).size()


static func is_unlocked(template_id: String) -> bool:
	var t := template(template_id)
	if t.is_empty():
		return false
	var req := String(t.get("requires", ""))
	return req == "" or _truthy(GameState.get_flag(req))


static func lock_reason(template_id: String) -> String:
	if template(template_id).is_empty():
		return "Unknown route."
	return "" if is_unlocked(template_id) else String(template(template_id).get("requires_text", "Not yet."))


## Every enemy id that may appear on the route (first-seen order across all stops and groups).
static func enemy_types(template_id: String) -> Array:
	var out: Array = []
	for s in template(template_id).get("stops", []):
		for g in (s as Dictionary).get("groups", []):
			for pair in g:
				var id := String((pair as Array)[0])
				if not out.has(id):
					out.append(id)
	return out


## What the board shows before starting (MP §15: expected difficulty and reward TYPES, never the roll).
## Enemy names go through ItemDB.enemy_display_name (arachnophobia-aware).
static func preview(template_id: String) -> Dictionary:
	var t := template(template_id)
	if t.is_empty():
		return {}
	var diff: Dictionary = Data.DIFFICULTIES.get(String(t.get("difficulty", "")), {})
	var names: Array = []
	for id in enemy_types(template_id):
		names.append(ItemDB.enemy_display_name(String(id)))
	var stops: Array = []
	for s in t.get("stops", []):
		stops.append(String((s as Dictionary).get("name", "")))
	return {"id": template_id, "name": String(t.get("name", template_id)), "blurb": String(t.get("blurb", "")),
		"difficulty": String(t.get("difficulty", "")), "difficulty_name": String(diff.get("name", "")),
		"pips": int(diff.get("pips", 1)), "difficulty_text": String(diff.get("text", "")),
		"minutes": String(t.get("minutes", "")), "stops": stops, "cache": String((t.get("cache", {}) as Dictionary).get("name", "")),
		"enemies": names, "reward_types": (t.get("reward_types", []) as Array).duplicate(),
		"unlocked": is_unlocked(template_id), "reason": lock_reason(template_id), "completed": completions(template_id),
		"arch": String(t.get("arch", ""))}


# --- Seeds and plans ------------------------------------------------------------------------------------------

static func roll_seed() -> int:
	return randi_range(1, Data.SEED_MAX)


static func _rng_for(template_id: String, seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s#%d" % [template_id, seed_value])
	return rng


## The concrete run a (template, seed) pair describes. Pure and deterministic (same pair -> same plan):
## {"template", "seed", "stops": [{"id", "name", "pos": Vector2, "points": [Vector2 in spawn order],
##  "group": [[enemy, n]...], "enemies": [enemy id per slot], "needed": int}], "cache": {id, name, pos},
##  "rewards": {item: n}, "keepsake_roll": 0..1, "keepsake_pick": int}. {} for an unknown template.
static func plan(template_id: String, seed_value: int) -> Dictionary:
	var key := "%s#%d" % [template_id, seed_value]
	if key == _plan_key:
		return _plan_cache
	var t := template(template_id)
	if t.is_empty():
		return {}
	var rng := _rng_for(template_id, seed_value)
	var stops: Array = []
	for s in t.get("stops", []):
		var sd: Dictionary = s
		var groups: Array = sd.get("groups", [])
		var group: Array = groups[rng.randi_range(0, groups.size() - 1)] if not groups.is_empty() else []
		var points: Array = (sd.get("points", []) as Array).duplicate()
		for i in range(points.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Variant = points[i]
			points[i] = points[j]
			points[j] = tmp
		var enemies: Array = []
		for pair in group:
			for k in int((pair as Array)[1]):
				enemies.append(String((pair as Array)[0]))
		stops.append({"id": String(sd.get("id", "")), "name": String(sd.get("name", "")), "pos": sd.get("pos", Vector2.ZERO),
			"points": points, "group": (group as Array).duplicate(true), "enemies": enemies, "needed": enemies.size()})
	var rw: Dictionary = t.get("rewards", {})
	var items: Dictionary = {}
	var base: Dictionary = rw.get("base", {})
	for id in base:
		_add(items, String(id), _roll_range(rng, base[id]))
	var picks: Dictionary = rw.get("picks", {})
	var from: Dictionary = picks.get("from", {})
	var pool: Array = from.keys()
	for i in range(pool.size() - 1, 0, -1):
		var j2 := rng.randi_range(0, i)
		var tmp2: Variant = pool[i]
		pool[i] = pool[j2]
		pool[j2] = tmp2
	for i in mini(int(picks.get("count", 0)), pool.size()):
		_add(items, String(pool[i]), _roll_range(rng, from[pool[i]]))
	var out := {"template": template_id, "seed": seed_value, "stops": stops,
		"cache": (t.get("cache", {}) as Dictionary).duplicate(true), "rewards": items,
		"keepsake_roll": rng.randf(), "keepsake_pick": rng.randi_range(0, 1 << 20)}
	_plan_key = key
	_plan_cache = out
	return out


static func _roll_range(rng: RandomNumberGenerator, r: Variant) -> int:
	if r is Array and (r as Array).size() >= 2:
		return rng.randi_range(int(r[0]), maxi(int(r[0]), int(r[1])))
	return int(r) if (r is int or r is float) else 0


static func _add(items: Dictionary, id: String, n: int) -> void:
	if n > 0:
		items[id] = int(items.get(id, 0)) + n


# --- State ----------------------------------------------------------------------------------------------------

## The saved section (created and normalised on demand; JSON floats become ints again).
static func state() -> Dictionary:
	var s: Variant = GameState.extra.get(Data.STATE_KEY)
	if not (s is Dictionary):
		s = {}
		GameState.extra[Data.STATE_KEY] = s
	var st: Dictionary = s
	# Cheap when already normal (the runner reads the run a few times a second): type checks only.
	if not (st.get("v") is int):
		st["v"] = Data.STATE_VERSION
	if not (st.get("runs") is int):
		st["runs"] = maxi(_int(st.get("runs")), 0)
	if not (st.get("abandoned") is int):
		st["abandoned"] = maxi(_int(st.get("abandoned")), 0)
	if not (st.get("completed") is Dictionary):
		st["completed"] = {}
	if not (st.get("last") is Dictionary):
		st["last"] = {}
	if not (st.get("active") is Dictionary):
		st["active"] = {}
	var a: Dictionary = st["active"]
	if not a.is_empty() and not (a.get("stop") is int and a.get("seed") is int and a.get("defeated") is int and a.get("run") is int
			and Data.TEMPLATES.has(a.get("template")) and a.get("down") is Dictionary):
		_normalise_active(st)
	return st


static func _normalise_active(st: Dictionary) -> void:
	var a: Dictionary = st["active"]
	var t := String(a.get("template", "")) if a.get("template") is String else ""
	var n := stop_count(t)
	var stop := _int(a.get("stop"), -1)
	var seed_value := _int(a.get("seed"), 0)
	if n <= 0 or stop < 0 or stop > n or seed_value < 1 or seed_value > Data.SEED_MAX:
		push_warning("Expeditions: dropping a damaged run %s" % str(a))
		st["active"] = {}
		return
	a["template"] = t
	a["stop"] = stop
	a["seed"] = seed_value
	a["defeated"] = maxi(_int(a.get("defeated"), 0), 0)
	a["run"] = maxi(_int(a.get("run"), 0), 0)
	a["started_at"] = float(a.get("started_at", 0.0)) if (a.get("started_at") is float or a.get("started_at") is int) else 0.0
	var down: Dictionary = {}
	var src: Variant = a.get("down")
	if src is Dictionary:
		for k in src:
			var c := _int((src as Dictionary)[k], 0)
			if k is String and c > 0:
				down[k] = c
	a["down"] = down
	# A damaged count that already covers the whole group can never leave the stop stuck: it is done.
	var needed := int(((plan(t, seed_value).get("stops", []) as Array)[stop] as Dictionary).get("needed", 0)) if stop < n else 0
	if stop < n and int(a["defeated"]) >= needed:
		a["stop"] = stop + 1
		a["defeated"] = 0
		a["down"] = {}


## The running expedition ({} when none). The returned dictionary is the saved one (read it, don't edit it).
static func active() -> Dictionary:
	return state()["active"]


static func is_active() -> bool:
	return _has_saved_run() and not active().is_empty()


## True when the save holds a (possibly damaged) run, read WITHOUT creating the saved section, so the views the
## HUD and the map poll never add an "expeditions" section to a save that never used the board.
static func _has_saved_run() -> bool:
	var s: Variant = GameState.extra.get(Data.STATE_KEY)
	if not (s is Dictionary):
		return false
	var a: Variant = (s as Dictionary).get("active")
	return a is Dictionary and not (a as Dictionary).is_empty()


static func current_stop_index() -> int:
	var a := active()
	return int(a.get("stop", -1)) if not a.is_empty() else -1


## True once every stop is quiet and the cache waits to be opened.
static func in_cache_phase() -> bool:
	var a := active()
	return not a.is_empty() and int(a["stop"]) >= stop_count(String(a["template"]))


static func current_plan() -> Dictionary:
	if not _has_saved_run():
		return {}
	var a := active()
	if a.is_empty():
		return {}
	return plan(String(a["template"]), int(a["seed"]))


static func completions(template_id: String) -> int:
	return maxi(_int((state()["completed"] as Dictionary).get(template_id), 0), 0)


static func last_result() -> Dictionary:
	return state()["last"]


## Begins a run of `template_id` (seed -1 = a fresh random seed). Refused (false) when the template is unknown
## or not unlocked, or another run is going (abandon it first). Writes no flag.
static func start(template_id: String, seed_value: int = -1) -> bool:
	if template(template_id).is_empty() or not is_unlocked(template_id) or is_active():
		return false
	var sd := seed_value if seed_value >= 1 and seed_value <= Data.SEED_MAX else roll_seed()
	var st := state()
	st["runs"] = int(st["runs"]) + 1
	st["active"] = {"template": template_id, "seed": sd, "stop": 0, "defeated": 0, "down": {},
		"started_at": float(GameState.total_minutes), "run": int(st["runs"])}
	var p := plan(template_id, sd)
	var first: Dictionary = (p["stops"] as Array)[0] if not (p["stops"] as Array).is_empty() else {}
	Events.notify.emit(_fmt("started", {"name": String(template(template_id)["name"]), "stop": String(first.get("name", ""))}), "quest")
	Events.hint.emit("expedition_intro", String(Data.TEXT["hint"]))
	Events.objectives_changed.emit()
	init()
	attach_to_current_area()
	return true


## Sets the running expedition aside. Free: nothing is taken, nothing she carries is lost (the drops and items
## she picked up stay hers). The run's cache is only paid by complete(): setting a run aside in the cache phase
## leaves that cache closed, and the panel / toast say so.
static func abandon() -> bool:
	if not is_active():
		return false
	var at_cache := in_cache_phase()
	var st := state()
	st["active"] = {}
	st["abandoned"] = int(st["abandoned"]) + 1
	Events.notify.emit(String(Data.TEXT["abandoned_cache" if at_cache else "abandoned"]), "info")
	Events.objectives_changed.emit()
	return true


## One enemy of the current stop's group was defeated (the runner binds template / run / stop to each enemy it
## spawns, so a stale enemy from an earlier stop or run never counts). Advances the stop when the group is done.
static func record_defeat(template_id: String, run: int, stop: int, enemy_id: String = "") -> bool:
	var a := active()
	if a.is_empty() or String(a["template"]) != template_id or int(a["run"]) != run or int(a["stop"]) != stop:
		return false
	var stops: Array = current_plan().get("stops", [])
	if stop < 0 or stop >= stops.size():
		return false
	var needed := int((stops[stop] as Dictionary)["needed"])
	a["defeated"] = int(a["defeated"]) + 1
	if enemy_id != "":
		# Which ones are down, so a group that comes back after a despawn / reload is the right remainder.
		if not (a.get("down") is Dictionary):
			a["down"] = {}
		var down: Dictionary = a["down"]
		down[enemy_id] = int(down.get(enemy_id, 0)) + 1
	if int(a["defeated"]) >= needed:
		_advance(stops)
	Events.objectives_changed.emit()
	return true


static func _advance(stops: Array) -> void:
	var a := active()
	var done := int(a["stop"])
	a["stop"] = done + 1
	a["defeated"] = 0
	a["down"] = {}
	var total := stops.size()
	var nm := String((stops[done] as Dictionary)["name"])
	if done + 1 < total:
		Events.notify.emit(_fmt("stop_clear", {"stop": nm, "n": str(done + 1), "total": str(total),
			"next": String((stops[done + 1] as Dictionary)["name"])}), "success")
	else:
		var cache: Dictionary = current_plan().get("cache", {})
		Events.notify.emit(_fmt("route_clear", {"cache": String(cache.get("name", "the cache"))}), "success")


## Opens the cache: pays the run's rewards ONCE and ends the run. Only in the cache phase. The completion is
## recorded before anything is given. Returns {"template", "items": {id: n}, "keepsake": {} | {kind, ...}} or {}.
static func complete() -> Dictionary:
	if not in_cache_phase():
		return {}
	var a := active()
	var tid := String(a["template"])
	var run := int(a["run"])
	var p := plan(tid, int(a["seed"]))
	var items: Dictionary = {}
	for id in p["rewards"]:
		if ItemDB.has_item(String(id)) and not ItemDB.is_story_required(String(id)) and not ItemDB.is_quest_item(String(id)):
			items[String(id)] = int(p["rewards"][id])
	var first := completions(tid) == 0
	var keepsake := keepsake_for(tid, p, first)
	# Record FIRST (like the reward ledger): whatever happens below, this run can never pay twice.
	var st := state()
	st["active"] = {}
	var comp: Dictionary = st["completed"]
	comp[tid] = completions(tid) + 1
	st["last"] = {"template": tid, "run": run, "items": items.duplicate(), "keepsake": keepsake.duplicate(),
		"at": float(GameState.total_minutes)}
	for id in items:
		GameState.give_item(String(id), int(items[id]))
	var parts: Array = []
	for id in items:
		parts.append("%s x%d" % [ItemDB.display_name(String(id)), int(items[id])])
	match String(keepsake.get("kind", "")):
		"dye":
			# A gift: the Loom palette is unlocked directly, skipping its Loom cost (post-Choir only; lead decision P42).
			_unlock_palette(String(keepsake["id"]))
		"decor":
			GameState.give_item(String(keepsake["item"]), int(keepsake.get("count", 1)))
	var ks := keepsake_text(keepsake)
	if ks != "":
		parts.append(ks)
	Events.notify.emit(_fmt("complete", {"name": String(template(tid).get("name", tid))}) + " " + ", ".join(parts), "item")
	if first:
		_award_first_route(tid)
	Events.objectives_changed.emit()
	return {"template": tid, "items": items, "keepsake": keepsake}


## A route's first completion is a new outing walked: a little Wayfinding mastery xp (MP 5.3: masteries grow
## with ordinary play). Mastery dedupes on "expedition:<route>", so it never repeats (not after a reload either);
## safe-loaded: a missing or broken mastery module simply gives nothing. No other side effect. Returns the xp added.
static func _award_first_route(template_id: String) -> int:
	if not ResourceLoader.exists(MASTERY_SCRIPT):
		return 0
	var m: Variant = load(MASTERY_SCRIPT)
	if not (m is Script) or not (m as Script).has_method("award"):
		return 0
	var got: Variant = (m as Script).call("award", "wayfinding", "expedition:" + template_id, Data.FIRST_ROUTE_WAYFINDING_XP)
	return int(got) if (got is int or got is float) else 0


## How a keepsake reads in the completion toast and the panel's "last outing" line ("" for none):
## "a new dye colour (Pumpkin)" or "Pumpkin Lights x2".
static func keepsake_text(keepsake: Dictionary) -> String:
	match String(keepsake.get("kind", "")):
		"dye":
			var id := String(keepsake.get("id", ""))
			var nm := String(ItemDB.dye_palette(id).get("name", "")).trim_suffix(" Dye").strip_edges()
			return String(Data.TEXT["dye_keepsake"]).format({"colour": nm if nm != "" else id.capitalize()})
		"decor":
			return "%s x%d" % [ItemDB.display_name(String(keepsake.get("item", ""))), int(keepsake.get("count", 1))]
	return ""


## The keepsake a finished run of `p` brings: always on a route's first completion, otherwise when the seed's
## roll is under keepsake_chance. Dye colours (Loom palettes) already owned are skipped; with none left a
## decoration comes.
## {} = none this time.
static func keepsake_for(template_id: String, p: Dictionary, first: bool) -> Dictionary:
	var rw: Dictionary = template(template_id).get("rewards", {})
	if not first and float(p.get("keepsake_roll", 1.0)) >= float(rw.get("keepsake_chance", 0.0)):
		return {}
	var pool: Array = []
	for k in rw.get("keepsakes", []):
		var kd: Dictionary = k
		match String(kd.get("kind", "")):
			"dye":
				if not ItemDB.dye_palette(String(kd.get("id", ""))).is_empty() and not _owns_palette(String(kd["id"])):
					pool.append(kd)
			"decor":
				if ItemDB.has_item(String(kd.get("item", ""))):
					pool.append(kd)
	if pool.is_empty():
		return {}
	# Prefer a dye colour she doesn't have yet; decorations when every dye of the route is already hers.
	var dyes: Array = pool.filter(func(k: Dictionary) -> bool: return String(k["kind"]) == "dye")
	var from: Array = dyes if not dyes.is_empty() else pool
	return (from[int(p.get("keepsake_pick", 0)) % from.size()] as Dictionary).duplicate(true)


static func _owns_palette(palette_id: String) -> bool:
	var have: Variant = GameState.wardrobe.get("palettes", [])
	return have is Array and (have as Array).has(palette_id)


static func _unlock_palette(palette_id: String) -> void:
	if palette_id == "" or _owns_palette(palette_id):
		return
	if GameState.has_method("unlock_palette"):
		GameState.call("unlock_palette", palette_id)     # emits Events.appearance_changed itself
		return
	var have: Variant = GameState.wardrobe.get("palettes", [])
	var list: Array = (have as Array).duplicate() if have is Array else []
	list.append(palette_id)
	GameState.wardrobe["palettes"] = list
	Events.appearance_changed.emit()


# --- Tracker / map / board views ------------------------------------------------------------------------------

## Where to go now: {"id", "name", "pos": Vector2, "area", "kind": "stop" | "cache"} ({} without a run).
static func current_target() -> Dictionary:
	var p := current_plan()
	if p.is_empty():
		return {}
	var i := current_stop_index()
	var stops: Array = p["stops"]
	if i < stops.size():
		var s: Dictionary = stops[i]
		return {"id": String(s["id"]), "name": String(s["name"]), "pos": s["pos"], "area": Data.AREA_ID, "kind": "stop"}
	var c: Dictionary = p["cache"]
	return {"id": String(c.get("id", "")), "name": String(c.get("name", "")), "pos": c.get("pos", Vector2.ZERO),
		"area": Data.AREA_ID, "kind": "cache"}


## A tracker card for the running expedition, shaped like Tracker.objective_view() ({} without a run):
## {"kind": "expedition", "header", "title", "text", "hint", "rows": [{label, done, progress, target}] (every stop +
##  the cache), "parts", "step_id", "group": "", "optional": true, "targets": [the CURRENT stop / cache only, so the
##  map pulses and the "where to" lines name just the next place], "where", "current"}.
## It is an OPTIONAL card: Tracker.objective_view() returns it only where the view would otherwise be a signpost /
## done / hidden (never over a chapter, legacy or pointer step; lead decision P36).
static func tracker_view() -> Dictionary:
	var p := current_plan()
	if p.is_empty():
		return {}
	var a := active()
	var i := int(a["stop"])
	var rows: Array = []
	var stops: Array = p["stops"]
	for k in stops.size():
		var s: Dictionary = stops[k]
		var done := k < i
		rows.append({"label": String(s["name"]), "done": done, "progress": int(s["needed"]) if done else (int(a["defeated"]) if k == i else 0),
			"target": int(s["needed"])})
	var c: Dictionary = p["cache"]
	rows.append({"label": "Open %s" % String(c.get("name", "the cache")), "done": false, "progress": 0, "target": 1})
	var tgt := current_target()
	var tid := String(tgt.get("id", ""))
	var tname := String(tgt.get("name", ""))
	var title := String(template(String(a["template"])).get("name", ""))
	var text := "Follow the ribbon lantern to %s." % tname
	var targets: Array = [{"id": tid, "area": Data.AREA_ID, "done": false, "step": tid, "name": tname, "pos": tgt.get("pos", Vector2.ZERO)}]
	return {"kind": "expedition", "header": "EXPEDITION", "title": title, "text": text, "hint": "", "rows": rows,
		"parts": [{"id": tid, "title": title, "text": text, "done": false, "rows": rows, "target": tid, "area": Data.AREA_ID}],
		"step_id": tid, "group": "", "optional": true, "targets": targets,
		"where": "Head to %s (Hallowmere Reach)" % tname, "current": tid}


## Pins for the map of `area_id`: every stop of the running expedition and its cache, in route order
## [{"id", "name", "pos": Vector2 (Reach metres), "done", "current", "kind": "stop" | "cache", "n": stop number
##  (1..; 0 for the cache)}] ([] elsewhere or without a run). map_view draws them on the Reach map.
static func map_marks(area_id: String) -> Array:
	if area_id != Data.AREA_ID:
		return []
	var p := current_plan()
	if p.is_empty():
		return []
	var i := current_stop_index()
	var stops: Array = p["stops"]
	var out: Array = []
	for k in stops.size():
		var s: Dictionary = stops[k]
		out.append({"id": String(s["id"]), "name": String(s["name"]), "pos": s["pos"], "done": k < i, "current": k == i,
			"kind": "stop", "n": k + 1})
	var c: Dictionary = p["cache"]
	out.append({"id": String(c.get("id", "")), "name": String(c.get("name", "")), "pos": c.get("pos", Vector2.ZERO), "done": false,
		"current": i >= stops.size(), "kind": "cache", "n": 0})
	return out


## Map lookup for an expedition place id of the running route ({"pos": Vector2, "radius", "name"}; {} otherwise),
## so map_view's place_disc() can resolve "exp_*" target ids like landmarks (lead decision P35).
static func place_disc(place_id: String) -> Dictionary:
	if not place_id.begins_with("exp_"):
		return {}
	for m in map_marks(Data.AREA_ID):
		if String(m["id"]) == place_id:
			return {"pos": m["pos"], "radius": PLACE_RADIUS, "name": String(m["name"])}
	return {}


## One line for the board / pause menu: "Orchard Patrol - stop 2 of 3: Western Hedgerow (1/3)".
static func summary_line() -> String:
	var p := current_plan()
	if p.is_empty():
		return ""
	var a := active()
	var name := String(template(String(a["template"])).get("name", ""))
	var total := (p["stops"] as Array).size()
	var i := int(a["stop"])
	if i >= total:
		return "%s - every stop is quiet: open %s" % [name, String((p["cache"] as Dictionary).get("name", "the cache"))]
	var s: Dictionary = p["stops"][i]
	return "%s - stop %d of %d: %s (%d/%d)" % [name, i + 1, total, String(s["name"]), int(a["defeated"]), int(s["needed"])]


# --- Helpers --------------------------------------------------------------------------------------------------

static func _fmt(key: String, values: Dictionary) -> String:
	return String(Data.TEXT.get(key, key)).format(values)


static func _int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		return v
	if v is float and is_finite(v):
		return int(round(v))
	return fallback


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	return v != null

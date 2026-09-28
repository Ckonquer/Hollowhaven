extends RefCounted
## Chapter Two quest layer (data/quests_ch2.gd). Stable ids, never indices: `done` lists the ids of
## completed steps. The layer is AVAILABLE once `chapter_one_complete` is set and ACTIVE once
## `ch2_accepted` is set as well; nothing happens (and nothing is shown) before that.
## The current steps are the first step that is not done - or, when that step belongs to a group, every
## not-done step of that group (the three lamps), which can be completed in any order.
## Objectives are state checks, so completion latches: a step whose objectives were met before it was
## reached completes as soon as it is reached. Rewards go through GameState.grant_once("rw_" + id, ...),
## so loading, re-evaluating or repairing a save never grants anything twice.
## GameState calls evaluate() from its coalesced quest evaluation and its 1 s poll.
## The static check_objective() is shared with src/core/optional_log.gd.
## Display rows: an objective with "display": true is a signpost only. check_objective() / objective_status()
## list it with its real done state (the result carries "display": true), but step_done() and
## has_pending_completion() ignore it, so it can never stall or trigger a completion; a step needs at least
## one non-display objective to complete. Honoured by this layer only (optional_log.gd does not read it).

const Data := preload("res://data/quests_ch2.gd")
const MAX_CASCADE := 64

var done: Array = []             # ids of completed steps (rewards applied through the ledger)
var baselines: Dictionary = {}   # step_id -> {counter: value when the step started}; also marks "started"
var _evaluating := false


func steps() -> Array:
	return Data.STEPS


func step_by_id(id: String) -> Dictionary:
	for s in Data.STEPS:
		if s["id"] == id:
			return s
	return {}


## Chapter One is complete, so the Ward Stone can offer Chapter Two.
func is_available() -> bool:
	return _truthy(GameState.get_flag("chapter_one_complete"))


## Available AND accepted: steps are tracked and shown.
func is_active() -> bool:
	return is_available() and _truthy(GameState.get_flag("ch2_accepted"))


func is_done(id: String) -> bool:
	return done.has(id)


## Every step is done (the final step completes when `chapter_two_complete` is set by the ending flow).
func is_finished() -> bool:
	return done.has(Data.FINAL_STEP)


## The step dictionaries to show now ([] when inactive or finished). See the header for groups.
func current_steps() -> Array:
	if not is_active():
		return []
	return _pending_front()


func _pending_front() -> Array:
	var out: Array = []
	var group := ""
	for s in Data.STEPS:
		if done.has(s["id"]):
			continue
		if out.is_empty():
			out.append(s)
			group = String(s.get("group", ""))
			if group == "":
				break
		elif String(s.get("group", "")) == group:
			out.append(s)
		else:
			break
	return out


## Title for the tracker: the group title for grouped steps, else the step title.
func display_title(cur: Array = []) -> String:
	if cur.is_empty():
		cur = current_steps()
	if cur.is_empty():
		return ""
	var g := String(cur[0].get("group", ""))
	if g != "" and Data.GROUPS.has(g):
		return String(Data.GROUPS[g].get("title", ""))
	return step_string(cur[0], "title")


## Player-facing text of a step field ("title", "text", "hint"), honouring the arachnophobia option
## through optional "alt_<field>" entries (same rule as QuestLog.step_string).
func step_string(step: Dictionary, field: String) -> String:
	var alt := "alt_" + field
	if step.has(alt) and bool(Settings.get_value("arachnophobia")):
		return String(step[alt])
	return String(step.get(field, ""))


## [{label, done, progress, target}] for a step (default: the first current step), display rows included
## (they also carry "display": true).
func objective_status(step: Dictionary = {}) -> Array:
	if step.is_empty():
		var cur := current_steps()
		if cur.is_empty():
			return []
		step = cur[0]
	var out: Array = []
	var b: Dictionary = baselines.get(String(step.get("id", "")), {})
	for o in step.get("objectives", []):
		out.append(check_objective(o, b))
	return out


func is_skipped(step: Dictionary) -> bool:
	var f := String(step.get("skip_if_flag", ""))
	return f != "" and _truthy(GameState.get_flag(f))


## Skipped, or every non-display objective is met (display rows never count; no counted objective = never).
func step_done(step: Dictionary) -> bool:
	if is_skipped(step):
		return true
	var counted := 0
	for st in objective_status(step):
		if bool(st.get("display", false)):
			continue
		counted += 1
		if not st["done"]:
			return false
	return counted > 0


## True when evaluate() would complete something now (used by GameState's 1 s poll).
func has_pending_completion() -> bool:
	if _evaluating:
		return false
	for s in current_steps():
		if step_done(s):
			return true
	return false


## Starts newly current steps and completes every current step whose objectives are met (cascading).
func evaluate() -> void:
	if _evaluating or not is_active():
		return
	_evaluating = true
	var changed := false
	var guard := 0
	while guard < MAX_CASCADE:
		guard += 1
		var progressed := false
		for s in _pending_front():
			if not baselines.has(s["id"]):
				_begin_step(s)
				changed = true
			if step_done(s):
				_complete(s)
				changed = true
				progressed = true
		if not progressed:
			break
	_evaluating = false
	if changed:
		Events.objectives_changed.emit()


func _begin_step(s: Dictionary) -> void:
	var group := String(s.get("group", ""))
	var group_started := false
	if group != "":
		for other in Data.STEPS:
			var same_group: bool = other["id"] != s["id"] and String(other.get("group", "")) == group
			if same_group and baselines.has(other["id"]) and not done.has(other["id"]):
				group_started = true
	baselines[s["id"]] = _baseline_for(s)
	Events.chapter2_step_started.emit(String(s["id"]))
	# A step that is already complete (latched) or skipped passes straight through without announcements.
	if step_done(s):
		return
	var hint := step_string(s, "hint")
	if hint != "":
		Events.hint.emit("quest_" + String(s["id"]), hint)   # same id scheme as the legacy steps (hint_quest_<id> flag)
	if group_started:
		return   # a group is announced once, by its title
	var title := String(Data.GROUPS[group].get("title", "")) if Data.GROUPS.has(group) else step_string(s, "title")
	Events.notify.emit("New goal: " + title, "quest")


func _complete(s: Dictionary) -> void:
	var id := String(s["id"])
	if done.has(id):
		return
	done.append(id)   # recorded first: a re-entrant evaluation can never complete it twice
	var skipped := is_skipped(s)
	var oc: Dictionary = s.get("on_complete", {})
	var give: Dictionary = oc.get("give", {})
	var flags: Array = oc.get("flags", [])
	GameState.grant_once("rw_" + id, give, flags, "")
	Events.chapter2_step_completed.emit(id)
	if not skipped:
		Events.notify.emit("Goal complete: " + step_string(s, "title"), "quest")
		if String(oc.get("message", "")) != "":
			Events.notify.emit(String(oc["message"]), "info")
	# Events.chapter2_completed is emitted once, by Game.complete_chapter_two() (the ending flow).


func _baseline_for(s: Dictionary) -> Dictionary:
	var b := {}
	for o in s.get("objectives", []):
		if String(o.get("type", "")) == "counter":
			b[String(o["counter"])] = GameState.get_counter(String(o["counter"]))
	return b


# --- Persistence ------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"accepted": _truthy(GameState.get_flag("ch2_accepted")), "done": done.duplicate(),
		"baselines": baselines.duplicate(true)}


## Restores from to_dict() output (JSON floats normalised; malformed parts ignored, never an error).
## Unknown step ids in `done` are kept (a newer build may have more steps) so they are written back.
## Grants nothing and emits nothing: completion of latched steps happens in the next evaluate().
func from_dict(d: Dictionary) -> void:
	done = []
	var dn: Variant = d.get("done", [])
	if dn is Array:
		for x in dn:
			if (x is String or x is StringName) and String(x) != "" and not done.has(String(x)):
				done.append(String(x))
	baselines = {}
	var bl: Variant = d.get("baselines", {})
	if bl is Dictionary:
		for sid in bl:
			if not (bl[sid] is Dictionary):
				continue
			var b := {}
			for counter in bl[sid]:
				var v: Variant = bl[sid][counter]
				if v is int or (v is float and is_finite(v)):
					b[str(counter)] = int(v)
			baselines[str(sid)] = b
	# Current steps need a baseline (silently, like QuestLog.from_dict) so since_start counters work.
	if is_active():
		for s in _pending_front():
			if not baselines.has(s["id"]):
				baselines[s["id"]] = _baseline_for(s)


# --- Shared objective semantics (also used by optional_log.gd) -------------------------------------------

## Evaluates one objective against GameState: {label, done, progress, target} (+ "display": true for a
## display-only row, see the header). `baseline` is {counter: value at step start} for "since_start" counters.
static func check_objective(o: Dictionary, baseline: Dictionary = {}) -> Dictionary:
	var progress := 0
	var target := 1
	match String(o.get("type", "")):
		"flag":
			progress = 1 if _truthy(GameState.get_flag(String(o.get("flag", "")))) else 0
		"flags_all":
			var fl: Array = o.get("flags", [])
			target = fl.size()
			for f in fl:
				if _truthy(GameState.get_flag(String(f))):
					progress += 1
		"item":
			target = int(o.get("count", 1))
			progress = _owned(String(o.get("item", "")))
		"item_any":
			target = int(o.get("count", 1))
			for it in o.get("items", []):
				progress += _owned(String(it))
		"placed":
			target = int(o.get("count", 1))
			progress = GameState.count_structures(String(o.get("structure", "")))
		"placed_any":
			target = int(o.get("count", 1))
			for sid in o.get("structures", []):
				progress += GameState.count_structures(String(sid))
		"befriended":
			progress = 1 if GameState.is_befriended(String(o.get("creature", ""))) else 0
		"counter":
			target = int(o.get("count", 1))
			var c := String(o.get("counter", ""))
			var v := GameState.get_counter(c)
			if bool(o.get("since_start", false)):
				v -= int(baseline.get(c, 0))
			progress = v
		"discovered":
			var area := String(o.get("area", ""))
			if o.has("landmark"):
				progress = 1 if GameState.is_discovered(area, String(o["landmark"])) else 0
			else:
				target = int(o.get("count", 1))
				progress = GameState.discovered_in(area).size()
		"equipped":
			target = int(o.get("count", 1))
			for slot in o.get("slots", GameState.EQUIPMENT_SLOTS):
				if String(GameState.equipment.get(String(slot), "")) != "":
					progress += 1
		"companion_home_spot":
			target = int(o.get("count", 1))
			for id in GameState.companions:
				var rec: Variant = GameState.companions[id]
				if rec is Dictionary and rec.get("home_spot") is Array:
					progress += 1
		_:
			push_warning("ChapterLog: unknown objective type %s" % str(o.get("type")))
	var label := String(o.get("label", ""))
	if o.has("alt_label") and bool(Settings.get_value("arachnophobia")):
		label = String(o["alt_label"])
	var out := {"label": label, "done": progress >= target, "progress": clampi(progress, 0, maxi(target, 0)), "target": target}
	if is_display_objective(o):
		out["display"] = true
	return out


## A display-only row: shown with its done state, never required for completion.
static func is_display_objective(o: Dictionary) -> bool:
	return _truthy(o.get("display", false))


## Backpack + key pouch + equipped copies of an item.
static func _owned(id: String) -> int:
	return GameState.count_item(id) + GameState.equipped_count(id)


## Flags may hold any JSON value; comparing them with == can be a script error, so test truthiness.
static func _truthy(v: Variant) -> bool:
	return true if v else false

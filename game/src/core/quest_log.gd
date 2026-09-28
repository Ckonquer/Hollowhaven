extends RefCounted
## Linear quest chain driven by data/quests.gd. Objectives are evaluated against GameState.
## Call evaluate() whenever state may have changed (GameState does this on relevant signals and
## once per second). Completing a step applies its rewards exactly once (tracked in `completed`).

const QuestsData := preload("res://data/quests.gd")

var index: int = 0                 # index into STEPS of the current step
var completed: Array = []          # ids of completed steps (rewards applied)
var baselines: Dictionary = {}     # step_id -> {counter_name: value_at_step_start}
var _evaluating := false


func steps() -> Array:
	return QuestsData.STEPS


func current_step() -> Dictionary:
	if index < 0 or index >= QuestsData.STEPS.size():
		return {}
	return QuestsData.STEPS[index]


func current_id() -> String:
	return String(current_step().get("id", ""))


func step_by_id(id: String) -> Dictionary:
	for s in QuestsData.STEPS:
		if s["id"] == id:
			return s
	return {}


## Player-facing text of a step field ("title", "text", "hint"), honouring the arachnophobia option
## through optional "alt_<field>" entries in data/quests.gd (e.g. "alt_text" of the "silk" step).
## UI should use this instead of reading step["title"] / step["text"] directly.
func step_string(step: Dictionary, field: String) -> String:
	var alt := "alt_" + field
	if step.has(alt) and bool(Settings.get_value("arachnophobia")):
		return String(step[alt])
	return String(step.get(field, ""))


func is_completed(step_id: String) -> bool:
	return completed.has(step_id)


func is_chapter_complete() -> bool:
	return completed.has("return")


## Called by GameState.new_game().
func start() -> void:
	index = 0
	completed = []
	baselines = {}
	_begin_step(false)


func _begin_step(announce: bool = true) -> void:
	var s := current_step()
	if s.is_empty():
		return
	var b := {}
	for o in s.get("objectives", []):
		if o.get("type") == "counter":
			b[o["counter"]] = GameState.get_counter(o["counter"])
	baselines[s["id"]] = b
	Events.quest_step_started.emit(s["id"])
	# A step that is already skipped (see is_skipped) is passed straight through by the running
	# evaluate() cascade: no hint card and no "New goal" toast for it.
	var silent := is_skipped(s)
	var hint: String = step_string(s, "hint")
	if hint != "" and not silent:
		Events.hint.emit("quest_" + String(s["id"]), hint)
	if announce and not silent:
		Events.notify.emit("New goal: " + step_string(s, "title"), "quest")
	Events.objectives_changed.emit()


## Returns [{label, done, progress, target}] for the given (or current) step.
func objective_status(step: Dictionary = {}) -> Array:
	if step.is_empty():
		step = current_step()
	var out := []
	for o in step.get("objectives", []):
		out.append(_check(step, o))
	return out


func _check(step: Dictionary, o: Dictionary) -> Dictionary:
	var progress := 0
	var target := 1
	match String(o.get("type", "")):
		"flag":
			progress = 1 if GameState.get_flag(o["flag"]) else 0
		"item":
			target = int(o.get("count", 1))
			progress = GameState.count_item(o["item"])
		"item_any":
			target = int(o.get("count", 1))
			for it in o["items"]:
				progress += GameState.count_item(it)
		"placed":
			target = int(o.get("count", 1))
			progress = GameState.count_structures(o["structure"])
		"befriended":
			progress = 1 if GameState.is_befriended(o["creature"]) else 0
		"counter":
			target = int(o.get("count", 1))
			var v := GameState.get_counter(o["counter"])
			if o.get("since_start", false):
				var b: Dictionary = baselines.get(step["id"], {})
				v -= int(b.get(o["counter"], 0))
			progress = v
		_:
			push_warning("QuestLog: unknown objective type %s" % o.get("type"))
	return {"label": String(o.get("label", "")), "done": progress >= target, "progress": min(progress, target), "target": target}


## True when the step's optional "skip_if_flag" is set: the step no longer applies (e.g. the dungeon
## steps once the Heartseed is back in the Ward Stone) and counts as done without its objectives.
## State-based like everything else, so a save that was stuck on such a step repairs itself on load.
func is_skipped(step: Dictionary) -> bool:
	var f: String = String(step.get("skip_if_flag", ""))
	if f == "":
		return false
	if GameState.get_flag(f):
		return true
	return false


func step_done(step: Dictionary) -> bool:
	if is_skipped(step):
		return true
	var objs: Array = step.get("objectives", [])
	if objs.is_empty():
		return false
	for st in objective_status(step):
		if not st["done"]:
			return false
	return true


## Checks the current step; completes it (and cascades) when all objectives are met.
func evaluate() -> void:
	if _evaluating:
		return
	_evaluating = true
	var guard := 0
	while guard < 32:
		guard += 1
		var s := current_step()
		if s.is_empty() or not step_done(s):
			break
		_complete(s)
	_evaluating = false
	Events.objectives_changed.emit()


func _complete(s: Dictionary) -> void:
	var id: String = s["id"]
	if not completed.has(id):
		completed.append(id)
		var oc: Dictionary = s.get("on_complete", {})
		for f in oc.get("flags", []):
			GameState.set_flag(f, true)
		var give: Dictionary = oc.get("give", {})
		for item_id in give:
			GameState.give_item(item_id, int(give[item_id]))
		Events.quest_step_completed.emit(id)
		if not is_skipped(s):
			Events.notify.emit("Goal complete: " + step_string(s, "title"), "quest")
		if String(oc.get("message", "")) != "":
			Events.notify.emit(oc["message"], "info")
	if index < QuestsData.STEPS.size() - 1:
		index += 1
		_begin_step(true)
	else:
		index = QuestsData.STEPS.size()   # past the end: everything done


func to_dict() -> Dictionary:
	return {"index": index, "completed": completed.duplicate(), "baselines": baselines.duplicate(true)}


## Restores from to_dict() output (usually via JSON: numbers arrive as floats). Malformed parts are
## ignored rather than raising script errors; baselines are normalised back to ints.
func from_dict(d: Dictionary) -> void:
	var idx: Variant = d.get("index", 0)
	var idx_ok: bool = idx is int or (idx is float and is_finite(idx))
	index = clampi(int(idx) if idx_ok else 0, 0, QuestsData.STEPS.size())
	completed = []
	var comp: Variant = d.get("completed", [])
	if comp is Array:
		for c in comp:
			if (c is String or c is StringName) and not completed.has(String(c)):
				completed.append(String(c))
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
	# Repair: every step before `index` must be marked completed (rewards were already granted).
	for i in min(index, QuestsData.STEPS.size()):
		var sid: String = QuestsData.STEPS[i]["id"]
		if not completed.has(sid):
			completed.append(sid)
	var cur := current_step()
	if not cur.is_empty() and not baselines.has(cur["id"]):
		var b := {}
		for o in cur.get("objectives", []):
			if o.get("type") == "counter":
				b[o["counter"]] = GameState.get_counter(o["counter"])
		baselines[cur["id"]] = b

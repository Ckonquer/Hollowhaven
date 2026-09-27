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
	var hint: String = s.get("hint", "")
	if hint != "":
		Events.hint.emit("quest_" + String(s["id"]), hint)
	if announce:
		Events.notify.emit("New goal: " + String(s["title"]), "quest")
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


func step_done(step: Dictionary) -> bool:
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
		Events.notify.emit("Goal complete: " + String(s["title"]), "quest")
		if String(oc.get("message", "")) != "":
			Events.notify.emit(oc["message"], "info")
	if index < QuestsData.STEPS.size() - 1:
		index += 1
		_begin_step(true)
	else:
		index = QuestsData.STEPS.size()   # past the end: everything done


func to_dict() -> Dictionary:
	return {"index": index, "completed": completed.duplicate(), "baselines": baselines.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	index = clampi(int(d.get("index", 0)), 0, QuestsData.STEPS.size())
	completed = []
	for c in d.get("completed", []):
		completed.append(String(c))
	baselines = d.get("baselines", {}).duplicate(true)
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

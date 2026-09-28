extends RefCounted
## Persistent optional-goal tracker (data/optional_goals.gd): Chapter One optional activities, Chapter Two
## side activities and the two legacy free_play goals. Separate from both story layers; never required.
## A visible goal completes (latches) the first time all its objectives hold; its reward is granted through
## GameState.grant_once("rw_" + goal id, ...), so repeating an evaluation or a load never grants twice.
## Saved as GameState "optional": {goal_id: {"done": bool, "done_at": float total_minutes}}.
## Objective semantics are shared with the Chapter Two layer (ChapterLog.check_objective).

const Data := preload("res://data/optional_goals.gd")
const ChapterLog := preload("res://src/core/chapter_log.gd")
const LEGACY_GOALS := ["opt_legacy_bond", "opt_legacy_heartbloom"]

var records: Dictionary = {}     # goal_id -> {"done": bool, "done_at": float} (unknown ids kept verbatim)
var _evaluating := false


func goals() -> Array:
	return Data.GOALS


func goal(id: String) -> Dictionary:
	for g in Data.GOALS:
		if g["id"] == id:
			return g
	return {}


func is_done(id: String) -> bool:
	var r: Variant = records.get(id)
	return r is Dictionary and bool(r.get("done", false))


func is_visible(g: Dictionary) -> bool:
	for c in g.get("visible_if", []):
		if not bool(ChapterLog.check_objective(c)["done"]):
			return false
	return true


## Goals to list in the journal: visible ones plus any already done (in data order).
func visible_goals() -> Array:
	var out: Array = []
	for g in Data.GOALS:
		if is_done(g["id"]) or is_visible(g):
			out.append(g)
	return out


## Visible goals that are not done yet.
func pending_goals() -> Array:
	var out: Array = []
	for g in Data.GOALS:
		if not is_done(g["id"]) and is_visible(g):
			out.append(g)
	return out


func done_count() -> int:
	var n := 0
	for g in Data.GOALS:
		if is_done(g["id"]):
			n += 1
	return n


## Player-facing text ("title", "text"), honouring arachnophobia through optional "alt_<field>" entries.
func step_string(g: Dictionary, field: String) -> String:
	var alt := "alt_" + field
	if g.has(alt) and bool(Settings.get_value("arachnophobia")):
		return String(g[alt])
	return String(g.get(field, ""))


## [{label, done, progress, target}] for a goal (a done goal reports every objective as done).
func objective_status(g: Dictionary) -> Array:
	var out: Array = []
	var finished := is_done(String(g.get("id", "")))
	for o in g.get("objectives", []):
		var st: Dictionary = ChapterLog.check_objective(o)
		if finished:
			st["done"] = true
			st["progress"] = st["target"]
		out.append(st)
	return out


func _objectives_met(g: Dictionary) -> bool:
	var objs: Array = g.get("objectives", [])
	if objs.is_empty():
		return false
	for o in objs:
		if not bool(ChapterLog.check_objective(o)["done"]):
			return false
	return true


## True when evaluate() would complete a goal now (used by GameState's 1 s poll).
func has_pending_completion() -> bool:
	if _evaluating:
		return false
	for g in pending_goals():
		if _objectives_met(g):
			return true
	return false


## Completes every visible goal whose objectives hold. Emits objectives_changed only when something changed.
func evaluate() -> void:
	if _evaluating:
		return
	_evaluating = true
	var changed := false
	for g in pending_goals():
		if _objectives_met(g):
			_complete(g)
			changed = true
	_evaluating = false
	if changed:
		Events.objectives_changed.emit()


func _complete(g: Dictionary) -> void:
	var id := String(g["id"])
	records[id] = {"done": true, "done_at": float(GameState.total_minutes)}   # latched before any reward
	var rw: Dictionary = g.get("reward", {})
	if GameState.grant_once("rw_" + id, rw.get("give", {}), rw.get("flags", []), ""):
		for p in rw.get("patterns", []):
			GameState.unlock_pattern(String(p))
	Events.optional_goal_completed.emit(id)
	Events.notify.emit("Optional goal complete: " + step_string(g, "title"), "quest")
	if String(rw.get("message", "")) != "":
		Events.notify.emit(String(rw["message"]), "info")


## Marks a goal done without rewards or announcements (legacy carry-over). Returns true if it changed.
func mark_done_silently(id: String) -> bool:
	if is_done(id):
		return false
	records[id] = {"done": true, "done_at": float(GameState.total_minutes)}
	return true


## Legacy carry-over: when the legacy quest log already completed `free_play`, both of its goals are done.
## Silent (no rewards - free_play never had any - and no toasts). Idempotent; called on load.
func apply_legacy(quest_log: RefCounted) -> void:
	if quest_log == null:
		return
	if quest_log.is_completed("free_play") or quest_log.index >= quest_log.steps().size():
		for id in LEGACY_GOALS:
			mark_done_silently(id)


# --- Persistence ------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return records.duplicate(true)


## Restores from to_dict() output. Records of unknown goal ids are kept (written back) so a newer
## build's progress is never lost. Malformed entries are ignored; numbers are normalised.
func from_dict(d: Dictionary) -> void:
	records = {}
	for k in d:
		var r: Variant = d[k]
		if not (k is String or k is StringName) or not (r is Dictionary):
			continue
		var rec: Dictionary = (r as Dictionary).duplicate(true)
		var dn: Variant = r.get("done", false)
		rec["done"] = dn if dn is bool else ((dn is int or dn is float) and is_finite(float(dn)) and float(dn) != 0.0)
		var at: Variant = r.get("done_at", 0.0)
		rec["done_at"] = float(at) if (at is int or (at is float and is_finite(at))) else 0.0
		records[String(k)] = rec

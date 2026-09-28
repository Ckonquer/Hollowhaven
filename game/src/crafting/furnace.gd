extends RefCounted
## Furnace queue (static, pure over GameState; MP 3 / 16, docs/CHAPTER_TWO_SPEC.md 3 / 9).
## A furnace smelts "timed" recipes (data/recipes.gd `time` in seconds, station "furnace") as a FINITE queue of
## short jobs that run one after another on the play-seconds timeline (GameState.stats.play_seconds): they
## advance only while the game runs unpaused, never while a menu pauses it or the app is closed, and resume
## exactly where they were after save/load (the timeline is saved with the journey).
## State lives in the structure record (saved with it, spec §3): GameState.structures[uid].data
##   "queue":  [{"recipe": id, "start": play_seconds, "end": play_seconds}, ...]   (ordered, sequential)
##   "output": {item_id: count}                                                  finished, not yet collected
## Exactly once: settle() moves every finished job from the queue to the output buffer in one step (emitting
## Events.crafted once per job); collect() moves the buffer into the backpack. Whatever doesn't fit stays in
## the buffer (persistent overflow) - never dropped, never duplicated.
## Dismantling returns everything once: refund_all(uid) before the record is removed, or refund_record(rec) on a
## record that was already removed (the furnace node does this itself when it is dismantled, so nothing is lost
## even without a build_ops hook). Both empty the record, so doing both never pays twice.
## Mastery xp for the furnace comes only through the Events.crafted listener when a job finishes (never here).
##   const Furnace := preload("res://src/crafting/furnace.gd")
##   Furnace.enqueue(uid, "copper_bar", sources := [])  -> bool   (transactional, like Crafting.craft)
##   Furnace.progress(uid) -> {"jobs": [...], "output": {...}, "capacity", "busy", "ready"}
##   Furnace.collect(uid) -> int

const Crafting := preload("res://src/crafting/crafting.gd")
const Mastery := preload("res://src/core/mastery.gd")

const STATION := "furnace"
const DEFAULT_QUEUE := 4
## Finished items a furnace holds before it refuses new jobs ("collect first"): bounds the saved state.
const OUTPUT_CAP := 60

static var last_reason: String = ""


# --- Queries -----------------------------------------------------------------------------------------------

static func now() -> float:
	var v: Variant = GameState.stats.get("play_seconds", 0.0)
	return float(v) if (v is float or v is int) else 0.0


## True when `uid` is a placed furnace (a structure whose station is "furnace").
static func is_furnace(uid: String) -> bool:
	var rec: Variant = GameState.structures.get(uid)
	return rec is Dictionary and String(ItemDB.structure(String(rec.get("id", ""))).get("station", "")) == STATION


## Max queued jobs: data `queue` + hearthcraft mastery bonus.
static func capacity(uid: String) -> int:
	var sid := ""
	var rec: Variant = GameState.structures.get(uid)
	if rec is Dictionary:
		sid = String(rec.get("id", ""))
	return maxi(int(ItemDB.structure(sid).get("queue", DEFAULT_QUEUE)), 1) + maxi(Mastery.furnace_queue_bonus(), 0)


## Seconds one job of `recipe_id` takes when queued now (data time x hearthcraft station_time_mult).
static func job_seconds(recipe_id: String) -> float:
	return maxf(float(ItemDB.recipe(recipe_id).get("time", 0.0)) * Mastery.station_time_mult(), 1.0)


## Known furnace recipes (data order).
static func recipes() -> Array:
	var out: Array = []
	for rid in Crafting.known_recipes():
		if String(ItemDB.recipe(rid).get("station", "")) == STATION:
			out.append(rid)
	return out


## Current jobs after settling finished ones: [{"recipe", "start", "end"}] (copies).
static func queue(uid: String) -> Array:
	settle(uid)
	var out: Array = []
	for j in _jobs(uid):
		out.append((j as Dictionary).duplicate())
	return out


## Finished output waiting to be collected: {item_id: count} (copy).
static func output(uid: String) -> Dictionary:
	settle(uid)
	return _output(uid).duplicate()


static func output_total(uid: String) -> int:
	var n := 0
	var o := _output(uid)
	for id in o:
		n += int(o[id])
	return n


## Display state: {"jobs": [{"recipe", "result", "count", "fraction", "remaining", "active"}], "output": {..},
## "capacity", "busy" (a job is running), "ready" (items to collect)}.
static func progress(uid: String) -> Dictionary:
	settle(uid)
	var t := now()
	var jobs: Array = []
	var first := true
	for j in _jobs(uid):
		var r := ItemDB.recipe(String(j["recipe"]))
		var dur := maxf(float(j["end"]) - float(j["start"]), 0.001)
		var frac := clampf((t - float(j["start"])) / dur, 0.0, 1.0)
		jobs.append({"recipe": String(j["recipe"]), "result": String(r.get("result", "")), "count": int(r.get("count", 1)),
			"fraction": frac, "remaining": maxf(float(j["end"]) - t, 0.0), "active": first and t >= float(j["start"])})
		first = false
	var o := _output(uid).duplicate()
	return {"jobs": jobs, "output": o, "capacity": capacity(uid), "busy": not jobs.is_empty(), "ready": not o.is_empty()}


## {"ok", "reason", "missing"}: can `recipe_id` be queued at furnace `uid` right now?
static func can_enqueue(uid: String, recipe_id: String, sources: Array = []) -> Dictionary:
	if not is_furnace(uid):
		return {"ok": false, "reason": "Needs a Furnace nearby.", "missing": {}}
	if Crafting.kind(recipe_id) != "timed" or String(ItemDB.recipe(recipe_id).get("station", "")) != STATION:
		return {"ok": false, "reason": "That isn't made in a furnace.", "missing": {}}
	var c := Crafting._check(recipe_id, [STATION], sources, "", true)
	if not bool(c["ok"]):
		return c
	settle(uid)
	if _jobs(uid).size() >= capacity(uid):
		return {"ok": false, "reason": "The furnace queue is full (%d jobs)." % capacity(uid), "missing": {}}
	if output_total(uid) >= OUTPUT_CAP:
		return {"ok": false, "reason": "Collect the finished bars first.", "missing": {}}
	return {"ok": true, "reason": "", "missing": {}}


# --- Changes -----------------------------------------------------------------------------------------------

## Queues one job: consumes its ingredients (backpack first, then `sources` chests) in ONE transaction and appends
## the job after the last one. Returns true on success (nothing changes otherwise).
static func enqueue(uid: String, recipe_id: String, sources: Array = []) -> bool:
	var c := can_enqueue(uid, recipe_id, sources)
	if not bool(c["ok"]):
		last_reason = String(c["reason"])
		return false
	var data := _data(uid)
	var jobs := _jobs(uid)
	var t := now()
	var start := t
	if not jobs.is_empty():
		start = maxf(t, float((jobs[jobs.size() - 1] as Dictionary)["end"]))
	var job := {"recipe": recipe_id, "start": start, "end": start + job_seconds(recipe_id)}
	var commit := func() -> bool:
		jobs.append(job)
		data["queue"] = jobs
		return true
	var used := Crafting.transact(ItemDB.recipe(recipe_id).get("ingredients", {}), sources, commit)
	if used.is_empty():
		# The commit only appends after every ingredient was taken; on failure the queue is left untouched.
		if jobs.has(job):
			jobs.erase(job)
		last_reason = "Something went wrong; nothing was used."
		return false
	last_reason = ""
	Audio.play_ui("ui_craft")
	Events.station_queue_changed.emit(uid)
	return true


## Moves every finished job into the output buffer (exactly once each: the job leaves the queue in the same
## step). Emits Events.crafted per finished job and Events.station_queue_changed. Returns jobs finished.
## Cheap when nothing is due (no allocation), so a furnace may call it a few times per second.
static func settle(uid: String) -> int:
	var rec: Variant = GameState.structures.get(uid)
	if not (rec is Dictionary):
		return 0
	return _settle_rec(rec as Dictionary, uid)


## settle() on a record dictionary (also one already removed from GameState.structures while it is being
## dismantled). `uid` "" = don't announce the queue change.
static func _settle_rec(rec: Dictionary, uid: String) -> int:
	var data: Variant = rec.get("data")
	if not (data is Dictionary):
		return 0
	var q: Variant = (data as Dictionary).get("queue")
	if not (q is Array) or (q as Array).is_empty():
		return 0
	var first: Variant = (q as Array)[0]
	var t := now()
	if first is Dictionary and _num((first as Dictionary).get("end")) and float((first as Dictionary)["end"]) > t:
		return 0
	var jobs := _jobs_of(data)
	var out := _output_of(data)
	var done: Array = []
	while not jobs.is_empty() and float((jobs[0] as Dictionary)["end"]) <= t:
		var j: Dictionary = jobs.pop_front()
		var r := ItemDB.recipe(String(j["recipe"]))
		var item := String(r.get("result", ""))
		var n := int(r.get("count", 1))
		if ItemDB.has_item(item) and n > 0:
			out[item] = int(out.get(item, 0)) + n
			done.append([String(j["recipe"]), item, n])
		else:
			_held_of(data).append(j)   # a recipe this build doesn't know: kept verbatim, never lost
	(data as Dictionary)["queue"] = jobs
	(data as Dictionary)["output"] = out
	for d in done:
		GameState.stats["items_crafted"] = int(GameState.stats.get("items_crafted", 0)) + int(d[2])
		Events.crafted.emit(String(d[0]), String(d[1]), int(d[2]))
	if not done.is_empty() and uid != "":
		Events.station_queue_changed.emit(uid)
	return done.size()


## Moves finished output into the backpack. What doesn't fit stays in the furnace's buffer (saved), so nothing is
## lost or duplicated. Returns the number of items that went into the backpack.
static func collect(uid: String) -> int:
	settle(uid)
	var out := _output(uid)
	if out.is_empty():
		last_reason = "Nothing is ready yet."
		return 0
	var moved := 0
	var left_any := false
	for item in out.keys():
		var n := int(out[item])
		var left: int = int(GameState.inventory.add(String(item), n))
		var added := n - left
		if added > 0:
			moved += added
			Events.item_added.emit(String(item), added)
		if left > 0:
			out[item] = left
			left_any = true
		else:
			out.erase(item)
	_data(uid)["output"] = out
	last_reason = "Your backpack is full; the rest waits in the furnace." if left_any else ""
	if moved > 0:
		Audio.play_ui("ui_craft")
	if moved > 0 or left_any:
		Events.station_queue_changed.emit(uid)
	return moved


## Dismantling: returns everything once and empties the station. Finished jobs (and the output buffer) give
## their results; unfinished jobs give their ingredients back. Items go through GameState.give_item (a full
## backpack drops the rest as persistent pickups at `drop_pos`). Returns {item_id: count} given.
static func refund_all(uid: String, drop_pos: Variant = null) -> Dictionary:
	var rec: Variant = GameState.structures.get(uid)
	if not (rec is Dictionary):
		return {}
	return refund_record(rec as Dictionary, drop_pos, uid)


## refund_all() on a furnace record dictionary, also one that BuildOps.dismantle already removed from
## GameState.structures (the furnace node calls this when it is taken apart). Idempotent: the record is emptied,
## so a second call (or a refund_all() done before the removal) gives nothing.
static func refund_record(rec: Dictionary, drop_pos: Variant = null, uid: String = "") -> Dictionary:
	var data: Variant = rec.get("data")
	if not (data is Dictionary):
		return {}
	_settle_rec(rec, uid)
	var given := {}
	var out := _output_of(data)
	for item in out:
		given[item] = int(given.get(item, 0)) + int(out[item])
	for j in _jobs_of(data):
		var ings: Dictionary = ItemDB.recipe(String(j["recipe"])).get("ingredients", {})
		for id in ings:
			given[id] = int(given.get(id, 0)) + int(ings[id])
	(data as Dictionary)["queue"] = []
	(data as Dictionary)["output"] = {}
	for id in given:
		if ItemDB.has_item(String(id)):
			GameState.give_item(String(id), int(given[id]), drop_pos)
		else:
			GameState.orphans.append({"where": "inventory", "slot": -1, "stack": {"id": String(id), "count": int(given[id])}})
	if uid != "":
		Events.station_queue_changed.emit(uid)
	return given


# --- Internals ---------------------------------------------------------------------------------------------

static func _data(uid: String) -> Dictionary:
	var rec: Dictionary = GameState.structures[uid]
	var d: Variant = rec.get("data")
	if not (d is Dictionary):
		d = {}
		rec["data"] = d
	return d


## The saved queue, normalised in place (JSON floats, damaged entries dropped). Unknown recipe ids from a later
## version are kept and never block: they sort to the end with their saved timing.
static func _jobs(uid: String) -> Array:
	if not GameState.structures.has(uid):
		return []
	return _jobs_of(_data(uid))


static func _jobs_of(data: Dictionary) -> Array:
	var q: Variant = data.get("queue")
	var out: Array = []
	if q is Array:
		for j in q:
			if j is Dictionary and (j as Dictionary).get("recipe") is String and _num(j.get("start")) and _num(j.get("end")):
				out.append({"recipe": String(j["recipe"]), "start": float(j["start"]), "end": float(j["end"])})
	data["queue"] = out
	return out


## Jobs whose recipe this build doesn't know (kept in data.held_jobs so a newer save never loses them).
static func _held_of(data: Dictionary) -> Array:
	var h: Variant = data.get("held_jobs")
	if not (h is Array):
		h = []
		data["held_jobs"] = h
	return h


static func _output(uid: String) -> Dictionary:
	if not GameState.structures.has(uid):
		return {}
	return _output_of(_data(uid))


static func _output_of(data: Dictionary) -> Dictionary:
	var o: Variant = data.get("output")
	var out := {}
	if o is Dictionary:
		for k in o:
			if _num(o[k]) and int(o[k]) > 0:
				out[String(k)] = int(o[k])
	data["output"] = out
	return out


static func _num(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v))

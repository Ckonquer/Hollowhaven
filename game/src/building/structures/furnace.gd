extends "res://src/building/structures/workbench.gd"
## Furnace: a crafting station ("crafting_station", station_id "furnace") that smelts bars as a short, finite,
## saved queue (logic and state: src/crafting/furnace.gd over GameState.structures[uid].data).
## Interacting collects finished bars (what doesn't fit waits inside) and opens the crafting panel on the
## furnace queue: Game.open_panel("crafting", {"station": "furnace", "uid": uid}).
## Visible state: the model's coal bed (parts "flame") and a warm mouth light are dark while idle, flicker while
## smelting and glow steadily with sparkles when bars are ready; the prompt names the job and what's ready. Checks the queue twice a second (no allocation when
## nothing is due), never every frame. With Settings reduce_flashing the smelting glow stays steady (no flicker).
## Dismantling (BuildOps.dismantle removes the record, then calls play_remove_and_free): everything still inside -
## finished bars and the ingredients of unfinished jobs - goes back to Krystal once (Furnace.refund_record).
## Contract (spec §9): queue_add(recipe_id) -> bool, queue() -> Array, collect() -> int.

const FurnaceLogic := preload("res://src/crafting/furnace.gd")
const Crafting := preload("res://src/crafting/crafting.gd")

const POLL_SECONDS := 0.5
const STATE_IDLE := 0
const STATE_WORKING := 1
const STATE_READY := 2

var light: OmniLight3D
var sparkles: CPUParticles3D
var _state := -1
var _busy := false                 # jobs still queued (smelting), whatever the display state
var _poll := 0.0
var _t := 0.0
var _base_energy := 0.9
var _steady := false               # Settings reduce_flashing: no flicker (re-read on every poll)
var _rec: Dictionary = {}          # this furnace's saved record, kept so a dismantle can still refund it


func _setup_behaviour() -> void:
	super._setup_behaviour()
	station_id = FurnaceLogic.STATION
	_remember_record()
	_steady = bool(Settings.get_value("reduce_flashing"))
	var ld: Dictionary = def.get("light", {})
	_base_energy = float(ld.get("energy", 0.9))
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = ld.get("color", Color("ff9a52"))
	light.omni_range = float(ld.get("range", 4.0))
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 8.0
	light.position = parts.get("light_pos", Vector3(0, 0.55, 0.45))
	light.visible = false
	add_child(light)
	sparkles = CPUParticles3D.new()
	sparkles.name = "Ready"
	sparkles.amount = 6
	sparkles.lifetime = 1.4
	sparkles.mesh = Shapes.star(0.07)
	sparkles.local_coords = true
	sparkles.material_override = U.sparkle_mat(Palette.WARD_GLOW)
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparkles.emission_box_extents = Vector3(0.5, 0.1, 0.25)
	sparkles.direction = Vector3.UP
	sparkles.spread = 25.0
	sparkles.gravity = Vector3(0, 0.15, 0)
	sparkles.initial_velocity_min = 0.05
	sparkles.initial_velocity_max = 0.2
	sparkles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparkles.emitting = false
	sparkles.position = light.position + Vector3(0, 0.35, 0)
	add_child(sparkles)
	Events.station_queue_changed.connect(_on_queue_changed)
	refresh()


# --- Contract (spec §9) ------------------------------------------------------------------------------------

func queue_add(recipe_id: String) -> bool:
	var ok := FurnaceLogic.enqueue(uid, recipe_id)
	refresh()
	return ok


func queue() -> Array:
	return FurnaceLogic.queue(uid)


func collect() -> int:
	var n := FurnaceLogic.collect(uid)
	refresh()
	return n


# --- Interaction ---------------------------------------------------------------------------------------------

func get_interaction(_player: Node) -> Dictionary:
	if uid == "" or not FurnaceLogic.is_furnace(uid):
		return {"text": "Use %s" % display_name(), "enabled": true}
	var p := FurnaceLogic.progress(uid)
	var out: Dictionary = p["output"]
	if not out.is_empty():
		return {"text": "Collect %s" % Crafting.describe_items(out), "enabled": true}
	var jobs: Array = p["jobs"]
	if not jobs.is_empty():
		var j: Dictionary = jobs[0]
		return {"text": "Furnace: %s %d%% (%d queued)" % [ItemDB.display_name(String(j["result"])), int(float(j["fraction"]) * 100.0), jobs.size()], "enabled": true}
	return {"text": "Use %s" % display_name(), "enabled": true}


func interact(_player: Node) -> void:
	if uid != "" and FurnaceLogic.is_furnace(uid):
		var before := FurnaceLogic.output(uid)
		var n := FurnaceLogic.collect(uid)
		if n > 0:
			var got := {}
			var after := FurnaceLogic.output(uid)
			for id in before:
				var d := int(before[id]) - int(after.get(id, 0))
				if d > 0:
					got[id] = d
			Events.notify.emit("Collected %s." % Crafting.describe_items(got), "success")
		elif not before.is_empty():
			Events.notify.emit(FurnaceLogic.last_reason, "warn")
		refresh()
	Game.open_panel("crafting", {"station": station_id, "uid": uid})
	Events.hint.emit("furnace_queue", "Queue a few batches, then carry on: bars keep smelting while you play. Come back and press {interact} to collect them.")


# --- Visual state ------------------------------------------------------------------------------------------

func _on_queue_changed(changed_uid: String) -> void:
	if changed_uid == uid:
		refresh()


## Syncs light/sparkles with the saved state (settles finished jobs first).
func refresh() -> void:
	if light == null:
		return
	_remember_record()
	var st := STATE_IDLE
	_busy = false
	if uid != "" and FurnaceLogic.is_furnace(uid):
		FurnaceLogic.settle(uid)
		_busy = not _jobs_empty()
		if FurnaceLogic.output_total(uid) > 0:
			st = STATE_READY
		elif _busy:
			st = STATE_WORKING
	if st == _state:
		return
	_state = st
	light.visible = st != STATE_IDLE
	sparkles.emitting = st == STATE_READY
	light.light_energy = _base_energy
	var coals: Variant = parts.get("flame")   # the model's glowing coal bed: cold (hidden) while idle
	if coals is Node3D:
		(coals as Node3D).visible = st != STATE_IDLE


func _jobs_empty() -> bool:
	var rec: Variant = GameState.structures.get(uid)
	if not (rec is Dictionary):
		return true
	var d: Variant = (rec as Dictionary).get("data")
	if not (d is Dictionary):
		return true
	var q: Variant = (d as Dictionary).get("queue")
	return not (q is Array) or (q as Array).is_empty()


func current_state() -> int:
	return _state


## Keeps a reference to the live record (same Dictionary as GameState.structures[uid]; no copy).
func _remember_record() -> void:
	var r: Variant = GameState.structures.get(uid) if uid != "" else null
	if r is Dictionary:
		_rec = r


## Taken apart: BuildOps.dismantle has already removed the record. Whatever is still inside goes back to Krystal
## once (a full backpack drops the rest as persistent pickups); a refund_all() the caller did before the removal
## emptied the record, so nothing is ever paid twice.
func play_remove_and_free() -> void:
	if not _removing and uid != "" and not _rec.is_empty() and not GameState.structures.has(uid):
		var p: Variant = _rec.get("pos")
		var drop: Variant = null
		if p is Array and (p as Array).size() == 3:
			drop = Vector3(float(p[0]), float(p[1]) + 0.6, float(p[2]))
		FurnaceLogic.refund_record(_rec, drop)
		_rec = {}
	super.play_remove_and_free()


func _process(delta: float) -> void:
	if light == null or uid == "" or not _busy:
		return
	_poll += delta
	if _poll >= POLL_SECONDS:
		_poll = 0.0
		_steady = bool(Settings.get_value("reduce_flashing"))
		FurnaceLogic.settle(uid)   # emits station_queue_changed -> refresh() when a batch finishes
	if _steady:
		light.light_energy = _base_energy
		return
	_t += delta
	light.light_energy = _base_energy * (1.0 + sin(_t * 6.1) * 0.08 + sin(_t * 11.3 + 0.7) * 0.05)

extends Node3D
## A fixed resonator of the Choir Vault (MP §13.3 Phase B): a bronze bell-frame carrying one LARGE plate
## per symbol of the set taught on the Bellmaker's Floor (room 5; data/works_layout_deep.gd bell_symbols()).
## Striking the plates in the required order activates it (signal activated). Each strike shows the plate
## lighting up + its name, and a caption names it - never pitch, never colour alone, no timing window
## (window_seconds() is INF with timing_assist; boss modules that want a window read it).
## A wrong plate gives a gentle "flat note" and restarts the sequence (never damage).
##   var r = Resonator.new(); r.setup({"id": "hw_resonator_west", "symbols": Layout.bell_symbols()})
##   r.set_sequence(["moon", "leaf", "bell"]); r.strike("moon") -> "progress" | "done" | "wrong" | "idle"
## Default sequence = the symbols in their taught order (usable without a boss driving it).

signal struck(resonator_id: String, symbol_id: String, correct: bool)
signal activated(resonator_id: String)
signal reset_done(resonator_id: String)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")

const PLATE_SIZE := 0.95
const PLATE_GAP := 1.25
const WINDOW_SECONDS := 12.0

var resonator_id: String = ""
var symbols: Array = []            # [{"id", "name", "caption"}]
var sequence: Array = []           # required order of symbol ids
var progress: int = 0
var active: bool = false
var enabled: bool = true

var _plates: Dictionary = {}       # symbol id -> {"node", "lit": MeshInstance3D}
var _core: MeshInstance3D
var _core_mat: Material
var _hv: Node3D


func setup(p: Dictionary) -> void:
	resonator_id = String(p.get("id", resonator_id))
	symbols = (p.get("symbols", []) as Array).duplicate(true)
	if p.has("sequence"):
		sequence = (p["sequence"] as Array).duplicate()


func _ready() -> void:
	add_to_group("hw_resonator")
	if symbols.is_empty():
		symbols = [{"id": "moon", "name": "Moon", "caption": "[the Moon plate hums]"}, {"id": "leaf", "name": "Leaf", "caption": "[the Leaf plate hums]"}]
	if sequence.is_empty():
		for s in symbols:
			sequence.append(String(s["id"]))
	_build()
	Events.settings_changed.connect(_on_settings_changed)
	_refresh()


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" and _hv != null:
		_hv.visible = Art.high_visibility()


static func window_seconds() -> float:
	return INF if Art.timing_assist() else WINDOW_SECONDS


func symbol_ids() -> Array:
	var out: Array = []
	for s in symbols:
		out.append(String(s["id"]))
	return out


## Required order (ids must belong to this resonator's symbols; unknown ids are dropped).
func set_sequence(seq: Array) -> void:
	var ids := symbol_ids()
	sequence.clear()
	for s in seq:
		if ids.has(String(s)):
			sequence.append(String(s))
	if sequence.is_empty():
		sequence = ids
	reset()


func reset() -> void:
	progress = 0
	active = false
	_refresh()
	reset_done.emit(resonator_id)


func is_active() -> bool:
	return active


## Strikes one plate. Returns "progress", "done" (just activated), "wrong" (sequence restarted) or "idle".
func strike(symbol_id: String) -> String:
	if not enabled or active or not _plates.has(symbol_id):
		return "idle"
	var info := _symbol(symbol_id)
	if progress < sequence.size() and String(sequence[progress]) == symbol_id:
		progress += 1
		Art.sfx3d("ward_hum", global_position + Vector3.UP * 1.6, -6.0)
		Art.caption("%s (%d of %d)" % [String(info.get("caption", "[a plate hums]")), progress, sequence.size()])
		struck.emit(resonator_id, symbol_id, true)
		if progress >= sequence.size():
			active = true
			Art.sfx3d("ward_restore", global_position + Vector3.UP * 1.6, -6.0)
			Art.caption("[the resonator rings true and holds its note]")
			_refresh()
			activated.emit(resonator_id)
			return "done"
		_refresh()
		return "progress"
	progress = 0
	Art.sfx3d("dir_creak", global_position + Vector3.UP * 1.6, -8.0)
	Art.caption("[a flat, wrong note - the plates fall quiet]")
	struck.emit(resonator_id, symbol_id, false)
	_refresh()
	return "wrong"


func _symbol(symbol_id: String) -> Dictionary:
	for s in symbols:
		if String(s["id"]) == symbol_id:
			return s
	return {}


func _build() -> void:
	var bronze := Mat.outlined(Mat.toon(Palette.COPPER.darkened(0.2), {"rim": 0.45, "specular": 0.4}), 0.016)
	var wood := Mat.outlined(Mat.toon(Color("6a4a36")), 0.016)
	var n := symbols.size()
	var span := float(n) * PLATE_GAP + 0.4
	for sx in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.26, 3.0, 0.26), wood), Vector3(sx * span * 0.5, 1.5, 0))
	Kit.add(self, Kit.box(Vector3(span + 0.5, 0.26, 0.34), wood), Vector3(0, 3.05, 0))
	_core_mat = Mat.toon(Palette.COPPER.darkened(0.35), {"rim": 0.5})
	_core = Kit.cylinder(0.35, 0.55, 0.8, _core_mat, 14)
	Kit.add(self, _core, Vector3(0, 3.6, 0))
	for i in n:
		var s: Dictionary = symbols[i]
		var sid := String(s["id"])
		var holder := Node3D.new()
		holder.name = "Plate_" + sid
		add_child(holder)
		holder.position = Vector3((float(i) - float(n - 1) * 0.5) * PLATE_GAP, 1.75, 0.0)
		Kit.add(holder, Kit.cylinder(0.012, 0.012, 1.0, bronze, 5), Vector3(0, 0.75, 0))
		Kit.add(holder, Kit.cylinder(0.56, 0.56, 0.08, bronze, 20), Vector3.ZERO, Vector3(90, 0, 0))
		var lit := Kit.cylinder(0.6, 0.6, 0.04, Mat.glow(Palette.LANTERN_GLOW, 1.6), 20)
		Kit.add(holder, lit, Vector3(0, 0, -0.05), Vector3(90, 0, 0))
		lit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sym := Art.symbol(holder, sid, PLATE_SIZE * 0.8, Color("f3e6c8"), String(s.get("name", sid.capitalize())))
		sym.position = Vector3(0, 0, 0.07)
		var it: Node3D = Interactable.new()
		it.setup({"text": "Strike the %s plate" % String(s.get("name", sid.capitalize())), "size": Vector3(1.1, 1.3, 1.0),
			"offset": Vector3(0, 0, 0.4), "handler": Callable(self, "_on_plate").bind(sid), "id": resonator_id + "_" + sid})
		it.name = "Strike_" + sid
		holder.add_child(it)
		_plates[sid] = {"node": holder, "lit": lit}
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(span + 0.3, 3.2, 0.5)
	cs.shape = sh
	cs.position = Vector3(0, 1.6, -0.1)
	body.add_child(cs)
	add_child(body)
	_hv = Node3D.new()
	_hv.name = "Hv"
	add_child(_hv)
	var hv_ring := Art.bold_ring(_hv, span * 0.5 + 0.4)
	hv_ring.position = Vector3(0, 0.04, 0.9)
	_hv.visible = Art.high_visibility()


func _on_plate(_player: Node, symbol_id: String) -> void:
	strike(symbol_id)


func _refresh() -> void:
	for i in sequence.size():
		var sid := String(sequence[i])
		if _plates.has(sid):
			((_plates[sid] as Dictionary)["lit"] as MeshInstance3D).visible = active or i < progress
	for sid in _plates:
		if not sequence.has(sid):
			((_plates[sid] as Dictionary)["lit"] as MeshInstance3D).visible = active
	if _core != null:
		_core.material_override = Mat.glow(Palette.WARD_GLOW, 1.8) if active else _core_mat

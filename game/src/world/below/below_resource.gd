extends Node3D
## Harvestable resources of The Below (follows the harvestable/interactable contracts):
##   glowcap -> hand (E), 1-2 glowcap          silk -> hand (E), 1-2 silk ("Pale Thread" clump in arachnophobia mode)
##   crystal -> pickaxe, 1-2 echo_shard (3 hits)
## Depletion persists with GameState.deplete(node_id, respawn_minutes) and a stable node_id.
##   var r = Res.new(); r.setup({"id": "below_glowcap_1", "kind": "glowcap"})

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const KINDS := {
	"glowcap": {"item": "glowcap", "tool": "hand", "min": 1, "max": 2, "respawn": 1440.0, "hits": 1, "name": "Glowcap Cluster", "verb": "Pick Glowcaps", "sound": "pickup", "event_kind": "glowcap"},
	"silk": {"item": "silk", "tool": "hand", "min": 1, "max": 2, "respawn": 1440.0, "hits": 1, "name": "Silk Clump", "alt_name": "Pale Thread Tangle", "verb": "Gather Silk", "alt_verb": "Gather Pale Thread", "sound": "grass_pull", "event_kind": "silk"},
	"crystal": {"item": "echo_shard", "tool": "pickaxe", "min": 1, "max": 2, "respawn": 1440.0, "hits": 3, "name": "Echo Crystal", "verb": "", "sound": "rock_break", "event_kind": "crystal"},
}

var node_id: String = ""
var kind: String = "glowcap"
var hits: int = 0
var depleted: bool = false

var _def: Dictionary = {}
var _visual: Node3D
var _area: Area3D
var _light: OmniLight3D
var _tween: Tween
var _check_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(p: Dictionary) -> void:
	node_id = String(p.get("id", node_id))
	kind = String(p.get("kind", kind))


func _ready() -> void:
	_def = KINDS.get(kind, KINDS["glowcap"])
	_rng.seed = hash(node_id)
	_build()
	_area = Area3D.new()
	_area.collision_layer = 16
	_area.collision_mask = 0
	_area.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.7 if kind != "crystal" else 0.85
	cs.shape = sh
	cs.position = Vector3(0, 0.45, 0)
	_area.add_child(cs)
	add_child(_area)
	if kind == "silk":
		Events.settings_changed.connect(_on_settings_changed)
	_set_depleted(GameState.is_depleted(node_id))


func _on_settings_changed(key: String) -> void:
	if key == "arachnophobia" and _visual != null:
		_visual.queue_free()
		_visual = null
		_build()
		_visual.visible = not depleted


func _arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	match kind:
		"glowcap":
			var stem := Mat.toon(Color("dfeee2"), {"rim": 0.3})
			var cap_mat := Mat.outlined(Mat.toon(Palette.GLOWCAP, {"emission": Palette.GLOWCAP, "emission_energy": 1.3, "rim": 0.5}), 0.012)
			var spots := Mat.glow(Color("e8fff4"), 1.8)
			for i in 5:
				var a := float(i) / 5.0 * TAU + _rng.randf_range(-0.3, 0.3)
				var r := 0.0 if i == 0 else _rng.randf_range(0.14, 0.3)
				var h := 0.34 if i == 0 else _rng.randf_range(0.12, 0.24)
				var cr := 0.16 if i == 0 else _rng.randf_range(0.07, 0.12)
				var p := Vector3(cos(a) * r, 0, sin(a) * r)
				var tilt := Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12))
				var m := Node3D.new()
				_visual.add_child(m)
				m.position = p
				m.rotation_degrees = tilt
				Kit.add(m, Kit.cylinder(cr * 0.28, cr * 0.36, h, stem, 8), Vector3(0, h * 0.5, 0))
				Kit.add(m, Kit.sphere(cr, cap_mat, 8, 12), Vector3(0, h, 0), Vector3.ZERO, Vector3(1.0, 0.55, 1.0))
				Kit.add(m, Kit.sphere(cr * 0.18, spots, 4, 6), Vector3(cr * 0.45, h + cr * 0.4, 0))
			_light = OmniLight3D.new()
			_light.light_color = Palette.GLOWCAP
			_light.light_energy = 0.7
			_light.omni_range = 2.8
			_light.omni_attenuation = 1.4
			_light.distance_fade_enabled = true
			_light.distance_fade_begin = 26.0
			_light.distance_fade_length = 6.0
			_light.light_volumetric_fog_energy = 0.2
			_visual.add_child(_light)
			_light.position = Vector3(0, 0.5, 0)
		"silk":
			if _arachno():
				var root_mat := Mat.outlined(Mat.toon(Color("d8ccb4"), {"rim": 0.35}), 0.012)
				for i in 7:
					var a := float(i) / 7.0 * TAU
					var seg := Kit.cylinder(0.025, 0.045, _rng.randf_range(0.5, 0.8), root_mat, 6)
					_visual.add_child(seg)
					seg.position = Vector3(cos(a) * 0.12, 0.25, sin(a) * 0.12)
					seg.rotation = Vector3(_rng.randf_range(-1.2, 1.2), a, _rng.randf_range(-1.2, 1.2))
				Kit.add(_visual, Kit.blob(0.2, root_mat, 71, 0.35, 0.8), Vector3(0, 0.18, 0))
				Kit.add(_visual, Kit.sphere(0.04, Mat.glow(Color("f2ead8"), 1.2), 4, 6), Vector3(0.08, 0.35, 0.05))
			else:
				var silk_mat := Mat.outlined(Mat.toon(Palette.SILK_WEB, {"rim": 0.6, "emission": Palette.SILK_WEB, "emission_energy": 0.12}), 0.012)
				Kit.add(_visual, Kit.blob(0.26, silk_mat, 33, 0.3, 0.7), Vector3(0, 0.2, 0))
				Kit.add(_visual, Kit.blob(0.16, silk_mat, 34, 0.35, 0.8), Vector3(0.2, 0.12, 0.12))
				for i in 5:
					var a := float(i) / 5.0 * TAU
					var t := Kit.cylinder(0.008, 0.008, 0.7, silk_mat, 4)
					_visual.add_child(t)
					t.position = Vector3(cos(a) * 0.2, 0.35, sin(a) * 0.2)
					t.rotation = Vector3(_rng.randf_range(-0.9, 0.9), 0, _rng.randf_range(-0.9, 0.9))
		"crystal":
			var base := Mat.toon(Palette.SILK_ROCK if global_position.y < -8.0 else Palette.RUIN_STONE_DARK)
			Kit.add(_visual, Kit.blob(0.42, base, 17, 0.25, 0.55), Vector3(0, 0.12, 0))
			var cm := Mat.outlined(Mat.toon(Color("b9a3f0"), {"emission": Color("9f86e8"), "emission_energy": 0.9, "rim": 0.8}), 0.015)
			for i in 5:
				var a := float(i) / 5.0 * TAU + 0.4
				var h := _rng.randf_range(0.35, 0.75) * (1.3 if i == 0 else 1.0)
				var sh := Node3D.new()
				_visual.add_child(sh)
				sh.position = Vector3(cos(a) * 0.14, 0.2, sin(a) * 0.14) if i > 0 else Vector3(0, 0.25, 0)
				sh.rotation = Vector3(_rng.randf_range(-0.5, 0.5), a, _rng.randf_range(-0.5, 0.5)) if i > 0 else Vector3.ZERO
				Kit.add(sh, Kit.cylinder(0.07, 0.09, h, cm, 6), Vector3(0, h * 0.5, 0))
				Kit.add(sh, Kit.cone(0.07, 0.16, cm, 6), Vector3(0, h + 0.08, 0))
			_light = OmniLight3D.new()
			_light.light_color = Color("b9a3f0")
			_light.light_energy = 0.55
			_light.omni_range = 2.6
			_light.distance_fade_enabled = true
			_light.distance_fade_begin = 26.0
			_light.distance_fade_length = 6.0
			_light.light_volumetric_fog_energy = 0.2
			_visual.add_child(_light)
			_light.position = Vector3(0, 0.7, 0)


func _display_name() -> String:
	if _arachno() and _def.has("alt_name"):
		return String(_def["alt_name"])
	return String(_def["name"])


# --- Contracts ----------------------------------------------------------------------------------

func get_harvest_info() -> Dictionary:
	if depleted:
		return {}
	return {"tool": String(_def["tool"]), "name": _display_name()}


func get_interaction(_player: Node = null) -> Dictionary:
	if depleted or String(_def["tool"]) != "hand":
		return {}
	var verb: String = String(_def.get("alt_verb", _def["verb"])) if _arachno() else String(_def["verb"])
	return {"text": verb, "enabled": true}


func interact(player: Node = null) -> void:
	if depleted or String(_def["tool"]) != "hand":
		return
	harvest_hit(player, "")


func harvest_hit(_player: Node, _tool_item_id: String = "") -> void:
	if depleted:
		return
	hits += 1
	if hits < int(_def["hits"]):
		Audio.play_3d("mine_hit", global_position + Vector3(0, 0.5, 0))
		_wobble()
		return
	var n := _rng.randi_range(int(_def["min"]), int(_def["max"]))
	var item := String(_def["item"])
	var at := global_position + Vector3(0, 0.4, 0)
	GameState.give_item(item, n, at)
	Events.harvested.emit(String(_def["event_kind"]), item, n, at)
	Audio.play_3d(String(_def["sound"]), at)
	GameState.deplete(node_id, float(_def["respawn"]))
	_set_depleted(true)


func is_depleted() -> bool:
	return depleted


func _set_depleted(on: bool) -> void:
	depleted = on
	hits = 0
	if _visual != null:
		_visual.visible = not on
	if on:
		if is_in_group("harvestable"):
			remove_from_group("harvestable")
		if is_in_group("interactable"):
			remove_from_group("interactable")
		if _area != null:
			_area.collision_layer = 0
	else:
		add_to_group("harvestable")
		if String(_def.get("tool", "")) == "hand":
			add_to_group("interactable")
		if _area != null:
			_area.collision_layer = 16
	set_process(on)


func _process(delta: float) -> void:
	# Depleted: check occasionally whether it has regrown (in-game day).
	_check_t += delta
	if _check_t < 5.0:
		return
	_check_t = 0.0
	if not GameState.is_depleted(node_id):
		_set_depleted(false)
		if _visual != null:
			_visual.scale = Vector3.ONE * 0.1
			var tw := create_tween()
			tw.tween_property(_visual, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _wobble() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_visual.rotation = Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(_visual, "rotation:z", 0.12, 0.05)
	_tween.tween_property(_visual, "rotation:z", -0.08, 0.07)
	_tween.tween_property(_visual, "rotation:z", 0.0, 0.08)

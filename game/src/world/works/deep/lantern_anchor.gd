extends Node3D
## A fixed lantern anchor (Choir Vault, the Bell Throat practice station): an iron hook-post standing in
## a carved stone ring. Krystal raises her ORDINARY lantern here (interact; the lantern is switched on for
## her if it was off) and for reveal_time() seconds the anchor becomes a strong light source (group
## "light_source", light_radius = reveal_radius, read by Combat.light_at) that shows which form truly
## lights the ground - the Choir's exposure rule (MP §13.3). No timing skill: timing_assist doubles the
## reveal time; high_visibility_cues adds a bold ring. Works with sound muted (visual + caption).
##   var a = Anchor.new(); a.setup({"id": "hw_vault_anchor_0", "reveal_radius": 9.0}); parent.add_child(a)
##   a.raised.connect(...)   a.raise(player) -> bool   a.is_raised()   a.lower()
## Boss modules may call raise()/lower() themselves and read reveal_point()/reveal_radius.

signal raised(anchor_id: String)
signal lowered(anchor_id: String)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")

const REVEAL_SECONDS := 8.0
const RING_RADIUS := 1.15
const HOOK_HEIGHT := 2.3

var anchor_id: String = ""
var reveal_radius: float = 9.0
var reveal_seconds: float = REVEAL_SECONDS
var require_lantern: bool = true
var enabled: bool = true
var raise_count: int = 0
var light_radius: float = 0.0          # Combat.light_at reads this while in group light_source
var light_strength: float = 1.0

var _left: float = 0.0
var _raised: bool = false
var _light: OmniLight3D
var _glow: Node3D
var _ring_glow: MeshInstance3D
var _hv: MeshInstance3D


func setup(p: Dictionary) -> void:
	anchor_id = String(p.get("id", anchor_id))
	reveal_radius = float(p.get("reveal_radius", reveal_radius))
	reveal_seconds = float(p.get("reveal_seconds", reveal_seconds))
	require_lantern = bool(p.get("require_lantern", require_lantern))


func reveal_time() -> float:
	return reveal_seconds * (2.0 if Art.timing_assist() else 1.0)


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("hw_lantern_anchor")
	_build()
	var a := Area3D.new()
	a.name = "InteractArea"
	a.collision_layer = 16
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 1.3
	sh.height = 2.2
	cs.shape = sh
	cs.position = Vector3(0, 1.1, 0)
	a.add_child(cs)
	add_child(a)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	var bcs := CollisionShape3D.new()
	var bsh := CylinderShape3D.new()
	bsh.radius = 0.16
	bsh.height = HOOK_HEIGHT
	bcs.shape = bsh
	bcs.position = Vector3(0, HOOK_HEIGHT * 0.5, 0)
	body.add_child(bcs)
	add_child(body)
	Events.settings_changed.connect(_on_settings_changed)
	_apply(false)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" and _hv != null:
		_hv.visible = Art.high_visibility()


func _build() -> void:
	var stone := Mat.outlined(Mat.toon(Color("a89cb0"), {"rim": 0.3, "noise": 0.12}), 0.016)
	var iron := Mat.outlined(Mat.toon(Color("3b3238"), {"rim": 0.45}), 0.014)
	Kit.add(self, Kit.torus(RING_RADIUS - 0.18, RING_RADIUS, stone), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	for i in 6:
		var ang := TAU * float(i) / 6.0
		Kit.add(self, Kit.box(Vector3(0.16, 0.05, 0.3), stone), Vector3(cos(ang) * (RING_RADIUS - 0.35), 0.03, sin(ang) * (RING_RADIUS - 0.35)), Vector3(0, -rad_to_deg(ang), 0))
	Kit.add(self, Kit.cylinder(0.1, 0.13, HOOK_HEIGHT, iron, 8), Vector3(0, HOOK_HEIGHT * 0.5, 0))
	Kit.add(self, Kit.box(Vector3(0.08, 0.08, 0.55), iron), Vector3(0, HOOK_HEIGHT - 0.05, 0.25))
	Kit.add(self, Kit.torus(0.05, 0.1, iron), Vector3(0, HOOK_HEIGHT - 0.2, 0.5), Vector3(90, 0, 0))
	_ring_glow = Kit.torus(RING_RADIUS - 0.12, RING_RADIUS - 0.04, Mat.glow(Palette.LANTERN_GLOW, 0.5))
	Kit.add(self, _ring_glow, Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.3, 1))
	_ring_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow = Node3D.new()
	_glow.name = "RaisedLantern"
	add_child(_glow)
	_glow.position = Vector3(0, HOOK_HEIGHT - 0.55, 0.5)
	Kit.add(_glow, Kit.cylinder(0.15, 0.15, 0.3, Mat.transparent(Color(1.0, 0.86, 0.6, 0.3), true), 10))
	Kit.add(_glow, Kit.sphere(0.09, Mat.glow(Palette.LANTERN_GLOW, 3.4), 8, 10), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.4, 1))
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Palette.LANTERN_GLOW
	_light.omni_range = reveal_radius
	_light.omni_attenuation = 0.9
	_light.light_energy = 2.4
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 40.0
	_light.distance_fade_length = 10.0
	_glow.add_child(_light)
	_hv = Art.bold_ring(self, RING_RADIUS + 0.25)
	_hv.visible = Art.high_visibility()


func _apply(on: bool) -> void:
	_raised = on
	_glow.visible = on
	light_radius = reveal_radius if on else 0.0
	if on:
		add_to_group("light_source")
	elif is_in_group("light_source"):
		remove_from_group("light_source")
	_ring_glow.material_override = Mat.glow(Palette.LANTERN_GLOW, 2.2 if on else 0.5)
	set_process(on)


func is_raised() -> bool:
	return _raised


func is_light_active() -> bool:
	return _raised


func reveal_point() -> Vector3:
	return global_position if is_inside_tree() else position


## Raises the lantern here. `player` (optional) gets her lantern switched on. False if she has none
## (require_lantern) or the anchor is disabled.
func raise(player: Node = null) -> bool:
	if not enabled:
		return false
	if require_lantern and not GameState.has_item("lantern"):
		return false
	if player != null and is_instance_valid(player) and player.has_method("set_lantern") and not Art.lantern_raised(player):
		player.call("set_lantern", true)
	_left = reveal_time()
	raise_count += 1
	var first := not _raised
	_apply(true)
	if first:
		Art.sfx3d("lantern_on", global_position + Vector3.UP * 2.0, -2.0)
		Art.caption("[your lantern flares on the anchor hook]")
	raised.emit(anchor_id)
	return true


func lower() -> void:
	if not _raised:
		return
	_apply(false)
	lowered.emit(anchor_id)


func tick(dt: float) -> void:
	if not _raised:
		return
	_left -= dt
	if _left <= 0.0:
		lower()


func _process(delta: float) -> void:
	tick(delta)


func get_interaction(_player: Node = null) -> Dictionary:
	if not enabled:
		return {}
	if require_lantern and not GameState.has_item("lantern"):
		return {"text": "Raise a lantern at the anchor (you need a Lantern)", "enabled": false}
	if _raised:
		return {"text": "Your lantern burns on the anchor", "enabled": false}
	return {"text": "Raise your lantern at the anchor", "enabled": true}


func interact(player: Node = null) -> void:
	raise(player)

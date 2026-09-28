extends Node3D
## A Moonveil ward candle on a tall wrought-iron stand. Used for the Count's Gallery arena (three of
## them, MP §13.1), the Looking-Glass Hall's practice candle, the ballroom's hearth candle and the candle
## beside the dancing rail. "Daylight" in the manor is stored ward-light: these candles never depend on
## the clock. Lighting is instant (no hold, no timing) and needs only the ordinary Lantern.
##
## API (the Count Velour boss module uses it; group "ward_candle"):
##   candle_id: String, kind: String, pool_radius: float
##   is_lit() -> bool
##   light(source: Variant = null) -> bool        true if it changed (emits lit / state_changed)
##   darken(source: Variant = null) -> bool       true if it changed (emits darkened / state_changed)
##   pool_center() -> Vector3                     floor point under the flame
##   in_pool(pos: Vector3) -> bool                inside the lit pool (XZ distance, lit only)
##   flame_position() -> Vector3
##   set_interactable(on: bool)                   e.g. false while a scripted beat owns the candle
##   signals lit(candle), darkened(candle), state_changed(candle, lit: bool)
## Light contract: group "light_source" with light_radius (= pool_radius) and is_light_active() (= lit),
## so Combat.light_at() and light-fearing enemies see the pool.
## high_visibility_cues: a bold ring marks a lit pool, and another marks a candle waiting to be lit
## (shape + brightness, never colour alone); both follow the setting live.
##   setup({"id": "north", "kind": "ward", "lit": true, "pool_radius": 3.2, "height": 1.55,
##          "needs_lantern": true, "prompt": "Light the ward candle"})

signal lit(candle: Node3D)
signal darkened(candle: Node3D)
signal state_changed(candle: Node3D, is_lit: bool)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const IRON := Color("3a2c3e")
const GOLD := Color("d9b25a")
const WAX := Color("f7ecd8")
const FLAME := Color("ffc562")
const POOL := Color("ffcf7a")

var candle_id: String = ""
var kind: String = "ward"            # ward | practice | hearth | rail
var pool_radius: float = 3.2
var light_radius: float = 3.2        # light_source contract (kept equal to pool_radius)
var stand_height: float = 1.55
var needs_lantern: bool = true
var prompt: String = "Light the ward candle"
var interactable: bool = true
var last_source: Variant = null

var _lit := false
var _flame: MeshInstance3D
var _halo: MeshInstance3D
var _light: OmniLight3D
var _pool: MeshInstance3D
var _bold: MeshInstance3D
var _beckon: MeshInstance3D       # high_visibility_cues: a bold ring round the base of a candle waiting to be lit
var _t := 0.0


func setup(params: Dictionary) -> void:
	candle_id = String(params.get("id", candle_id))
	kind = String(params.get("kind", kind))
	pool_radius = float(params.get("pool_radius", pool_radius))
	light_radius = pool_radius
	stand_height = float(params.get("height", stand_height))
	needs_lantern = bool(params.get("needs_lantern", needs_lantern))
	prompt = String(params.get("prompt", prompt))
	_lit = bool(params.get("lit", false))


func _ready() -> void:
	if name.begins_with("@") or name == "":
		name = "WardCandle_" + candle_id
	add_to_group("interactable")
	add_to_group("ward_candle")
	add_to_group("light_source")
	_build()
	_apply(false)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func is_lit() -> bool:
	return _lit


func is_light_active() -> bool:
	return _lit


func flame_position() -> Vector3:
	return global_position + Vector3.UP * (stand_height + 0.36) if is_inside_tree() else position + Vector3.UP * (stand_height + 0.36)


func pool_center() -> Vector3:
	return global_position if is_inside_tree() else position


func in_pool(pos: Vector3) -> bool:
	if not _lit:
		return false
	var c := pool_center()
	return Vector2(pos.x - c.x, pos.z - c.z).length() <= pool_radius


func light(source: Variant = null) -> bool:
	if _lit:
		return false
	_lit = true
	last_source = source
	_apply(true)
	if is_inside_tree():
		Audio.play_3d("brazier_light", flame_position(), -8.0, 0.05, 20.0)
	Events.caption.emit("[a ward candle catches with a soft gold hush]")
	lit.emit(self)
	state_changed.emit(self, true)
	return true


func darken(source: Variant = null) -> bool:
	if not _lit:
		return false
	_lit = false
	last_source = source
	_apply(true)
	if is_inside_tree():
		Audio.play_3d("lantern_off", flame_position(), -6.0, 0.05, 20.0)
	Events.caption.emit("[a ward candle gutters out]")
	darkened.emit(self)
	state_changed.emit(self, false)
	return true


func set_interactable(on: bool) -> void:
	interactable = on
	_apply(false)


## Sets the state without signals, sounds or captions (restoring a saved state on load).
func restore(on: bool) -> void:
	_lit = on
	_apply(false)


# --- Interaction contract ---------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if not interactable:
		return {}
	if _lit:
		return {"text": "The candle burns warm and steady", "enabled": false}
	if needs_lantern and not GameState.has_item("lantern"):
		return {"text": prompt, "enabled": false, "reason": "You need your Lantern to light it."}
	return {"text": prompt, "enabled": true}


func interact(player: Node = null) -> void:
	if not interactable or _lit:
		return
	if needs_lantern and not GameState.has_item("lantern"):
		Events.notify.emit("You need your Lantern to light it.", "info")
		return
	light(player)


# --- Visuals ------------------------------------------------------------------------------------------------

func _build() -> void:
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.3}), 0.012)
	var gold := Mat.toon(GOLD, {"rim": 0.5, "specular": 0.3})
	var base := Kit.cylinder(0.26, 0.34, 0.14, iron, 12)
	Kit.add(self, base, Vector3(0, 0.07, 0))
	var foot_ring := Kit.torus(0.22, 0.3, gold)
	Kit.add(self, foot_ring, Vector3(0, 0.14, 0))
	var shaft := Kit.cylinder(0.045, 0.06, stand_height, iron, 8)
	Kit.add(self, shaft, Vector3(0, stand_height * 0.5 + 0.1, 0))
	for k in 3:
		var knot := Kit.sphere(0.075, gold, 8, 10)
		Kit.add(self, knot, Vector3(0, 0.45 + float(k) * stand_height * 0.3, 0))
	var dish := Kit.cylinder(0.2, 0.08, 0.08, gold, 14)
	Kit.add(self, dish, Vector3(0, stand_height + 0.08, 0))
	var wax := Kit.cylinder(0.075, 0.085, 0.26, Mat.toon(WAX, {"rim": 0.25}), 12)
	Kit.add(self, wax, Vector3(0, stand_height + 0.25, 0))
	_flame = Kit.sphere(0.06, Mat.glow(FLAME, 3.2), 8, 10)
	Kit.add(self, _flame, Vector3(0, stand_height + 0.46, 0), Vector3.ZERO, Vector3(1.0, 1.9, 1.0))
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo = Kit.sphere(0.2, Mat.transparent(Color(1.0, 0.8, 0.45, 0.16), true), 8, 12)
	Kit.add(self, _halo, Vector3(0, stand_height + 0.46, 0))
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.name = "CandleLight"
	_light.light_color = FLAME
	_light.light_energy = 1.3
	_light.omni_range = maxf(pool_radius + 1.6, 3.5)
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 26.0
	_light.distance_fade_length = 8.0
	_light.position = Vector3(0, stand_height + 0.55, 0)
	add_child(_light)
	# The lit pool: a soft ring on the floor showing where the candle's light reaches (MP §13.1).
	_pool = MeshInstance3D.new()
	_pool.name = "Pool"
	var tm := TorusMesh.new()
	tm.inner_radius = pool_radius - 0.08
	tm.outer_radius = pool_radius
	tm.rings = 40
	tm.ring_segments = 6
	_pool.mesh = tm
	_pool.material_override = Mat.glow(POOL, 0.7)
	_pool.scale = Vector3(1.0, 0.25, 1.0)
	_pool.position = Vector3(0, 0.03, 0)
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)
	# High-visibility cue: a bold, wide ring (shape + brightness, never colour alone).
	_bold = MeshInstance3D.new()
	_bold.name = "BoldPool"
	var tb := TorusMesh.new()
	tb.inner_radius = pool_radius - 0.28
	tb.outer_radius = pool_radius + 0.04
	tb.rings = 40
	tb.ring_segments = 6
	_bold.mesh = tb
	_bold.material_override = Mat.glow(Color("fff1c4"), 1.6)
	_bold.scale = Vector3(1.0, 0.2, 1.0)
	_bold.position = Vector3(0, 0.035, 0)
	_bold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bold)
	_beckon = MeshInstance3D.new()
	_beckon.name = "BoldBeckon"
	var tk := TorusMesh.new()
	tk.inner_radius = 0.42
	tk.outer_radius = 0.6
	tk.rings = 24
	tk.ring_segments = 6
	_beckon.mesh = tk
	_beckon.material_override = Mat.glow(Color("fff1c4"), 1.8)
	_beckon.scale = Vector3(1.0, 0.3, 1.0)
	_beckon.position = Vector3(0, 0.04, 0)
	_beckon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beckon)
	var body := StaticBody3D.new()
	body.name = "StandBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = stand_height + 0.3
	cs.shape = cyl
	cs.position = Vector3(0, (stand_height + 0.3) * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.75
	ics.shape = sph
	ics.position = Vector3(0, 1.1, 0)
	ib.add_child(ics)
	add_child(ib)


func _apply(_animate: bool) -> void:
	if _flame == null:
		return
	_flame.visible = _lit
	_halo.visible = _lit
	_light.visible = _lit
	_pool.visible = _lit
	var hv := bool(Settings.get_value("high_visibility_cues"))
	_bold.visible = _lit and hv
	_beckon.visible = not _lit and interactable and hv
	set_process(_lit)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_apply(false)


func _process(delta: float) -> void:
	_t += delta
	if _light != null and _lit:
		_light.light_energy = 1.3 + sin(_t * 7.3) * 0.06 + sin(_t * 12.1) * 0.04
		_flame.scale = Vector3(1.0, 1.9 + sin(_t * 9.0) * 0.12, 1.0)

extends Node3D
## The shortcut hatch of Tobin's Lost Shift (docs/CHAPTER_TWO_SPEC.md §1: "annex hatch (after ta_hatch_open)
## -> surface annex_hatch"). It opens ONCE, from below, and stays open (flag `ta_hatch_open`):
##   variant "ceiling" (tobin_annex, ta_sump): origin on the sump floor under the hole; the lid sits at the top
##     of the shaft (`shaft_top` metres up). Closed: "Slide back the rusted bolt" sets the flag and swings the
##     lid open (daylight falls down the shaft). Open: "Climb up to the mine mouth" -> surface / annex_hatch.
##   variant "ground" (surface, beside the mine mouth; built by src/world/surface/c1x/tobin_door.gd): origin
##     on the ground at the hatch centre. Closed: greyed "Bolted fast from below". Open: "Climb down the
##     hatch" -> tobin_annex / annex_hatch_below (the shortcut works both ways once opened).
## Interaction contract: groups "interactable" + "area_exit", a layer-16 StaticBody "Interact". No solid
## collision (a hatch never trips Krystal up). Listens to Events.flag_set so both ends agree at once.
##   var h = AnnexHatch.new(); h.setup({"variant": "ceiling", "shaft_top": 7.6}); parent.add_child(h)

signal opened
signal travelled(area: String, spawn: String)   # just before Game.change_area (tests listen)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Fx := preload("res://src/world/common/fx.gd")

const FLAG := "ta_hatch_open"
const LID := 1.25
const OPEN_ANGLE := -100.0            # degrees about the hinge (x axis): the far edge swings up
const DAYLIGHT := Color("ffe9c8")

var variant: String = "ceiling"
var flag: String = FLAG
var target_area: String = "surface"
var target_spawn: String = "annex_hatch"
var shaft_top: float = 7.6
var use_respawn: bool = false
var travel_enabled: bool = true
var is_open: bool = false

var _busy: bool = false
var _lid_pivot: Node3D
var _bolt: Node3D
var _sky: MeshInstance3D
var _hole: MeshInstance3D
var _ladder_top: Node3D
var _light: SpotLight3D
var _tween: Tween


func setup(p: Dictionary) -> void:
	variant = String(p.get("variant", variant))
	if variant == "ground":
		target_area = "tobin_annex"
		target_spawn = "annex_hatch_below"
	flag = String(p.get("flag", flag))
	target_area = String(p.get("target_area", target_area))
	target_spawn = String(p.get("target_spawn", target_spawn))
	shaft_top = float(p.get("shaft_top", shaft_top))


func _ready() -> void:
	name = "AnnexHatch" if variant == "ceiling" else "AnnexHatchTop"
	add_to_group("interactable")
	add_to_group("area_exit")
	if variant == "ceiling":
		_build_ceiling()
	else:
		_build_ground()
	_apply(bool(GameState.get_flag(flag)), false)
	Events.flag_set.connect(_on_flag_set)


## {"area", "spawn"} this hatch leads to (area_exit contract).
func destination() -> Dictionary:
	return {"area": target_area, "spawn": target_spawn}


func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if variant == "ceiling":
		if not is_open:
			return {"text": "Slide back the rusted bolt", "enabled": true}
		return {"text": "Climb up to the mine mouth", "enabled": true}
	if not is_open:
		return {"text": "An iron hatch", "enabled": false, "reason": "Bolted fast from below."}
	return {"text": "Climb down the hatch", "enabled": true}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	if not is_open:
		if variant == "ceiling":
			open_hatch()
		else:
			Events.notify.emit("Bolted fast from below.", "info")
		return
	if Game.mode != "playing" and travel_enabled:
		return
	_busy = true
	Audio.play_3d("step_wood", global_position + Vector3.UP, -6.0)
	travelled.emit(target_area, target_spawn)
	if not travel_enabled:
		_busy = false
		return
	create_tween().tween_callback(func() -> void: _busy = false).set_delay(4.0)
	Game.change_area(target_area, target_spawn)


## Unbolts the hatch (ceiling side only). The flag is set FIRST (persisted). False if it was already open.
func open_hatch() -> bool:
	if is_open:
		return false
	GameState.set_flag(flag, true)       # _on_flag_set animates the lid
	if not is_open:
		_apply(true, true)
	var top := global_position + Vector3.UP * (shaft_top - 0.4)
	Audio.play_3d("gate_unlock", top, -2.0)
	if is_inside_tree():
		Fx.burst(get_parent(), top, "dust", 1.3, Vector3.DOWN)
	Events.camera_shake.emit(0.12, 0.35)
	Events.caption.emit("[a rusted bolt grinds back; the hatch thumps open]")
	Events.notify.emit("The hatch swings open. Daylight! A shortcut up to the mine mouth.", "success")
	opened.emit()
	return true


func _on_flag_set(flag_name: String, value: Variant) -> void:
	if flag_name != flag or is_open:
		return
	if value is bool and value:
		_apply(true, variant == "ceiling" and is_inside_tree())


func _apply(open: bool, animate: bool) -> void:
	is_open = open
	var target := deg_to_rad(OPEN_ANGLE) if open else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(_lid_pivot, "rotation:x", target, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_lid_pivot.rotation.x = target
	if _bolt != null:
		_bolt.position.x = 0.22 if open else 0.0
	if _sky != null:
		_sky.visible = open
	if _light != null:
		_light.visible = open
	if _hole != null:
		_hole.visible = open
	if _ladder_top != null:
		_ladder_top.visible = open


# --- Visuals -------------------------------------------------------------------------------------------

func _lid(parent: Node3D) -> void:
	var planks := Mat.outlined(Mat.toon(Palette.WOOD_DARK, {"noise": 0.15, "noise_scale": 2.2}), 0.014)
	var iron := Mat.outlined(Mat.toon(Color("3b3238"), {"rim": 0.4}), 0.012)
	for i in 4:
		var w := LID / 4.0
		Kit.add(parent, Kit.box(Vector3(w - 0.015, 0.08, LID), planks), Vector3(-LID * 0.5 + w * (float(i) + 0.5), 0, LID * 0.5))
	for z: float in [0.25, LID - 0.25]:
		Kit.add(parent, Kit.box(Vector3(LID + 0.02, 0.1, 0.1), iron), Vector3(0, 0.0, z))
	Kit.add(parent, Kit.torus(0.03, 0.08, iron), Vector3(0, 0.07, LID * 0.7), Vector3(0, 0, 0))


func _interact_body(radius: float, pos: Vector3) -> void:
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	cs.shape = sph
	cs.position = pos
	ib.add_child(cs)
	add_child(ib)


func _build_ceiling() -> void:
	# The lid closes the top of the shaft; its hinge is on the north (-z) edge.
	_lid_pivot = Node3D.new()
	_lid_pivot.name = "LidPivot"
	add_child(_lid_pivot)
	_lid_pivot.position = Vector3(0, shaft_top, -LID * 0.5)
	_lid(_lid_pivot)
	# The bolt under the lid (seen from below): slides aside when opened.
	_bolt = Node3D.new()
	_bolt.name = "Bolt"
	add_child(_bolt)
	var iron := Mat.outlined(Mat.toon(Color("5a4a48"), {"rim": 0.4}), 0.012)
	Kit.add(_bolt, Kit.box(Vector3(0.5, 0.07, 0.07), iron), Vector3(0, shaft_top - 0.09, LID * 0.25))
	# Daylight above the shaft and a soft shaft of light down the ladder (unshadowed).
	_sky = MeshInstance3D.new()
	_sky.name = "Daylight"
	var pm := PlaneMesh.new()
	pm.size = Vector2(LID, LID)
	_sky.mesh = pm
	_sky.material_override = Mat.glow(DAYLIGHT, 1.5)
	_sky.rotation_degrees.x = 180.0
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sky)
	_sky.position = Vector3(0, shaft_top + 0.45, 0)
	_light = SpotLight3D.new()
	_light.name = "ShaftLight"
	_light.light_color = DAYLIGHT
	_light.light_energy = 1.8
	_light.spot_range = shaft_top + 2.0
	_light.spot_angle = 24.0
	_light.spot_attenuation = 0.7
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 1.2
	add_child(_light)
	_light.position = Vector3(0, shaft_top + 0.2, 0)
	_light.rotation_degrees = Vector3(-90, 0, 0)
	_interact_body(1.2, Vector3(0, 1.1, 0.35))


func _build_ground() -> void:
	var stone := Mat.outlined(Mat.toon(Palette.STONE_DARK, {"noise": 0.12}), 0.014)
	var half := LID * 0.5 + 0.11
	for s: float in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(LID + 0.44, 0.16, 0.22), stone), Vector3(0, 0.05, float(s) * half))
		Kit.add(self, Kit.box(Vector3(0.22, 0.16, LID), stone), Vector3(float(s) * half, 0.05, 0))
	_lid_pivot = Node3D.new()
	_lid_pivot.name = "LidPivot"
	add_child(_lid_pivot)
	_lid_pivot.position = Vector3(0, 0.1, -LID * 0.5)
	_lid(_lid_pivot)
	# The dark hole and the top of the ladder (only once opened).
	var void_mat := StandardMaterial3D.new()
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_mat.albedo_color = Color(0.04, 0.03, 0.03)
	_hole = MeshInstance3D.new()
	_hole.name = "Hole"
	var pm := PlaneMesh.new()
	pm.size = Vector2(LID - 0.05, LID - 0.05)
	_hole.mesh = pm
	_hole.material_override = void_mat
	_hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hole)
	_hole.position = Vector3(0, 0.035, 0)
	_ladder_top = Node3D.new()
	_ladder_top.name = "LadderTop"
	add_child(_ladder_top)
	var timber := Mat.outlined(Mat.toon(Palette.MINE_TIMBER), 0.014)
	for sx: float in [-0.28, 0.28]:
		Kit.add(_ladder_top, Kit.box(Vector3(0.08, 0.7, 0.08), timber), Vector3(float(sx), 0.2, -LID * 0.5 + 0.12))
	Kit.add(_ladder_top, Kit.box(Vector3(0.56, 0.05, 0.06), timber), Vector3(0, 0.3, -LID * 0.5 + 0.12))
	_interact_body(1.1, Vector3(0, 0.6, 0))

extends Node3D
## A Lantern Road arch (MP §9, docs/CHAPTER_TWO_SPEC.md §1 and §8): a small wooden festival arch with a
## hanging lantern. The first use lights it for good (flag ch2_arch_<id>, Events.arch_lit, a toast, and
## it becomes this area's return point); every later use opens the Lantern Road travel list
## (Game.travel_lantern_road). Neither works while Game.can_fast_travel() is false (something chasing
## Krystal, a boss fight, a cutscene): the prompt is shown greyed with the reason instead.
## Interaction contract: group "interactable" + a layer-16 sphere; the two posts are solid (layer 1).
##   setup({"id": "commons", "area": "hallowmere_reach", "spawn": "commons_arch", "name": "..."})
## id/spawn/name default from data/hallowmere_layout.gd ARCHES.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")
const Fx := preload("res://src/world/common/fx.gd")
const Reach := preload("res://data/hallowmere_layout.gd")

const GLOW := Color("ffb45a")
const POST_X := 1.25

var arch_id: String = ""
var area_name: String = Reach.AREA_ID     # area id this arch stands in (for the respawn point)
var spawn_id: String = ""
var display_name: String = ""

## The prompt is polled by the interaction probe (~12 Hz); its travel check scans the "enemy" group, so
## it is reused for this long (like bed.gd's danger check). interact() always checks afresh.
const PROMPT_CHECK_MS := 400

var glass_material: StandardMaterial3D
var light: OmniLight3D
var _t := 0.0
var _busy := false
var _prompt_ft: Dictionary = {}
var _prompt_ft_ms := -100000
var _prompt_ft_mode := ""


func setup(params: Dictionary) -> void:
	arch_id = String(params.get("id", arch_id))
	area_name = String(params.get("area", area_name))
	var def: Dictionary = Reach.ARCHES.get(arch_id, {})
	spawn_id = String(params.get("spawn", def.get("spawn", arch_id + "_arch")))
	display_name = String(params.get("name", def.get("name", arch_id.capitalize())))


func _ready() -> void:
	name = "LanternArch_" + arch_id
	add_to_group("interactable")
	add_to_group("lantern_arch")
	_build()
	_apply_lit(is_lit())


func flag_name() -> String:
	return Reach.arch_flag(arch_id)


func is_lit() -> bool:
	return arch_id != "" and bool(GameState.get_flag(flag_name()))


static func _travel_check() -> Dictionary:
	if Game.has_method("can_fast_travel"):
		var r: Variant = Game.can_fast_travel()
		if r is Dictionary:
			return r
	return {"ok": Game.mode == "playing", "reason": "You can't travel right now."}


## _travel_check() for the prompt, reused for PROMPT_CHECK_MS (re-checked at once when Game.mode changes).
func _prompt_check() -> Dictionary:
	var now := Time.get_ticks_msec()
	if _prompt_ft.is_empty() or now - _prompt_ft_ms >= PROMPT_CHECK_MS or Game.mode != _prompt_ft_mode:
		_prompt_ft = _travel_check()
		_prompt_ft_ms = now
		_prompt_ft_mode = Game.mode
	return _prompt_ft


# --- Interaction -------------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	var text := "Light the lantern arch" if not is_lit() else "Travel the Lantern Road"
	var ft := _prompt_check()
	if not bool(ft.get("ok", false)):
		return {"text": text, "enabled": false, "reason": String(ft.get("reason", ""))}
	return {"text": text, "enabled": true}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	var ft := _travel_check()
	if not bool(ft.get("ok", false)):
		Events.notify.emit(String(ft.get("reason", "You can't travel right now.")), "warn")
		return
	if not is_lit():
		light_arch()
		return
	_busy = true
	if Game.has_method("travel_lantern_road"):
		await Game.travel_lantern_road()
	if is_instance_valid(self):
		_busy = false


## Lights the arch for good. Returns true if it was newly lit by this call.
func light_arch() -> bool:
	if arch_id == "" or is_lit():
		return false
	GameState.set_flag(flag_name(), true)
	Events.arch_lit.emit(arch_id)
	# The arch Krystal lit last is where she wakes in this area (docs/CHAPTER_TWO_SPEC.md §1).
	if spawn_id != "" and Game.has_method("set_respawn"):
		Game.set_respawn(area_name, spawn_id)
	_apply_lit(true)
	if is_inside_tree():
		Fx.burst(get_parent(), global_position + Vector3(0, 2.6, 0.2), "sparkle", 1.5)
		Audio.play_3d("checkpoint_light", global_position + Vector3(0, 2.4, 0), -2.0)
	Events.notify.emit("Lantern arch lit: %s. The Lantern Road can bring you here." % display_name, "success")
	return true


# --- Visuals ------------------------------------------------------------------------------------------

func _build() -> void:
	var wood := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.12, "rim": 0.2}), 0.02)
	var trim := Mat.outlined(Mat.toon(Color("c96a3a"), {"noise": 0.1, "rim": 0.2}), 0.018)
	var frame := NodeVisuals.Merger.new()
	for sx in [-1.0, 1.0]:
		frame.add(NodeVisuals._cyl(0.13, 0.16, 3.0, 8), Transform3D(Basis(), Vector3(float(sx) * POST_X, 1.5, 0)), Palette.WOOD_DARK)
		frame.add(Kit.blob_mesh(0.28, 8700 + int(sx), 0.3, 0.45, 1), Transform3D(Basis(), Vector3(float(sx) * POST_X, 0.05, 0)), Palette.STONE)
	# A shallow curved top made of short segments.
	var seg := 7
	for i in seg:
		var a0 := PI * float(i) / float(seg)
		var a1 := PI * float(i + 1) / float(seg)
		var p0 := Vector3(cos(a0) * POST_X, 3.0 + sin(a0) * 0.55, 0)
		var p1 := Vector3(cos(a1) * POST_X, 3.0 + sin(a1) * 0.55, 0)
		var d := p1 - p0
		frame.add(NodeVisuals._box(Vector3(d.length() + 0.06, 0.2, 0.24)), Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), (p0 + p1) * 0.5), Palette.WOOD)
	var frame_mi := Props.instance(frame.commit(), wood, 140.0)
	add_child(frame_mi)
	var bunting := Props.instance(Props.garland(2.3, [Color("e9a15b"), Color("b48ad8"), Color("f3e6c8")]), trim, 90.0, false)
	bunting.position = Vector3(0, 2.8, 0.15)
	add_child(bunting)
	glass_material = StandardMaterial3D.new()
	glass_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass_material.albedo_color = Palette.STONE_DARK
	var glass := MeshInstance3D.new()
	glass.mesh = Props.lantern_glass()
	glass.material_override = glass_material
	glass.position = Vector3(0, 2.95, 0.05)
	glass.scale = Vector3.ONE * 1.4
	add_child(glass)
	var body := StaticBody3D.new()
	body.name = "Posts"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	add_child(body)
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.2
		cyl.height = 3.0
		cs.shape = cyl
		cs.position = Vector3(float(sx) * POST_X, 1.5, 0)
		body.add_child(cs)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.5
	ics.shape = sph
	ics.position = Vector3(0, 1.2, 0)
	ib.add_child(ics)
	add_child(ib)
	light = OmniLight3D.new()
	light.light_color = GLOW
	light.omni_range = 6.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position = Vector3(0, 2.7, 0.4)
	add_child(light)


func _apply_lit(on: bool) -> void:
	if glass_material != null:
		glass_material.albedo_color = Color(1.6, 1.15, 0.6) if on else Palette.STONE_DARK
	if light != null:
		light.light_energy = 1.1 if on else 0.0
		light.visible = on
	set_process(on)


func _process(delta: float) -> void:
	_t += delta
	if light == null:
		return
	if bool(Settings.get_value("reduce_flashing")):
		light.light_energy = 1.1       # comfort: a steady flame
	else:
		light.light_energy = 1.1 * (1.0 + sin(_t * 5.3) * 0.04 + sin(_t * 9.1 + 0.4) * 0.03)

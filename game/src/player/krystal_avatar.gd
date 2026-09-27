extends Node3D
## Krystal: an original stylised explorer (chibi-leaning, ~1.55 m, big head) built from Kit primitives
## with toon materials, outlines and fully procedural animation.
## The model faces +Z in its own space (the player rotates this node to its facing).
## Driven every frame by the player controller (speed, grounded, swing/roll phases ...), or standalone
## on the preview stage through play_anim(name):
##   idle, walk, run, jump, roll, axe, pickaxe, sword, hands, gather, lantern, lantern_walk,
##   wave, cheer, flinch, sleep, eat, hurt, death
## Right hand = -X side (tools), left hand = +X side (lantern).

signal footstep(foot: int)          # 0 = left, 1 = right; emitted at each foot plant while walking

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const OUTLINE := 0.011
## Render layer (12) used by Krystal's meshes: her own lantern ignores it as a shadow caster so her body
## never blacks out half of the light pool; the sun and every other light still shadow her normally.
const AVATAR_LAYER := 1 << 11
const FILL := 0.07
const FILL_TINT := Color(0.42, 0.34, 0.32)   # dim warm tint: same fill magnitude as the per-part albedo fill
const EYE_DARK := Color("2e2233")
const EYE_WARM := Color("7a4632")
const BLUSH := Color("f4a0ab")
const MOUTH := Color("8f3e4f")
const HAIR_DARK := Color("5e2c22")
const HAIR_LIGHT := Color("94503a")
const JACKET_DARK := Color("2e8781")
const SCARF_DARK := Color("d9a53a")
const BOOT_LIGHT := Color("8a5a36")
const BRASS := Color("e0b85a")
const LEATHER := Color("6e4a33")

# Pose channel indices (PackedVector3Array) -------------------------------------------------------
const J_LEG_L := 0
const J_LEG_R := 1
const J_KNEE_L := 2
const J_KNEE_R := 3
const J_SH_L := 4
const J_SH_R := 5
const J_EL_L := 6
const J_EL_R := 7
const J_HIPS := 8
const J_SPINE := 9
const J_HEAD := 10
const J_HAND_L := 11
const J_HAND_R := 12
const J_COUNT := 13

## Swing keyframes per kind. "t" = normalized swing time; the strike lands at ~0.44 (see player_logic).
## Channels: right shoulder x/y/z, right elbow x, spine lean x / twist y, left shoulder x, left elbow x,
## knee bend, body height offset, head pitch.
const SWING_KEYS := {
	"axe": {"t": [0.0, 0.34, 0.46, 0.62, 1.0],
		"sh_x": [0.0, -2.95, -1.0, -0.8, 0.0], "sh_y": [0.0, -0.15, 0.1, 0.05, 0.0], "sh_z": [-0.1, -0.2, -0.05, -0.1, -0.1],
		"el_x": [-0.15, -1.25, -0.2, -0.3, -0.15], "sp_x": [0.0, -0.15, 0.28, 0.2, 0.0], "sp_y": [0.0, -0.32, 0.24, 0.16, 0.0],
		"lsh_x": [0.0, -0.9, 0.35, 0.2, 0.0], "lel_x": [-0.15, -0.9, -0.3, -0.25, -0.15],
		"knee": [0.05, 0.12, 0.38, 0.3, 0.05], "body_y": [0.0, 0.02, -0.06, -0.05, 0.0], "head_x": [0.0, -0.14, 0.14, 0.08, 0.0]},
	"pickaxe": {"t": [0.0, 0.34, 0.46, 0.62, 1.0],
		"sh_x": [0.0, -3.0, -0.75, -0.6, 0.0], "sh_y": [0.0, -0.1, 0.1, 0.05, 0.0], "sh_z": [-0.1, -0.2, -0.05, -0.1, -0.1],
		"el_x": [-0.15, -1.3, -0.15, -0.3, -0.15], "sp_x": [0.0, -0.16, 0.4, 0.3, 0.0], "sp_y": [0.0, -0.3, 0.2, 0.12, 0.0],
		"lsh_x": [0.0, -0.95, 0.3, 0.2, 0.0], "lel_x": [-0.15, -0.9, -0.3, -0.25, -0.15],
		"knee": [0.05, 0.14, 0.5, 0.4, 0.05], "body_y": [0.0, 0.02, -0.09, -0.07, 0.0], "head_x": [0.0, -0.12, 0.2, 0.12, 0.0]},
	"sword": {"t": [0.0, 0.34, 0.46, 0.62, 1.0],
		"sh_x": [0.0, -1.35, -1.45, -1.2, 0.0], "sh_y": [0.0, -1.05, 0.95, 1.0, 0.0], "sh_z": [-0.1, -0.3, -0.1, -0.1, -0.1],
		"el_x": [-0.15, -0.95, -0.1, -0.25, -0.15], "sp_x": [0.0, -0.05, 0.12, 0.08, 0.0], "sp_y": [0.0, -0.45, 0.42, 0.35, 0.0],
		"lsh_x": [0.0, 0.3, -0.45, -0.3, 0.0], "lel_x": [-0.15, -0.5, -0.6, -0.5, -0.15],
		"knee": [0.05, 0.16, 0.32, 0.26, 0.05], "body_y": [0.0, 0.0, -0.04, -0.03, 0.0], "head_x": [0.0, 0.0, 0.06, 0.03, 0.0]},
	"hands": {"t": [0.0, 0.3, 0.44, 0.6, 1.0],
		"sh_x": [0.0, 0.35, -1.55, -1.4, 0.0], "sh_y": [0.0, 0.0, 0.1, 0.05, 0.0], "sh_z": [-0.1, -0.15, -0.05, -0.1, -0.1],
		"el_x": [-0.15, -1.8, -0.1, -0.3, -0.15], "sp_x": [0.0, -0.05, 0.15, 0.1, 0.0], "sp_y": [0.0, -0.35, 0.35, 0.25, 0.0],
		"lsh_x": [0.0, -0.9, 0.4, 0.3, 0.0], "lel_x": [-0.15, -1.6, -0.4, -0.3, -0.15],
		"knee": [0.05, 0.2, 0.3, 0.25, 0.05], "body_y": [0.0, -0.03, -0.05, -0.04, 0.0], "head_x": [0.0, 0.0, 0.0, 0.0, 0.0]},
	"gather": {"t": [0.0, 0.3, 0.46, 0.65, 1.0],
		"sh_x": [0.0, -0.5, -1.1, -1.0, 0.0], "sh_y": [0.0, 0.0, 0.1, 0.05, 0.0], "sh_z": [-0.1, -0.1, -0.05, -0.1, -0.1],
		"el_x": [-0.15, -0.6, -0.2, -0.4, -0.15], "sp_x": [0.0, 0.12, 0.45, 0.4, 0.0], "sp_y": [0.0, -0.1, 0.05, 0.0, 0.0],
		"lsh_x": [0.0, -0.3, -0.7, -0.6, 0.0], "lel_x": [-0.15, -0.5, -0.3, -0.35, -0.15],
		"knee": [0.05, 0.3, 0.7, 0.65, 0.05], "body_y": [0.0, -0.05, -0.14, -0.13, 0.0], "head_x": [0.0, 0.1, 0.3, 0.25, 0.0]},
}

## Roll: points on the head + hair silhouette (HeadCenter space) that must stay above the floor.
const ROLL_CLEARANCE := 0.02
const _HEAD_HULL := [Vector3(0, 0.33, -0.05), Vector3(0, -0.27, 0.0), Vector3(0, -0.3, -0.2), Vector3(0.28, 0.03, -0.03),
	Vector3(-0.28, 0.03, -0.03), Vector3(0, 0.03, 0.26), Vector3(0, 0.0, -0.33), Vector3(0, 0.24, 0.17), Vector3(0, 0.25, -0.26),
	Vector3(0, -0.2, 0.17), Vector3(0.2, 0.24, -0.05), Vector3(-0.2, 0.24, -0.05), Vector3(0.2, -0.2, -0.1), Vector3(-0.2, -0.2, -0.1)]

const ACTION_TIME := {"hurt": 0.42, "flinch": 0.9, "wave": 1.8, "cheer": 1.6, "eat": 1.1, "interact": 0.45, "sleep": -1.0, "death": -1.0, "tired": 0.8}

# --- Controller inputs (set by the player every frame) -------------------------------------------------
var driven: bool = false            # true when a controller feeds the fields below
var speed: float = 0.0
var grounded: bool = true
var vertical_speed: float = 0.0
var turn_rate: float = 0.0
var sprinting: bool = false
var swing_kind: String = ""
var swing_t: float = -1.0           # 0..1 while swinging, < 0 otherwise
var roll_t: float = -1.0            # 0..1 while rolling, < 0 otherwise
var lantern_on: bool = false
var lantern_owned: bool = false     # shows the lantern clipped to the satchel when it is not raised
var lantern_energy_scale: float = 1.0   # set by the player (dimmer in surface daylight)
var look_target: Vector3 = Vector3.ZERO
var has_look_target: bool = false

# --- Rig ------------------------------------------------------------------------------------------------
var _body_root: Node3D
var _roll: Node3D
var _body: Node3D
var _joints: Array[Node3D] = []
var _pose := PackedVector3Array()
var _body_off := Vector3.ZERO
var _head_c: Node3D
var _eyes: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth_smile: MeshInstance3D
var _mouth_open: MeshInstance3D
var _scarf_ends: Array = []          # [[seg0, seg1], [seg0, seg1]]
var _braid: Array[Node3D] = []
var _tools: Dictionary = {}           # kind -> Node3D (in the right hand)
var _tool_anchor: Node3D
var _lantern: Node3D
var _lantern_belt: Node3D
var _lantern_light: OmniLight3D
var _food: MeshInstance3D

# --- Animation state -----------------------------------------------------------------------------------
var _t: float = 0.0
var _phase: float = 0.0
var _move_w: float = 0.0
var _run_w: float = 0.0
var _air_w: float = 0.0
var _lantern_w: float = 0.0
var _swing_w: float = 0.0
var _last_swing_kind: String = "hands"
var _last_swing_t: float = 1.0
var _tool_timer: float = 0.0
var _shown_tool: String = ""
var _sq: float = 0.0
var _sq_v: float = 0.0
var _blink_timer: float = 2.0
var _blink_t: float = -1.0
var _idle_look_timer: float = 6.0
var _idle_look := Vector2.ZERO
var _idle_look_hold: float = 0.0
var _head_look := Vector2.ZERO
var _action: String = ""
var _action_t: float = 0.0
var _action_w: float = 0.0
var _prev_gpos := Vector3.ZERO
var _prev_lv := Vector3.ZERO
var _has_prev: bool = false
var _scarf_ang: Array = [Vector2.ZERO, Vector2.ZERO]
var _scarf_vel: Array = [Vector2.ZERO, Vector2.ZERO]
var _braid_ang := Vector2.ZERO
var _braid_vel := Vector2.ZERO
var _lant_ang := Vector2.ZERO
var _lant_vel := Vector2.ZERO
var _roll_blend: float = 0.0
var _demo: String = ""
var _demo_t: float = 0.0
var _eyes_closed: float = 0.0
var _mouth_amt: float = 0.0
var _brow_worry: float = 0.0
var _visible_body: bool = true
var _lant_scale: float = 1.0

static var _arc_cache: Dictionary = {}
static var _bake_cache: Dictionary = {}     # "node path|material class" -> merged ArrayMesh (shared by all avatars)


func _ready() -> void:
	_pose.resize(J_COUNT)
	_build()
	_blink_timer = randf_range(1.5, 4.0)


# =====================================================================================================
# Public API
# =====================================================================================================

## Plays a one-shot or looping action: hurt, flinch, wave, cheer, eat, interact, sleep, death, tired.
## Also accepts "jump" / "land" (squash & stretch only).
func play_action(action_name: String, strength: float = 1.0) -> void:
	match action_name:
		"jump":
			_sq_v += 2.6
			return
		"land":
			_sq_v -= clampf(strength, 0.6, 3.4)
			return
		"hurt":
			if _action == "death":
				return
	if not ACTION_TIME.has(action_name):
		return
	_action = action_name
	_action_t = 0.0
	if action_name == "eat" and _food != null:
		_food.visible = true
		_food.scale = Vector3.ONE


## Alias used by the player contract (play_emote).
func play_emote(emote_name: String) -> void:
	play_action(emote_name)


## Ends a looping/ongoing action (sleep, wave...) - e.g. when the player starts moving.
func cancel_action(include_death: bool = false) -> void:
	if _action == "death" and not include_death:
		return
	_action = ""
	if _food != null:
		_food.visible = false


func current_action() -> String:
	return _action


## Tints the food morsel shown while eating.
func set_food_color(c: Color) -> void:
	if _food != null:
		_food.material_override = Mat.outlined(Mat.toon(c, {"rim": 0.5}), 0.006)


## Shows the tool for a swing kind ("axe", "pickaxe", "sword"; anything else = empty hands).
func show_tool(kind: String, seconds: float = 0.9) -> void:
	_shown_tool = kind if _tools.has(kind) else ""
	_tool_timer = seconds
	for k in _tools:
		(_tools[k] as Node3D).visible = (k == _shown_tool)


func set_body_visible(v: bool) -> void:
	_visible_body = v
	if _body_root != null:
		_body_root.visible = v


## Resets the pose and motion history (teleports, respawn).
func reset_motion() -> void:
	_has_prev = false
	_prev_lv = Vector3.ZERO
	for i in 2:
		_scarf_ang[i] = Vector2.ZERO
		_scarf_vel[i] = Vector2.ZERO
	_braid_ang = Vector2.ZERO
	_braid_vel = Vector2.ZERO
	_lant_ang = Vector2.ZERO
	_lant_vel = Vector2.ZERO
	_sq = 0.0
	_sq_v = 0.0


## World position of the lantern flame (for lights / effects).
func lantern_world_position() -> Vector3:
	if _lantern != null and _lantern.is_inside_tree():
		return _lantern.global_position + _lantern.global_basis.y * 0.09
	return global_position + Vector3.UP * 0.9


func get_lantern_light() -> OmniLight3D:
	return _lantern_light


## Preview-stage entry point (standalone animation without a controller).
func play_anim(anim_name: String) -> void:
	_demo = anim_name
	_demo_t = 0.0
	driven = false
	speed = 0.0
	sprinting = false
	grounded = true
	lantern_on = false
	lantern_owned = true
	match anim_name:
		"walk":
			speed = 4.2
		"run":
			speed = 7.0
			sprinting = true
		"lantern":
			lantern_on = true
		"lantern_walk":
			lantern_on = true
			speed = 4.2
		"wave", "cheer", "flinch", "sleep", "eat", "hurt", "death", "tired":
			play_action(anim_name)


# =====================================================================================================
# Building the model
# =====================================================================================================

## Toon material for Krystal. A faint self-fill (emission ~7% of the albedo) keeps her readable in the
## darkest places (the Below at night) without lighting the world around her.
func _m(c: Color, outline: bool = true, thick: float = OUTLINE) -> Material:
	var base := Mat.toon(c, {"rim": 0.42, "noise": 0.04, "emission": c, "emission_energy": FILL})
	return Mat.outlined(base, thick) if outline else base


func _flat(c: Color) -> Material:
	return Mat.toon(c, {"rim": 0.0, "noise": 0.0, "emission": c, "emission_energy": FILL})


func _node(parent: Node3D, pos: Vector3, nm: String = "") -> Node3D:
	var n := Node3D.new()
	if nm != "":
		n.name = nm
	parent.add_child(n)
	n.position = pos
	return n


func _part(parent: Node3D, mi: MeshInstance3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	Kit.add(parent, mi, pos, rot_deg, scl)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build() -> void:
	_body_root = _node(self, Vector3.ZERO, "Body")
	_roll = _node(_body_root, Vector3(0, 0.5, 0), "RollPivot")
	_body = _node(_roll, Vector3(0, -0.5, 0), "Rig")
	_joints.resize(J_COUNT)
	var hips := _node(_body, Vector3(0, 0.6, 0), "Hips")
	_joints[J_HIPS] = hips
	# Pelvis (plum trousers)
	_part(hips, Kit.sphere(0.155, _m(Palette.K_PANTS)), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.08, 0.72, 0.92))
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		_build_leg(hips, side, s)
	var spine := _node(hips, Vector3(0, 0.02, 0), "Spine")
	_joints[J_SPINE] = spine
	_build_torso(spine)
	var chest := _node(spine, Vector3(0, 0.36, 0), "Chest")
	_build_scarf(chest)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		_build_arm(chest, side, s)
	var head := _node(chest, Vector3(0, 0.04, 0), "Head")
	_joints[J_HEAD] = head
	_head_c = _node(head, Vector3(0, 0.23, 0.0), "HeadCenter")
	_build_head(_head_c)
	# Lantern light lives outside the body so hiding the body (camera very close) keeps the light.
	_lantern_light = OmniLight3D.new()
	_lantern_light.name = "LanternLight"
	_lantern_light.light_color = Palette.LANTERN_GLOW
	_lantern_light.light_energy = 1.25
	_lantern_light.omni_range = 7.0
	_lantern_light.omni_attenuation = 1.5
	_lantern_light.shadow_enabled = true
	_lantern_light.shadow_bias = 0.08
	_lantern_light.light_specular = 0.25
	_lantern_light.shadow_caster_mask = 0xFFFFFFFF & ~AVATAR_LAYER
	_lantern_light.visible = false
	add_child(_lantern_light)
	_bake_tree(_body_root, _body_root)
	_set_layers(_body_root)


# --- Draw-call baking -------------------------------------------------------------------------------------
# The rig is authored as ~120 primitive parts for readability. Parts that never move relative to their
# joint are merged per joint and material class into one vertex-coloured mesh (~190 -> ~70 draw calls).
# Animated / toggled pieces (eyes blink as a node, mouth shapes, food, glows) stay separate.

func _bake_tree(n: Node, root: Node) -> void:
	for c in n.get_children():
		_bake_tree(c, root)
	if n is Node3D:
		_bake_children(n as Node3D, root)


func _bake_children(n: Node3D, root: Node) -> void:
	var groups: Dictionary = {}
	for c in n.get_children():
		if not (c is MeshInstance3D) or c == _mouth_smile or c == _mouth_open or c == _food:
			continue
		var mi := c as MeshInstance3D
		if not mi.visible or mi.get_child_count() > 0 or mi.mesh == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat == null or mat.shader != Mat.TOON:
			continue
		var thick := 0.0
		if mat.next_pass is ShaderMaterial:
			thick = float((mat.next_pass as ShaderMaterial).get_shader_parameter("thickness"))
		var rim := float(mat.get_shader_parameter("rim_strength"))
		var noise := float(mat.get_shader_parameter("noise_amount"))
		var spec_v: Variant = mat.get_shader_parameter("specular_amount")
		var spec := float(spec_v) if spec_v != null else 0.0
		var key := "%.3f|%.2f|%.2f|%.2f|%d" % [thick, rim, noise, spec, mi.cast_shadow]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(mi)
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var first := list[0] as MeshInstance3D
		var fmat := first.material_override as ShaderMaterial
		var cache_key := "%s|%s" % [str(root.get_path_to(n)), key]
		var mesh: ArrayMesh = _bake_cache.get(cache_key)
		if mesh == null:
			mesh = _merge_parts(list)
			_bake_cache[cache_key] = mesh
		var opts := {"rim": float(fmat.get_shader_parameter("rim_strength")), "noise": float(fmat.get_shader_parameter("noise_amount")),
			"vertex_color": true, "emission": FILL_TINT, "emission_energy": FILL}
		var spec_v2: Variant = fmat.get_shader_parameter("specular_amount")
		if spec_v2 != null and float(spec_v2) > 0.0:
			opts["specular"] = float(spec_v2)
		var base := Mat.toon(Color.WHITE, opts)
		var mat: Material = base
		if fmat.next_pass is ShaderMaterial:
			mat = Mat.outlined(base, float((fmat.next_pass as ShaderMaterial).get_shader_parameter("thickness")))
		var merged := MeshInstance3D.new()
		merged.name = "Baked"
		merged.mesh = mesh
		merged.material_override = mat
		merged.cast_shadow = first.cast_shadow
		n.add_child(merged)
		for mi in list:
			n.remove_child(mi)
			(mi as Node).free()


## Merges parts (transforms relative to their shared parent) into one mesh; each part's albedo becomes
## its vertex colour (converted to linear because the toon shader multiplies raw COLOR).
static func _merge_parts(list: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for item in list:
		var mi := item as MeshInstance3D
		var xf := mi.transform
		var nb := xf.basis.inverse().transposed()
		var c: Color = (mi.material_override as ShaderMaterial).get_shader_parameter("albedo")
		var lc := c.srgb_to_linear()
		for sidx in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(sidx)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ii: Variant = arr[Mesh.ARRAY_INDEX]
			var start := verts.size()
			for k in v.size():
				verts.append(xf * v[k])
				norms.append((nb * nn[k]).normalized() if k < nn.size() else Vector3.UP)
				cols.append(lc)
			if ii is PackedInt32Array and not (ii as PackedInt32Array).is_empty():
				for k in (ii as PackedInt32Array):
					idx.append(start + k)
			else:
				for k in v.size():
					idx.append(start + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = AVATAR_LAYER
	for c in n.get_children():
		_set_layers(c)


func _build_leg(hips: Node3D, side: int, s: float) -> void:
	var leg := _node(hips, Vector3(0.092 * s, -0.005, 0), "Leg%d" % side)
	_joints[J_LEG_L + side] = leg
	_part(leg, Kit.capsule(0.078, 0.3, _m(Palette.K_PANTS)), Vector3(0, -0.12, 0))
	var knee := _node(leg, Vector3(0, -0.235, 0), "Knee%d" % side)
	_joints[J_KNEE_L + side] = knee
	_part(knee, Kit.capsule(0.066, 0.24, _m(Palette.K_PANTS)), Vector3(0, -0.08, 0))
	# Boot: shaft, cuff, rounded toe and a little sole
	_part(knee, Kit.cylinder(0.078, 0.084, 0.16, _m(Palette.K_BOOTS)), Vector3(0, -0.2, 0.0))
	_part(knee, Kit.torus(0.07, 0.094, _m(BOOT_LIGHT)), Vector3(0, -0.125, 0), Vector3.ZERO, Vector3(1, 1.3, 1))
	_part(knee, Kit.sphere(0.088, _m(Palette.K_BOOTS)), Vector3(0, -0.29, 0.04), Vector3.ZERO, Vector3(0.98, 0.64, 1.42))
	_part(knee, Kit.cylinder(0.082, 0.082, 0.024, _m(LEATHER, true, 0.006), 16), Vector3(0, -0.338, 0.042), Vector3.ZERO, Vector3(1.0, 1.0, 1.42), false)


func _build_torso(spine: Node3D) -> void:
	var jacket := _m(Palette.K_JACKET)
	# Jacket body (slightly flattened front-to-back) and an A-line hem
	_part(spine, Kit.capsule(0.168, 0.5, jacket), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.84))
	_part(spine, Kit.cylinder(0.165, 0.205, 0.15, jacket), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.88))
	# Cream shirt: a soft V showing at the open front of the jacket
	_part(spine, Kit.prism(Vector3(0.13, 0.15, 0.03), _m(Palette.K_SHIRT, false)), Vector3(0, 0.335, 0.122), Vector3(-14, 0, 180), Vector3.ONE, false)
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		# Brass buttons along the jacket edge and rounded pocket flaps on the hem
		_part(spine, Kit.sphere(0.013, _flat(BRASS), 8, 12), Vector3(0.062 * s, 0.24, 0.139), Vector3.ZERO, Vector3.ONE, false)
		_part(spine, Kit.sphere(0.013, _flat(BRASS), 8, 12), Vector3(0.062 * s, 0.15, 0.144), Vector3.ZERO, Vector3.ONE, false)
		_part(spine, Kit.sphere(0.045, _m(JACKET_DARK, false)), Vector3(0.1 * s, 0.05, 0.158), Vector3(0, 22 * s, 0), Vector3(1.0, 0.42, 0.28), false)
	# Back: an embroidered explorer patch (cream disc with a little green sprout) - seen from the camera
	var patch := _node(spine, Vector3(0, 0.25, -0.142), "Patch")
	patch.rotation_degrees = Vector3(-8, 180, 0)
	_part(patch, Kit.cylinder(0.052, 0.052, 0.012, _m(Palette.K_SHIRT, true, 0.005), 20), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
	_part(patch, Kit.capsule(0.006, 0.05, _flat(Palette.FOLIAGE_DARK)), Vector3(0, -0.008, 0.009), Vector3.ZERO, Vector3.ONE, false)
	_part(patch, Kit.sphere(0.017, _flat(Palette.FOLIAGE), 8, 10), Vector3(-0.014, 0.014, 0.01), Vector3(0, 0, 35), Vector3(1.4, 0.7, 0.4), false)
	_part(patch, Kit.sphere(0.015, _flat(Palette.FOLIAGE_LIGHT), 8, 10), Vector3(0.013, 0.02, 0.01), Vector3(0, 0, -35), Vector3(1.4, 0.7, 0.4), false)
	# Satchel strap across the chest (right shoulder -> left hip) and the satchel on the left hip
	_part(spine, Kit.torus(0.17, 0.2, _m(Palette.K_BAG)), Vector3(0.03, 0.2, 0), Vector3(0, 0, -57), Vector3(1.42, 0.9, 0.78))
	var bag := _node(spine, Vector3(0.2, 0.0, -0.07), "Satchel")
	bag.rotation_degrees = Vector3(0, 115, -5)
	_part(bag, Kit.capsule(0.07, 0.21, _m(Palette.K_BAG)), Vector3.ZERO, Vector3(0, 0, 90), Vector3(1.05, 1.0, 0.62))
	_part(bag, Kit.sphere(0.1, _m(LEATHER)), Vector3(0, 0.03, 0.02), Vector3.ZERO, Vector3(1.05, 0.55, 0.52))
	_part(bag, Kit.sphere(0.017, _flat(BRASS), 8, 12), Vector3(0, 0.0, 0.07), Vector3.ZERO, Vector3.ONE, false)
	# Lantern clipped to the satchel strap while it is not raised
	_lantern_belt = _node(bag, Vector3(0.07, 0.04, 0.07), "BeltLantern")
	_build_lantern_mesh(_lantern_belt, false)
	_lantern_belt.scale = Vector3.ONE * 0.8
	_lantern_belt.visible = false


func _build_scarf(chest: Node3D) -> void:
	var scarf := _m(Palette.K_SCARF)
	_part(chest, Kit.torus(0.085, 0.16, scarf), Vector3(0, 0.02, 0), Vector3(4, 0, 0), Vector3(1.0, 1.55, 0.94))
	_part(chest, Kit.torus(0.08, 0.14, scarf), Vector3(0, 0.075, -0.01), Vector3(-6, 0, 0), Vector3(0.96, 1.3, 0.9))
	# Knot at the back-left and two ends that flutter
	_part(chest, Kit.sphere(0.05, scarf), Vector3(0.075, 0.03, -0.128), Vector3.ZERO, Vector3(1.1, 0.85, 0.8))
	_scarf_ends.clear()
	for i in 2:
		var root := _node(chest, Vector3(0.06 + 0.035 * i, 0.02, -0.15), "ScarfEnd%d" % i)
		root.rotation = Vector3(0.25, 0, 0.22 - 0.4 * i)
		_part(root, Kit.capsule(0.03, 0.16, scarf), Vector3(0, -0.07, 0), Vector3.ZERO, Vector3(1.2, 1.0, 0.55))
		var seg := _node(root, Vector3(0, -0.13, 0), "Tip")
		_part(seg, Kit.capsule(0.03, 0.15 - 0.035 * i, scarf), Vector3(0, -0.055, 0), Vector3(0, 0, 6 - 12 * i), Vector3(1.3, 1.0, 0.5))
		_part(seg, Kit.box(Vector3(0.074, 0.016, 0.034), _m(SCARF_DARK, false)), Vector3(0, -0.09 + 0.02 * i, 0), Vector3(0, 0, 6 - 12 * i), Vector3.ONE, false)
		_scarf_ends.append([root, seg])


func _build_arm(chest: Node3D, side: int, s: float) -> void:
	var sh := _node(chest, Vector3(0.195 * s, -0.02, 0.0), "Shoulder%d" % side)
	_joints[J_SH_L + side] = sh
	var jacket := _m(Palette.K_JACKET)
	_part(sh, Kit.sphere(0.072, jacket), Vector3(0, -0.01, 0))
	_part(sh, Kit.capsule(0.06, 0.23, jacket), Vector3(0, -0.1, 0))
	var el := _node(sh, Vector3(0, -0.195, 0), "Elbow%d" % side)
	_joints[J_EL_L + side] = el
	_part(el, Kit.capsule(0.054, 0.2, jacket), Vector3(0, -0.075, 0))
	_part(el, Kit.torus(0.042, 0.066, _m(JACKET_DARK)), Vector3(0, -0.16, 0), Vector3.ZERO, Vector3(1, 1.4, 1))
	var hand := _node(el, Vector3(0, -0.2, 0), "Hand%d" % side)
	_joints[J_HAND_L + side] = hand
	_part(hand, Kit.sphere(0.056, _m(Palette.K_SKIN)), Vector3(0, -0.012, 0.004), Vector3.ZERO, Vector3(0.9, 1.0, 1.0))
	_part(hand, Kit.sphere(0.022, _m(Palette.K_SKIN)), Vector3(-0.045 * s, 0.0, 0.03), Vector3.ZERO, Vector3(1, 1.3, 1))   # thumb
	if side == 1:
		_tool_anchor = _node(hand, Vector3(0, -0.02, 0.0), "ToolAnchor")
		_build_tools(_tool_anchor)
		_food = Kit.sphere(0.035, _m(Palette.BERRY), 10, 14)
		_part(hand, _food, Vector3(0.01, -0.03, 0.06), Vector3.ZERO, Vector3.ONE, false)
		_food.visible = false
	else:
		_lantern = _node(hand, Vector3(0, -0.04, 0.0), "Lantern")
		_build_lantern_mesh(_lantern, true)
		_lantern.visible = false


func _build_tools(anchor: Node3D) -> void:
	var handle := _m(Palette.WOOD)
	var stone := _m(Palette.STONE)
	var fiber := _m(Palette.MEADOW_GOLD)
	# Stone axe: handle along +Y, lumpy stone head lashed with fiber, edge towards +Z.
	var axe := _node(anchor, Vector3.ZERO, "Axe")
	axe.rotation = Vector3(2.3, 0, 0)
	_part(axe, Kit.cylinder(0.02, 0.024, 0.5, handle, 10), Vector3(0, 0.2, 0))
	_part(axe, Kit.blob(0.07, stone, 11, 0.22, 1.0, 2), Vector3(0, 0.4, 0.055), Vector3.ZERO, Vector3(0.55, 1.05, 1.35))
	_part(axe, Kit.torus(0.02, 0.036, fiber), Vector3(0, 0.4, 0.0), Vector3(0, 0, 0), Vector3(1, 1.6, 1))
	# Stone pickaxe: curved head across the top, point towards +Z.
	var pick := _node(anchor, Vector3.ZERO, "Pickaxe")
	pick.rotation = Vector3(2.3, 0, 0)
	_part(pick, Kit.cylinder(0.02, 0.024, 0.52, handle, 10), Vector3(0, 0.21, 0))
	_part(pick, Kit.cone(0.035, 0.17, stone, 10), Vector3(0, 0.44, 0.08), Vector3(80, 0, 0))
	_part(pick, Kit.cone(0.032, 0.13, stone, 10), Vector3(0, 0.44, -0.06), Vector3(-100, 0, 0))
	_part(pick, Kit.sphere(0.045, stone), Vector3(0, 0.44, 0.0))
	_part(pick, Kit.torus(0.02, 0.034, fiber), Vector3(0, 0.41, 0.0), Vector3.ZERO, Vector3(1, 1.4, 1))
	# Copper sword: extends along the arm (blade -Y-ish), bright copper with a leather grip.
	var sword := _node(anchor, Vector3.ZERO, "Sword")
	sword.rotation = Vector3(2.75, 0, 0)
	var copper := Mat.outlined(Mat.toon(Palette.COPPER, {"rim": 0.8, "specular": 0.6, "noise": 0.02}), OUTLINE)
	_part(sword, Kit.cylinder(0.018, 0.018, 0.1, _m(LEATHER), 8), Vector3(0, 0.0, 0))
	_part(sword, Kit.sphere(0.026, _m(BRASS)), Vector3(0, -0.06, 0))
	_part(sword, Kit.box(Vector3(0.15, 0.03, 0.04), _m(BRASS)), Vector3(0, 0.06, 0))
	_part(sword, Kit.box(Vector3(0.078, 0.46, 0.02), copper), Vector3(0, 0.3, 0))
	_part(sword, Kit.prism(Vector3(0.078, 0.09, 0.02), copper), Vector3(0, 0.575, 0))
	_part(sword, Kit.box(Vector3(0.016, 0.42, 0.022), _flat(Color("f7cf9c"))), Vector3(0, 0.29, 0), Vector3.ZERO, Vector3.ONE, false)
	_tools = {"axe": axe, "pickaxe": pick, "sword": sword}
	for k in _tools:
		(_tools[k] as Node3D).visible = false


func _build_lantern_mesh(root: Node3D, lit: bool) -> void:
	var frame := _m(Palette.MINE_TIMBER, true, 0.008)
	var brass := _m(BRASS, true, 0.008)
	var glass: Material = Mat.glow(Palette.LANTERN_GLOW, 2.2) if lit else _m(Color("e8d9b0"), true, 0.008)
	# Hangs below the hand: handle ring at the top, roof, glass, base.
	var parts: Array[MeshInstance3D] = []
	parts.append(_part(root, Kit.torus(0.022, 0.034, brass), Vector3(0, 0.0, 0), Vector3(90, 0, 0)))
	parts.append(_part(root, Kit.cone(0.07, 0.06, frame, 12), Vector3(0, -0.055, 0)))
	parts.append(_part(root, Kit.cylinder(0.05, 0.055, 0.1, glass, 12), Vector3(0, -0.13, 0)))
	parts.append(_part(root, Kit.cylinder(0.066, 0.066, 0.025, frame, 12), Vector3(0, -0.19, 0)))
	parts.append(_part(root, Kit.sphere(0.018, brass, 8, 10), Vector3(0, -0.02, 0)))
	for p in parts:
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_head(hc: Node3D) -> void:
	var skin := _m(Palette.K_SKIN, true, 0.012)
	var hair := _m(Palette.K_HAIR, true, 0.012)
	_part(hc, Kit.sphere(0.25, skin, 24, 32), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.94, 0.95))
	# --- Face (front = +Z) ---
	_eyes.clear()
	_brows.clear()
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var eye := _node(hc, Vector3(0.087 * s, -0.022, 0.206), "Eye%d" % side)
		eye.rotation = Vector3(0, deg_to_rad(21.0 * s), 0)
		_part(eye, Kit.sphere(0.047, _flat(EYE_DARK), 12, 18), Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 1.13, 0.46), false)
		_part(eye, Kit.sphere(0.03, _flat(EYE_WARM), 10, 14), Vector3(0, -0.02, 0.01), Vector3.ZERO, Vector3(0.85, 0.62, 0.5), false)
		_part(eye, Kit.sphere(0.0145, Mat.glow(Color.WHITE, 1.1), 8, 10), Vector3(0.012 * s, 0.02, 0.02), Vector3.ZERO, Vector3.ONE, false)
		_part(eye, Kit.sphere(0.0075, Mat.glow(Color.WHITE, 1.0), 6, 8), Vector3(-0.012 * s, -0.022, 0.019), Vector3.ZERO, Vector3.ONE, false)
		# A single cute lash flick at the outer corner
		_part(eye, Kit.capsule(0.007, 0.042, _flat(EYE_DARK)), Vector3(0.038 * s, 0.038, 0.0), Vector3(0, 0, -48.0 * s), Vector3.ONE, false)
		_eyes.append(eye)
		var brow := _node(hc, Vector3(0.088 * s, 0.062, 0.222), "Brow%d" % side)
		brow.rotation = Vector3(-0.2, deg_to_rad(20.0 * s), 0)
		_part(brow, Kit.capsule(0.0105, 0.068, _flat(HAIR_DARK)), Vector3.ZERO, Vector3(0, 0, 90 - 8 * s), Vector3.ONE, false)
		_brows.append(brow)
		_part(hc, Kit.sphere(0.036, _flat(BLUSH), 10, 14), Vector3(0.138 * s, -0.085, 0.172), Vector3(0, 36 * s, 0), Vector3(1.35, 0.72, 0.4), false)
	_part(hc, Kit.sphere(0.017, _m(Palette.K_SKIN, false), 8, 12), Vector3(0, -0.068, 0.233), Vector3.ZERO, Vector3(1.1, 0.9, 0.8), false)
	_mouth_smile = MeshInstance3D.new()
	_mouth_smile.mesh = _arc_mesh(0.03, 0.0072, 1.9)
	_mouth_smile.material_override = _flat(MOUTH)
	_part(hc, _mouth_smile, Vector3(0, -0.118, 0.212), Vector3(-22, 0, 0), Vector3.ONE, false)
	_mouth_open = Kit.sphere(0.026, _flat(MOUTH), 10, 14)
	_part(hc, _mouth_open, Vector3(0, -0.118, 0.205), Vector3(-20, 0, 0), Vector3(1.15, 0.85, 0.45), false)
	_mouth_open.visible = false
	# --- Hair: cap, back volume, side-swept fringe, face-framing locks, braid and a flower clip ---
	_part(hc, Kit.sphere(0.268, hair, 20, 28), Vector3(0, 0.052, -0.057), Vector3.ZERO, Vector3(1.05, 1.0, 1.0))
	_part(hc, Kit.sphere(0.21, hair, 16, 22), Vector3(0, -0.085, -0.12), Vector3.ZERO, Vector3(1.12, 1.0, 0.92))
	var fringe := [
		[Vector3(-0.125, 0.1, 0.188), Vector3(-12, -32, -18), Vector3(0.62, 1.35, 0.5), 0.07],
		[Vector3(-0.055, 0.118, 0.212), Vector3(-14, -12, -30), Vector3(0.7, 1.4, 0.48), 0.072],
		[Vector3(0.02, 0.13, 0.22), Vector3(-14, 6, -42), Vector3(0.72, 1.45, 0.46), 0.072],
		[Vector3(0.1, 0.13, 0.2), Vector3(-12, 28, -52), Vector3(0.7, 1.35, 0.48), 0.068],
		[Vector3(0.17, 0.09, 0.15), Vector3(-6, 48, -24), Vector3(0.62, 1.3, 0.55), 0.066],
	]
	for f in fringe:
		_part(hc, Kit.sphere(float(f[3]), hair, 12, 16), f[0], f[1], f[2])
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		_part(hc, Kit.capsule(0.056, 0.25, hair), Vector3(0.212 * s, -0.08, 0.075), Vector3(10, 0, 7 * s), Vector3(0.72, 1.0, 0.95))
		_part(hc, Kit.sphere(0.1, hair, 12, 16), Vector3(0.19 * s, -0.04, -0.03), Vector3.ZERO, Vector3(0.62, 1.15, 1.1))
	# Soft layered locks along the nape so the back of the head (the usual camera view) has shape
	for i in 5:
		var x := -0.13 + 0.065 * float(i)
		_part(hc, Kit.sphere(0.056, hair, 10, 14), Vector3(x, -0.255 + absf(x) * 0.3, -0.212 + absf(x) * 0.22), Vector3(-22, x * 110.0, x * 80.0), Vector3(0.95, 1.55, 0.72))
	# A single springy strand on top of the head
	var curl := MeshInstance3D.new()
	curl.mesh = _arc_mesh(0.045, 0.011, 3.6)
	curl.material_override = _m(Palette.K_HAIR, true, 0.006)
	_part(hc, curl, Vector3(0.025, 0.338, -0.03), Vector3(0, 60, 90), Vector3(1, 1.15, 1))
	# Side braid from behind the right ear, hanging over the back of the right shoulder.
	_braid.clear()
	var parent: Node3D = _node(hc, Vector3(-0.17, -0.1, -0.13), "Braid")
	parent.rotation = Vector3(0.35, 0.0, -0.18)
	var radii := [0.058, 0.054, 0.05, 0.046, 0.042, 0.038]
	for i in radii.size():
		var seg := _node(parent, Vector3(0, -0.065 if i > 0 else 0.0, 0), "B%d" % i)
		var r: float = radii[i]
		var off := 0.012 if i % 2 == 0 else -0.012
		_part(seg, Kit.sphere(r, hair, 10, 14), Vector3(off, -0.03, 0), Vector3(0, 0, 25.0 if i % 2 == 0 else -25.0), Vector3(0.9, 1.15, 0.9))
		_braid.append(seg)
		parent = seg
	var tie := _node(parent, Vector3(0, -0.075, 0), "Tie")
	_part(tie, Kit.torus(0.018, 0.034, _m(Palette.K_SCARF, true, 0.006)), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.6, 1))
	_part(tie, Kit.sphere(0.042, hair, 10, 14), Vector3(0, -0.05, 0), Vector3.ZERO, Vector3(1.0, 1.3, 0.85))
	_part(tie, Kit.sphere(0.03, hair, 8, 12), Vector3(0.012, -0.095, 0), Vector3(0, 0, 20), Vector3(0.8, 1.3, 0.75))
	# Flower clip on the left side of the head (five petals + honey centre)
	var clip := _node(hc, Vector3(0.2, 0.13, 0.1), "FlowerClip")
	clip.rotation_degrees = Vector3(-10, 55, 10)
	for i in 5:
		var a := TAU * float(i) / 5.0
		_part(clip, Kit.sphere(0.024, _m(Palette.FLOWER_WHITE, true, 0.005), 8, 10), Vector3(cos(a) * 0.026, sin(a) * 0.026, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.45), false)
	_part(clip, Kit.sphere(0.016, _m(Palette.FLOWER_YELLOW, false), 8, 10), Vector3(0, 0, 0.01), Vector3.ZERO, Vector3.ONE, false)


## Small smile: a tube bent into a U (cached ArrayMesh).
static func _arc_mesh(radius: float, tube: float, angle: float) -> ArrayMesh:
	var key := "%.4f|%.4f|%.3f" % [radius, tube, angle]
	if _arc_cache.has(key):
		return _arc_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var segs := 8
	var pts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in rings + 1:
		var a := -angle * 0.5 + angle * float(i) / float(rings)
		var c := Vector3(sin(a) * radius, radius - cos(a) * radius, 0.0)
		var n_in := Vector3(-sin(a), cos(a), 0.0)       # toward the arc centre
		for j in segs:
			var b := TAU * float(j) / float(segs)
			var n := n_in * cos(b) + Vector3(0, 0, 1) * sin(b)
			pts.append(c + n * tube)
			norms.append(n)
	for i in rings:
		for j in segs:
			var a0 := i * segs + j
			var a1 := i * segs + (j + 1) % segs
			var b0 := (i + 1) * segs + j
			var b1 := (i + 1) * segs + (j + 1) % segs
			for idx in [a0, b0, a1, a1, b0, b1]:
				st.set_normal(norms[idx])
				st.add_vertex(pts[idx])
	var mesh := st.commit()
	_arc_cache[key] = mesh
	return mesh


# =====================================================================================================
# Animation
# =====================================================================================================

func _process(delta: float) -> void:
	if _body == null:
		return
	var dt := minf(delta, 0.05)
	_t += dt
	if not driven:
		_run_demo(dt)
	_update_weights(dt)
	_reset_pose()
	_pose_locomotion(dt)
	_pose_air()
	_pose_lantern()
	_pose_swing(dt)
	_pose_action(dt)
	_pose_roll(dt)
	_apply_pose(dt)
	_keep_roll_above_ground()
	_update_face(dt)
	_update_secondary(dt)
	_update_props(dt)


func _update_weights(dt: float) -> void:
	var k := 1.0 - exp(-10.0 * dt)
	_move_w = lerpf(_move_w, clampf(speed / 4.2, 0.0, 1.0), k)
	_run_w = lerpf(_run_w, clampf((speed - 4.6) / 2.2, 0.0, 1.0), k)
	_air_w = lerpf(_air_w, 0.0 if grounded else 1.0, 1.0 - exp(-14.0 * dt))
	_lantern_w = lerpf(_lantern_w, 1.0 if lantern_on else 0.0, 1.0 - exp(-8.0 * dt))
	if swing_t >= 0.0:
		_swing_w = 1.0
		_last_swing_kind = swing_kind if SWING_KEYS.has(swing_kind) else "hands"
		_last_swing_t = swing_t
	else:
		_swing_w = move_toward(_swing_w, 0.0, dt * 8.0)
	# Squash & stretch spring
	_sq_v += (-_sq * 170.0 - _sq_v * 12.0) * dt
	_sq = clampf(_sq + _sq_v * dt, -0.28, 0.28)


func _reset_pose() -> void:
	for i in J_COUNT:
		_pose[i] = Vector3.ZERO
	_pose[J_SH_L] = Vector3(0.0, 0.0, 0.1)
	_pose[J_SH_R] = Vector3(0.0, 0.0, -0.1)
	_pose[J_EL_L] = Vector3(-0.15, 0.0, 0.0)
	_pose[J_EL_R] = Vector3(-0.15, 0.0, 0.0)
	_pose[J_KNEE_L] = Vector3(0.05, 0.0, 0.0)
	_pose[J_KNEE_R] = Vector3(0.05, 0.0, 0.0)
	_body_off = Vector3.ZERO


func _pose_locomotion(dt: float) -> void:
	var mw := _move_w
	var rw := _run_w
	# Walk cycle phase advances with distance travelled; footsteps at the plants.
	if speed > 0.05 and grounded and roll_t < 0.0:
		var cycle_len := lerpf(1.35, 2.05, rw)
		var prev := _phase
		_phase = fmod(_phase + dt * speed / cycle_len, 1.0)
		if speed > 0.6 and swing_t < 0.0:
			if prev < 0.25 and _phase >= 0.25:
				footstep.emit(0)
			elif prev < 0.75 and (_phase >= 0.75 or _phase < prev):
				footstep.emit(1)
	var cyc := _phase * TAU
	var sn := sin(cyc)
	var cs := cos(cyc)
	var leg_amp := lerpf(0.52, 0.9, rw) * mw
	var knee_amp := lerpf(0.55, 1.25, rw) * mw
	_pose[J_LEG_L].x += -sn * leg_amp
	_pose[J_LEG_R].x += sn * leg_amp
	_pose[J_KNEE_L].x += (maxf(0.0, cs) * knee_amp + 0.1 * mw)
	_pose[J_KNEE_R].x += (maxf(0.0, -cs) * knee_amp + 0.1 * mw)
	var arm_amp := lerpf(0.5, 0.95, rw) * mw
	_pose[J_SH_L].x += sn * arm_amp
	_pose[J_SH_R].x += -sn * arm_amp
	_pose[J_SH_L].z += 0.06 * mw
	_pose[J_SH_R].z -= 0.06 * mw
	_pose[J_EL_L].x += -(0.25 * mw + 0.95 * rw)
	_pose[J_EL_R].x += -(0.25 * mw + 0.95 * rw)
	_body_off.y += (absf(cs) - 0.6) * lerpf(0.035, 0.06, rw) * mw
	_pose[J_SPINE].x += 0.06 * mw + 0.16 * rw
	_pose[J_SPINE].y += sn * 0.12 * mw
	_pose[J_HIPS].y += -sn * 0.1 * mw
	_pose[J_HIPS].z += clampf(-turn_rate * 0.05, -0.22, 0.22) * mw
	_pose[J_HEAD].x += -0.05 * rw
	_pose[J_HEAD].y += -sn * 0.06 * mw
	# Idle: breathing, gentle sway and the odd curious look around.
	var iw := 1.0 - mw
	var br := sin(_t * 2.1)
	_body_off.y += br * 0.004 * iw
	_pose[J_SPINE].x += br * 0.015 * iw
	_pose[J_SH_L].z += (0.03 + br * 0.02) * iw
	_pose[J_SH_R].z -= (0.03 + br * 0.02) * iw
	_pose[J_HIPS].z += sin(_t * 0.55) * 0.025 * iw
	_pose[J_HEAD].z += sin(_t * 0.7 + 1.0) * 0.045 * iw
	_idle_look_timer -= dt
	if _idle_look_timer <= 0.0:
		_idle_look_timer = randf_range(5.0, 10.0)
		_idle_look = Vector2(randf_range(-0.14, 0.1), randf_range(-0.45, 0.45))
		_idle_look_hold = randf_range(1.2, 2.2)
	_idle_look_hold -= dt
	var want := Vector2.ZERO
	if _idle_look_hold > 0.0 and iw > 0.7:
		want = _idle_look
	if has_look_target and is_inside_tree():
		var local := global_transform.affine_inverse() * look_target
		var head_h := 1.25
		var flat := Vector2(local.x, local.z)
		if flat.length() > 0.3:
			var yaw := clampf(atan2(local.x, local.z), -0.7, 0.7)
			var pitch := clampf(atan2(local.y - head_h, flat.length()), -0.45, 0.3)
			want = Vector2(-pitch, yaw)
	_head_look = _head_look.lerp(want, 1.0 - exp(-5.0 * dt))
	_pose[J_HEAD].x += _head_look.x
	_pose[J_HEAD].y += _head_look.y
	_pose[J_SPINE].y += _head_look.y * 0.2


func _pose_air() -> void:
	var w := _air_w
	if w < 0.01:
		return
	var rising := clampf(vertical_speed / 4.0, -1.0, 1.0)
	var up := maxf(rising, 0.0)
	var down := maxf(-rising, 0.0)
	_pose[J_LEG_L] = _pose[J_LEG_L].lerp(Vector3(-0.55 * up - 0.1 * down, 0, 0.04), w)
	_pose[J_LEG_R] = _pose[J_LEG_R].lerp(Vector3(-0.1 * up + 0.12 * down, 0, -0.04), w)
	_pose[J_KNEE_L] = _pose[J_KNEE_L].lerp(Vector3(1.0 * up + 0.35 * down, 0, 0), w)
	_pose[J_KNEE_R] = _pose[J_KNEE_R].lerp(Vector3(0.45 * up + 0.3 * down, 0, 0), w)
	_pose[J_SH_L] = _pose[J_SH_L].lerp(Vector3(-0.4 * up - 0.2 * down, 0, 0.5 + 0.55 * down), w)
	_pose[J_SH_R] = _pose[J_SH_R].lerp(Vector3(0.3 * up - 0.2 * down, 0, -0.5 - 0.55 * down), w)
	_pose[J_EL_L] = _pose[J_EL_L].lerp(Vector3(-0.7, 0, 0), w)
	_pose[J_EL_R] = _pose[J_EL_R].lerp(Vector3(-0.7, 0, 0), w)
	_pose[J_SPINE].x += (0.06 * up - 0.05 * down) * w
	_pose[J_HEAD].x += (-0.1 * up + 0.08 * down) * w


func _pose_lantern() -> void:
	var w := _lantern_w
	if w < 0.01:
		return
	# Left arm holds the lantern forward at hip height; walking swings it only a little.
	var cur: Vector3 = _pose[J_SH_L]
	_pose[J_SH_L] = cur.lerp(Vector3(-0.5 + cur.x * 0.25, 0.1, 0.18), w)
	_pose[J_EL_L] = _pose[J_EL_L].lerp(Vector3(-0.85, 0, 0), w)


func _sample(keys: Array, times: Array, t: float) -> float:
	var n := times.size()
	if t <= float(times[0]):
		return float(keys[0])
	for i in range(1, n):
		var t1 := float(times[i])
		if t <= t1:
			var t0 := float(times[i - 1])
			var u := (t - t0) / maxf(t1 - t0, 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(float(keys[i - 1]), float(keys[i]), u)
	return float(keys[n - 1])


func _pose_swing(dt: float) -> void:
	if _tool_timer > 0.0:
		_tool_timer -= dt
		if _tool_timer <= 0.0:
			show_tool("", 0.0)
	var w := _swing_w
	if w < 0.01:
		return
	var d: Dictionary = SWING_KEYS[_last_swing_kind]
	var times: Array = d["t"]
	var t := _last_swing_t
	var shr := Vector3(_sample(d["sh_x"], times, t), _sample(d["sh_y"], times, t), _sample(d["sh_z"], times, t))
	_pose[J_SH_R] = _pose[J_SH_R].lerp(shr, w)
	_pose[J_EL_R] = _pose[J_EL_R].lerp(Vector3(_sample(d["el_x"], times, t), 0, 0), w)
	if _lantern_w < 0.5:
		_pose[J_SH_L] = _pose[J_SH_L].lerp(Vector3(_sample(d["lsh_x"], times, t), 0, 0.12), w)
		_pose[J_EL_L] = _pose[J_EL_L].lerp(Vector3(_sample(d["lel_x"], times, t), 0, 0), w)
	var sp: Vector3 = _pose[J_SPINE]
	_pose[J_SPINE] = Vector3(lerpf(sp.x, _sample(d["sp_x"], times, t), w), lerpf(sp.y, _sample(d["sp_y"], times, t), w), sp.z)
	var knee := _sample(d["knee"], times, t)
	var planted := (1.0 - _move_w * 0.7) * w
	_pose[J_KNEE_L].x = lerpf(_pose[J_KNEE_L].x, knee, planted)
	_pose[J_KNEE_R].x = lerpf(_pose[J_KNEE_R].x, knee * 0.8, planted)
	# Step into the swing: lead foot forward, back foot behind.
	_pose[J_LEG_L].x = lerpf(_pose[J_LEG_L].x, -knee * 0.55, planted)
	_pose[J_LEG_R].x = lerpf(_pose[J_LEG_R].x, knee * 0.35, planted)
	_body_off.y += _sample(d["body_y"], times, t) * w
	_pose[J_HEAD].x += _sample(d["head_x"], times, t) * w


func _pose_action(dt: float) -> void:
	if _action == "":
		_action_w = move_toward(_action_w, 0.0, dt * 6.0)
		_eyes_closed = move_toward(_eyes_closed, 0.0, dt * 8.0)
		_mouth_amt = move_toward(_mouth_amt, 0.0, dt * 6.0)
		_brow_worry = move_toward(_brow_worry, 0.0, dt * 5.0)
		return
	_action_t += dt
	var dur: float = float(ACTION_TIME.get(_action, 1.0))
	var w: float
	if dur > 0.0:
		w = smoothstep(0.0, minf(0.14, dur * 0.3), _action_t) * (1.0 - smoothstep(dur - minf(0.22, dur * 0.4), dur, _action_t))
		if _action_t >= dur:
			var finished := _action
			_action = ""
			if finished == "eat" and _food != null:
				_food.visible = false
			return
	else:
		w = smoothstep(0.0, 0.5, _action_t)
	_action_w = w
	var t := _action_t
	var eyes := 0.0
	var mouth := 0.0
	var worry := 0.0
	match _action:
		"hurt", "flinch":
			var trem := sin(t * 55.0) * 0.03 if _action == "flinch" else 0.0
			# Protective flinch: forearms folded in front of the face, leaning back and turning away.
			_blend(J_SPINE, Vector3(-0.22, 0.25, trem), w)
			_blend(J_HEAD, Vector3(0.12, 0.35, 0.12), w)
			_blend(J_SH_L, Vector3(-1.35, -0.55, 0.1), w)
			_blend(J_SH_R, Vector3(-1.2, 0.5, -0.1), w)
			_blend(J_EL_L, Vector3(-2.0, 0, 0), w)
			_blend(J_EL_R, Vector3(-1.9, 0, 0), w)
			_pose[J_KNEE_L].x += 0.25 * w
			_pose[J_KNEE_R].x += 0.25 * w
			_body_off.z -= 0.05 * w
			_body_off.y -= 0.03 * w
			eyes = 0.85
			mouth = 0.45
			worry = 1.0
		"wave":
			_blend(J_SH_R, Vector3(-0.2, 0.0, -2.55), w)
			_blend(J_EL_R, Vector3(-0.15, 0.0, 0.0), w)
			var wave := sin(t * 11.0) * 0.45
			_pose[J_EL_R].z += wave * w
			_pose[J_HAND_R].z += wave * 0.5 * w
			_blend(J_HEAD, Vector3(0.05, -0.15, -0.14), w)
			_pose[J_SPINE].z += 0.05 * w
			mouth = 0.55
		"cheer":
			var hop := absf(sin(t * 7.5))
			_blend(J_SH_L, Vector3(-0.25, 0.0, 2.65), w)
			_blend(J_SH_R, Vector3(-0.25, 0.0, -2.65), w)
			_blend(J_EL_L, Vector3(-0.3, 0, 0), w)
			_blend(J_EL_R, Vector3(-0.3, 0, 0), w)
			_blend(J_HEAD, Vector3(-0.18, 0, sin(t * 7.5) * 0.12), w)
			_body_off.y += hop * 0.1 * w
			_pose[J_KNEE_L].x += (1.0 - hop) * 0.4 * w
			_pose[J_KNEE_R].x += (1.0 - hop) * 0.4 * w
			eyes = 1.0
			mouth = 1.0
		"eat":
			var bite := absf(sin(t * 6.0))
			_blend(J_SH_R, Vector3(-1.25, 0.45, -0.1), w)
			_blend(J_EL_R, Vector3(-2.1 + bite * 0.25, 0.0, 0.0), w)
			_blend(J_HEAD, Vector3(0.12, 0.08, 0.05), w)
			eyes = 0.9
			mouth = bite
			if _food != null and _food.visible:
				var s := clampf(1.0 - t / dur, 0.15, 1.0)
				_food.scale = Vector3.ONE * s
		"interact":
			_blend(J_SH_R, Vector3(-1.1, 0.1, -0.1), w)
			_blend(J_EL_R, Vector3(-0.3, 0, 0), w)
			_pose[J_SPINE].x += 0.18 * w
			_pose[J_HEAD].x += 0.15 * w
		"tired":
			_blend(J_SPINE, Vector3(0.5, 0, 0), w)
			_blend(J_SH_L, Vector3(-0.5, 0, 0.1), w)
			_blend(J_SH_R, Vector3(-0.5, 0, -0.1), w)
			_blend(J_EL_L, Vector3(-0.2, 0, 0), w)
			_blend(J_EL_R, Vector3(-0.2, 0, 0), w)
			_pose[J_KNEE_L].x += 0.35 * w
			_pose[J_KNEE_R].x += 0.35 * w
			_body_off.y -= 0.05 * w
			_body_off.y += sin(t * 9.0) * 0.008 * w
			mouth = 0.5
		"sleep", "death":
			# Sit down on the ground, hug the knees, head tilted, eyes closed (death slumps sideways).
			var slow := sin(t * 1.3)
			_blend(J_LEG_L, Vector3(-1.45, -0.12, 0.08), w)
			_blend(J_LEG_R, Vector3(-1.45, 0.12, -0.08), w)
			_blend(J_KNEE_L, Vector3(1.9, 0, 0), w)
			_blend(J_KNEE_R, Vector3(1.9, 0, 0), w)
			# Arms hug the knees; the head rests tilted on them so the sleepy face stays visible.
			_blend(J_SPINE, Vector3(0.22 + slow * 0.02, 0, 0), w)
			_blend(J_SH_L, Vector3(-0.75, -0.55, 0.12), w)
			_blend(J_SH_R, Vector3(-0.75, 0.55, -0.12), w)
			_blend(J_EL_L, Vector3(-1.1, 0, 0), w)
			_blend(J_EL_R, Vector3(-1.1, 0, 0), w)
			_blend(J_HEAD, Vector3(0.12 + slow * 0.02, 0.1, 0.38), w)
			_body_off.y -= 0.36 * w
			_body_off.z -= 0.08 * w
			if _action == "death":
				_pose[J_HIPS].z += 0.9 * w
				_body_off.x += 0.18 * w
				_body_off.y -= 0.08 * w
			eyes = 1.0
	_eyes_closed = move_toward(_eyes_closed, eyes * w, dt * 10.0)
	_mouth_amt = move_toward(_mouth_amt, mouth * w, dt * 8.0)
	_brow_worry = move_toward(_brow_worry, worry * w, dt * 8.0)


func _blend(j: int, target: Vector3, w: float) -> void:
	_pose[j] = _pose[j].lerp(target, w)


func _pose_roll(dt: float) -> void:
	var active := roll_t >= 0.0
	_roll_blend = move_toward(_roll_blend, 1.0 if active else 0.0, dt * 14.0)
	if not active:
		_roll.rotation.x = 0.0
		_roll.scale = Vector3.ONE
		_roll.position = Vector3(0, 0.5, 0)
		return
	var t := clampf(roll_t, 0.0, 1.0)
	var env := sin(PI * t)
	var tuck := clampf(env * 1.5, 0.0, 1.0)
	_blend(J_LEG_L, Vector3(-1.5, 0, 0.05), tuck)
	_blend(J_LEG_R, Vector3(-1.5, 0, -0.05), tuck)
	_blend(J_KNEE_L, Vector3(2.2, 0, 0), tuck)
	_blend(J_KNEE_R, Vector3(2.2, 0, 0), tuck)
	_blend(J_SH_L, Vector3(-1.0, 0.4, 0.2), tuck)
	_blend(J_SH_R, Vector3(-1.0, -0.4, -0.2), tuck)
	_blend(J_EL_L, Vector3(-1.9, 0, 0), tuck)
	_blend(J_EL_R, Vector3(-1.9, 0, 0), tuck)
	_blend(J_SPINE, Vector3(0.55, 0, 0), tuck)
	_blend(J_HEAD, Vector3(0.45, 0, 0), tuck)
	var u := smoothstep(0.05, 0.92, t)
	_roll.rotation.x = u * TAU
	var sc := 1.0 - 0.46 * env
	_roll.scale = Vector3(1.0, sc, 1.0)
	# Lower the pivot while tucked so the little ball rolls along the ground instead of floating.
	_roll.position = Vector3(0, 0.5 - 0.15 * env, 0)


## The big chibi head sticks out of the tucked ball: while it swings under the pivot (upside-down part of
## the roll) it used to sink ~0.4 m into the ground. Lift the roll pivot just enough to keep the head and
## hair above the floor, so the roll reads as a tumble over the head.
func _keep_roll_above_ground() -> void:
	if roll_t < 0.0 or _head_c == null or _roll == null or not is_inside_tree():
		return
	var xf := global_transform.affine_inverse() * _head_c.global_transform
	var low := INF
	for p in _HEAD_HULL:
		low = minf(low, (xf * p).y)
	if low < ROLL_CLEARANCE:
		_roll.position.y += ROLL_CLEARANCE - low


func _apply_pose(_dt: float) -> void:
	for i in J_COUNT:
		var j := _joints[i]
		if j != null:
			j.rotation = _pose[i]
	_body.position = Vector3(0, -0.5, 0) + _body_off
	_body_root.scale = Vector3(1.0 - _sq * 0.5, 1.0 + _sq, 1.0 - _sq * 0.5)


func _update_face(dt: float) -> void:
	_blink_timer -= dt
	if _blink_timer <= 0.0:
		_blink_t = 0.0
		_blink_timer = randf_range(0.22, 0.3) if randf() < 0.18 else randf_range(2.0, 5.0)
	var blink := 0.0
	if _blink_t >= 0.0:
		_blink_t += dt
		blink = sin(clampf(_blink_t / 0.13, 0.0, 1.0) * PI)
		if _blink_t >= 0.13:
			_blink_t = -1.0
	var closed := maxf(blink, _eyes_closed)
	var sy := lerpf(1.0, 0.1, closed)
	for e in _eyes:
		e.scale = Vector3(1.0, sy, 1.0)
	for i in _brows.size():
		var s := 1.0 if i == 0 else -1.0
		var b := _brows[i]
		b.position.y = 0.062 - 0.008 * closed + 0.01 * _mouth_amt * (1.0 - _brow_worry)
		b.rotation.z = 0.35 * _brow_worry * s
	var open := _mouth_amt > 0.2
	_mouth_open.visible = open
	_mouth_smile.visible = not open
	if open:
		_mouth_open.scale = Vector3(1.0 + 0.15 * _mouth_amt, 0.5 + 0.6 * _mouth_amt, 0.45)


func _update_secondary(dt: float) -> void:
	if not is_inside_tree():
		return
	var gp := global_position
	var lv := Vector3.ZERO
	if not driven:
		lv = Vector3(0, 0, speed)
	elif _has_prev:
		var v := (gp - _prev_gpos) / maxf(dt, 0.001)
		if v.length() > 14.0:
			v = Vector3.ZERO
		lv = global_basis.inverse() * v
	_prev_gpos = gp
	_has_prev = true
	var acc := (lv - _prev_lv) / maxf(dt, 0.001)
	acc = acc.limit_length(40.0)
	_prev_lv = lv
	var flutter := sin(_t * 17.0) * 0.1 * _run_w
	var fall := maxf(0.0, -lv.y) * 0.06
	# Scarf ends: trail behind when moving, lag on acceleration, flutter when running.
	for i in 2:
		var target := Vector2(clampf(lv.z * 0.13 + acc.z * 0.012 + fall, -0.5, 1.35), clampf(-lv.x * 0.1 - acc.x * 0.01, -0.7, 0.7))
		target.x += flutter * (1.0 if i == 0 else -0.7)
		var a: Vector2 = _scarf_ang[i]
		var v2: Vector2 = _scarf_vel[i]
		v2 += ((target - a) * 70.0 - v2 * 7.5) * dt
		a += v2 * dt
		_scarf_ang[i] = a
		_scarf_vel[i] = v2
		var pair: Array = _scarf_ends[i]
		(pair[0] as Node3D).rotation = Vector3(0.25 + a.x * 0.7, 0.0, (0.22 - 0.4 * i) + a.y * 0.7)
		(pair[1] as Node3D).rotation = Vector3(a.x * 0.45 + sin(_t * 9.0 + i) * 0.05 * _move_w, 0.0, a.y * 0.4)
	# Braid: heavier and slower; swings with the bob and lags behind turns.
	var bt := Vector2(clampf(lv.z * 0.08 + acc.z * 0.01 + fall * 0.8, -0.4, 0.9), clampf(-lv.x * 0.07 - acc.x * 0.008 + turn_rate * 0.03, -0.6, 0.6))
	bt.x -= _pose[J_SPINE].x * 0.8 + _pose[J_HEAD].x * 0.6
	_braid_vel += ((bt - _braid_ang) * 38.0 - _braid_vel * 5.0) * dt
	_braid_ang += _braid_vel * dt
	for i in _braid.size():
		var seg := _braid[i]
		var k := 0.22 + 0.06 * i
		var wave := sin(_t * 5.5 - float(i) * 0.8) * 0.04 * _move_w
		if i == 0:
			seg.rotation = Vector3(_braid_ang.x * 0.5, 0.0, _braid_ang.y * 0.5 + wave)
		else:
			seg.rotation = Vector3(_braid_ang.x * k * 0.5, 0.0, _braid_ang.y * k * 0.5 + wave)
	# Lantern: kept upright with a little pendulum lag.
	var lt := Vector2(clampf(lv.z * 0.05 + acc.z * 0.015, -0.6, 0.6), clampf(-lv.x * 0.05 - acc.x * 0.015, -0.6, 0.6))
	_lant_vel += ((lt - _lant_ang) * 55.0 - _lant_vel * 4.0) * dt
	_lant_ang += _lant_vel * dt


func _update_props(dt: float) -> void:
	var raised := lantern_on and roll_t < 0.0
	if _lantern != null:
		_lantern.visible = raised
		if raised and _lantern.is_inside_tree():
			var up_basis := global_basis * Basis.from_euler(Vector3(_lant_ang.x, 0.0, _lant_ang.y))
			_lantern.global_basis = up_basis.orthonormalized()
	if _lantern_belt != null:
		_lantern_belt.visible = lantern_owned and not lantern_on
	if _lantern_light != null:
		_lantern_light.visible = lantern_on
		if lantern_on and _lantern != null and _lantern.is_inside_tree():
			_lantern_light.global_position = lantern_world_position() + Vector3(0, 0.02, 0)
			_lant_scale = lerpf(_lant_scale, lantern_energy_scale, 1.0 - exp(-2.0 * dt))
			_lantern_light.light_energy = (1.25 + sin(_t * 7.3) * 0.045 + sin(_t * 12.1 + 1.3) * 0.035) * _lant_scale


# =====================================================================================================
# Standalone demo (preview stage)
# =====================================================================================================

func _run_demo(dt: float) -> void:
	_demo_t += dt
	match _demo:
		"axe", "pickaxe", "sword", "hands", "gather", "swing":
			var kind := "axe" if _demo == "swing" else _demo
			var cycle := 0.5 + 0.45
			var t := fmod(_demo_t, cycle)
			if t < 0.5:
				swing_kind = kind
				swing_t = t / 0.5
				if _shown_tool != kind and _tools.has(kind):
					show_tool(kind, 0.9)
				_tool_timer = 0.5
			else:
				swing_t = -1.0
		"roll":
			var t := fmod(_demo_t, 0.45 + 0.5)
			roll_t = t / 0.45 if t < 0.45 else -1.0
		"jump":
			var t := fmod(_demo_t, 1.2)
			grounded = t > 0.8
			vertical_speed = 6.0 - 18.0 * t
			if absf(t - 0.0) < dt:
				play_action("jump")
			if absf(t - 0.8) < dt:
				play_action("land", 2.0)
		"wave", "cheer", "flinch", "eat", "hurt", "tired":
			if _action == "":
				play_action(_demo)

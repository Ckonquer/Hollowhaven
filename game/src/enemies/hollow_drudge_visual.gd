extends Node3D
## Hollow Drudge look: an EMPTY miner's long coat that shambles on by itself - hunched forward, sleeves hanging
## long, a dented helmet with a dead lamp over a dark hood where two faint pale glints sit, teal and amber
## mineral crust growing from the shoulders and back, dragging one boot. It holds a pickaxe in both hands.
## A zombie-like silhouette with no gore. Faces -Z, feet at y = 0, about 2 m tall (with the pick) and 0.9 m wide.
## States (set_state): idle / wander / chase / return (shambling sway, one foot dragging), telegraph with
## set_attack("pick_swing") = pick raised high overhead, leaning back, amber glow on the pick head; telegraph with
## set_attack("scrape") = crouched low, pick dragged back along the floor with a cool white glow and sparks
## (two clearly different poses AND colours), swing / scrape (the strike), recover (slumped, pick resting on the
## floor), stunned, flinch, dead.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const COAT_COLOR := Color("6b5646")
const COAT_DARK := Color("4e3e33")
const TROUSER_COLOR := Color("4a3f3a")
const BOOT_COLOR := Color("3b302a")
const HOOD_COLOR := Color("1d1820")
const HELMET_COLOR := Color("8c7a4a")
const METAL_COLOR := Color("8a8f96")
const CRUST_TEAL := Color("7fc9c0")
const CRUST_AMBER := Color("e0a95a")
const GLINT_COLOR := Color("c9e8ff")
const SWING_TINT := Color(1.0, 0.62, 0.2)
const SCRAPE_TINT := Color(0.72, 0.87, 1.0)
const HIP_Y := 0.78

var state: String = "idle"
var state_len: float = 0.0
var attack_kind: String = "pick_swing"
var move_speed: float = 0.0
var preview_walk := false

var _t: float = 0.0
var _st: float = 0.0
var _flash_t: float = 0.0
var _spark_t: float = 0.0
var _root: Node3D
var _torso: Node3D
var _legs: Array = []
var _arms: Array = []
var _pick: Node3D
var _pick_head: MeshInstance3D
var _tint_mat: StandardMaterial3D
var _pick_tint: StandardMaterial3D
var _tint_meshes: Array = []
var _tint_on := false
var _pick_tint_on := false


func _ready() -> void:
	_build()


func body_height() -> float:
	return 1.85


func _build() -> void:
	_tint_mat = HitFx.new_tint()
	_pick_tint = HitFx.new_tint()
	_root = Node3D.new()
	_root.name = "Root"
	add_child(_root)
	var trouser := Mat.outlined(Mat.toon(TROUSER_COLOR, {"noise": 0.12}), 0.012)
	var boot := Mat.outlined(Mat.toon(BOOT_COLOR), 0.012)
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "Leg"
		Kit.add(_root, leg, Vector3(sx * 0.15, HIP_Y, 0))
		Kit.add(leg, Kit.capsule(0.12, 0.72, trouser), Vector3(0, -0.36, 0))
		Kit.add(leg, Kit.sphere(0.12, boot, 8, 12), Vector3(0, -0.72, -0.05), Vector3.ZERO, Vector3(1.0, 0.6, 1.5))
		_legs.append(leg)
	# Torso pivots at the hips so the whole coat can hunch, lean back or crouch.
	_torso = Node3D.new()
	_torso.name = "Torso"
	Kit.add(_root, _torso, Vector3(0, HIP_Y, 0))
	var coat_mat := Mat.outlined(Mat.toon(COAT_COLOR, {"rim": 0.35, "noise": 0.18}), 0.016)
	var coat_dark := Mat.outlined(Mat.toon(COAT_DARK, {"rim": 0.3, "noise": 0.18}), 0.014)
	var coat := Kit.cylinder(0.27, 0.42, 0.95, coat_mat, 14)
	Kit.add(_torso, coat, Vector3(0, 0.22, 0))
	_tint_meshes.append(coat)
	var chest := Kit.blob(0.3, coat_mat, 31, 0.06, 1.0, 3)
	Kit.add(_torso, chest, Vector3(0, 0.62, -0.02), Vector3.ZERO, Vector3(1.15, 0.85, 0.9))
	_tint_meshes.append(chest)
	var hem := Kit.cylinder(0.42, 0.46, 0.08, coat_dark, 14)
	Kit.add(_torso, hem, Vector3(0, -0.24, 0))
	for sx in [-1.0, 1.0]:
		Kit.add(_torso, Kit.box(Vector3(0.1, 0.5, 0.04), coat_dark), Vector3(sx * 0.1, 0.5, -0.29), Vector3(8, 0, sx * 6.0))
	# Mineral crust (teal + amber crystals, no gore)
	var teal := Mat.outlined(Mat.toon(CRUST_TEAL, {"rim": 0.6, "emission": CRUST_TEAL, "emission_energy": 0.25}), 0.008)
	var amber := Mat.outlined(Mat.toon(CRUST_AMBER, {"rim": 0.6, "emission": CRUST_AMBER, "emission_energy": 0.2}), 0.008)
	var crystals := [[Vector3(0.25, 0.85, 0.05), Vector3(0, 0, -35), teal], [Vector3(0.3, 0.78, 0.12), Vector3(20, 0, -60), amber],
		[Vector3(-0.27, 0.86, 0.08), Vector3(10, 0, 40), teal], [Vector3(0.05, 0.8, 0.26), Vector3(55, 0, 5), amber],
		[Vector3(-0.12, 0.62, 0.3), Vector3(70, 0, -10), teal], [Vector3(0.14, 0.45, 0.33), Vector3(75, 0, 15), teal]]
	for c in crystals:
		Kit.add(_torso, Kit.cone(0.06, 0.26, c[2], 6), c[0], c[1])
	# Hood, helmet with a dead lamp, two faint glints (the only "face")
	var hood := Kit.sphere(0.23, Mat.outlined(Mat.toon(HOOD_COLOR, {"rim": 0.2, "noise": 0.0}), 0.012), 12, 16)
	Kit.add(_torso, hood, Vector3(0, 0.98, -0.12), Vector3.ZERO, Vector3(1.0, 1.05, 1.0))
	var helmet := Kit.cylinder(0.2, 0.27, 0.16, Mat.outlined(Mat.toon(HELMET_COLOR, {"rim": 0.4, "specular": 0.4}), 0.01), 14)
	Kit.add(_torso, helmet, Vector3(0, 1.16, -0.1), Vector3(-10, 0, 8))
	_tint_meshes.append(helmet)
	Kit.add(_torso, Kit.cylinder(0.06, 0.06, 0.06, Mat.glow(Color("6a5a40"), 0.4), 10), Vector3(0, 1.18, -0.33), Vector3(80, 0, 0))
	for sx in [-1.0, 1.0]:
		var glint := Kit.sphere(0.025, Mat.glow(GLINT_COLOR, 1.3), 6, 8)
		glint.set_meta("no_flash", true)
		Kit.add(_torso, glint, Vector3(sx * 0.07, 0.96, -0.32))
	# Arms (long hanging sleeves) - pivots at the shoulders
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "Arm"
		Kit.add(_torso, arm, Vector3(sx * 0.34, 0.78, -0.04))
		var sleeve := Kit.capsule(0.1, 0.66, coat_mat)
		Kit.add(arm, sleeve, Vector3(0, -0.3, 0))
		_tint_meshes.append(sleeve)
		Kit.add(arm, Kit.sphere(0.075, Mat.outlined(Mat.toon(Palette.STONE_DARK), 0.008), 8, 10), Vector3(0, -0.64, 0))
		_arms.append(arm)
	# Pickaxe held in the right hand
	_pick = Node3D.new()
	_pick.name = "Pick"
	Kit.add(_arms[1], _pick, Vector3(0, -0.64, 0))
	Kit.add(_pick, Kit.cylinder(0.035, 0.035, 1.0, Mat.outlined(Mat.toon(Palette.WOOD_DARK), 0.008), 8), Vector3(0, 0, -0.35), Vector3(90, 0, 0))
	var metal := Mat.outlined(Mat.toon(METAL_COLOR, {"rim": 0.5, "specular": 0.6}), 0.01)
	_pick_head = Kit.box(Vector3(0.1, 0.1, 0.12), metal)
	Kit.add(_pick, _pick_head, Vector3(0, 0, -0.86))
	for sy in [-1.0, 1.0]:
		var tip := Kit.cone(0.05, 0.34, metal, 7)
		Kit.add(_pick, tip, Vector3(0, sy * 0.2, -0.86), Vector3(0 if sy > 0 else 180, 0, 0))
		_tint_meshes.append(tip)


func set_state(new_state: String, length: float = 0.0) -> void:
	state = new_state
	state_len = length
	_st = 0.0


func set_attack(kind: String) -> void:
	attack_kind = kind


func play_anim(anim: String) -> void:
	if anim == "walk":
		preview_walk = true
		set_state("chase")
	elif anim == "scrape" or anim == "pick_swing":
		set_attack(anim)
		set_state("telegraph", 1.2)
	else:
		set_state(anim, 1.2)


func hit_flash(duration: float = 0.11) -> void:
	_flash_t = maxf(_flash_t, duration)


## Height of the pick head above the feet (tests: raised overhead vs dragged low).
func pick_head_height() -> float:
	return (_pick_head.global_position - global_position).y if is_inside_tree() else 0.0


func _process(delta: float) -> void:
	_t += delta
	_st += delta
	_flash_t = maxf(_flash_t - delta, 0.0)
	var speed := move_speed
	var p := get_parent()
	if p != null and "move_speed_now" in p:
		speed = float(p.get("move_speed_now"))
	if preview_walk:
		speed = 2.4
	var hunch := 0.32
	var roll := 0.0
	var arm_x := 0.35                  # arms hang forward
	var arm_l_x := 0.35
	var pick_x := 0.0
	var crouch := 0.0
	var gait := 0.0
	var tint := 0.0
	var tint_col := SWING_TINT
	match state:
		"telegraph":
			var k := clampf(_st / 0.35, 0.0, 1.0)
			if attack_kind == "scrape":
				hunch = 0.32 + 0.35 * k            # crouched low over the floor
				crouch = 0.14 * k
				arm_x = 0.35 - 1.25 * k            # pick dragged back along the floor
				arm_l_x = 0.35 - 0.5 * k
				pick_x = -0.5 * k
				tint_col = SCRAPE_TINT
				_spark_t -= delta
				if _spark_t <= 0.0:
					_spark_t = 0.25
					# silent sparks (HitFx.spark would also play a hit sound)
					HitFx.burst(global_transform * Vector3(0.3, 0.1, 0.45), HitFx.SPARK_COLOR, 5, 2.4, 0.4, -12.0, 0.25, 70.0)
			else:
				hunch = 0.32 - 0.5 * k             # leans back
				arm_x = 0.35 + 2.55 * k            # both arms raise the pick high overhead
				arm_l_x = 0.35 + 2.35 * k
				pick_x = 0.3 * k
				tint_col = SWING_TINT
			if HitFx.reduce_flashing():
				tint = 0.32 * k
			else:
				tint = 0.25 + 0.22 * (0.5 + 0.5 * sin(_st * 18.0))
		"swing":
			var s := clampf(_st / 0.14, 0.0, 1.0)
			hunch = 0.5 * s
			arm_x = 2.9 - 2.3 * s
			arm_l_x = 2.7 - 2.1 * s
		"scrape":
			var s := clampf(_st / 0.22, 0.0, 1.0)
			hunch = 0.67
			crouch = 0.14
			arm_x = -0.9 + 1.5 * s
			arm_l_x = -0.15 + 0.6 * s
			pick_x = -0.5 + 0.5 * s
		"recover", "stunned":
			hunch = 0.55 + sin(_st * 2.5) * 0.04
			arm_x = 0.8                         # pick head resting on the floor
			arm_l_x = 0.75
			roll = sin(_st * 1.8) * 0.06
		"flinch":
			var f := 1.0 - clampf(_st / 0.3, 0.0, 1.0)
			hunch = 0.32 - 0.3 * f
		"dead":
			hunch = 0.9
		_:
			if speed > 0.3:
				gait = 1.0
			roll = sin(_t * 1.4) * 0.08
	var k_s := 1.0 - exp(-12.0 * delta)
	var ph := _t * (1.2 + speed * 0.35) * TAU
	_root.position.y = lerpf(_root.position.y, -crouch + absf(sin(ph)) * 0.03 * gait, k_s)
	_torso.rotation.x = lerpf(_torso.rotation.x, -hunch, k_s)
	_torso.rotation.z = lerpf(_torso.rotation.z, roll + sin(ph * 0.5) * 0.06 * gait, k_s)
	for i in _legs.size():
		var leg := _legs[i] as Node3D
		var side := -1.0 if i == 0 else 1.0
		var swing := sin(ph + (0.0 if i == 0 else PI)) * 0.45 * gait
		if i == 1:
			swing *= 0.4                         # the dragging foot
		leg.rotation.x = lerpf(leg.rotation.x, swing, k_s)
		leg.rotation.z = lerpf(leg.rotation.z, side * crouch * 0.6, k_s)
	# rotation.x > 0 swings a hanging arm forward (and, past PI/2, up overhead); < 0 swings it back.
	(_arms[0] as Node3D).rotation.x = lerpf((_arms[0] as Node3D).rotation.x, arm_l_x, k_s)
	(_arms[1] as Node3D).rotation.x = lerpf((_arms[1] as Node3D).rotation.x, arm_x, k_s)
	_pick.rotation.x = lerpf(_pick.rotation.x, pick_x, k_s)
	_apply_tint(tint, tint_col)


func _apply_tint(tint: float, col: Color) -> void:
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(HitFx.FLASH_COLOR, HitFx.flash_strength(0.75))
	elif tint > 0.0:
		c = Color(col, clampf(tint, 0.0, 1.0))
	var on := c.a > 0.01
	if on:
		_tint_mat.albedo_color = c
	if on != _tint_on:
		_tint_on = on
		for m in _tint_meshes:
			(m as MeshInstance3D).material_overlay = _tint_mat if on else null
	# The pick head itself glows in the tell colour for the whole wind-up (a second, very local cue).
	var pick_on := state == "telegraph"
	if pick_on:
		_pick_tint.albedo_color = Color(tint_col_for_pick(), 0.75)
	if pick_on != _pick_tint_on:
		_pick_tint_on = pick_on
		_pick_head.material_overlay = _pick_tint if pick_on else null


func tint_col_for_pick() -> Color:
	return SCRAPE_TINT if attack_kind == "scrape" else SWING_TINT

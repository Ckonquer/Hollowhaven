extends Node3D
## The Heartseed cocoon at the centre of the Heartseed Chamber: a silk cocoon (arachnophobia mode:
## a cage of pale roots) with the Heartseed's pink glow beating inside. When the boss is defeated it
## splits open. Safety net: if the chapter state says the boss is beaten but the seed is nowhere
## (not held, not dropped, not returned), the opened cocoon offers it again. If the boss script is
## missing entirely, the cocoon itself lets Krystal free the seed so the game can never soft-lock.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")

const SEED := "heartseed"
const BOSS_ID := "weaver_matron"       # the only boss_defeated id that opens the cocoon

var ceiling_points: Array = []       # threads/roots run up to these
var opened: bool = false
var fallback_mode: bool = false      # boss missing: free the seed by hand
var safety_net: bool = true          # offer a lost seed again (only when the boss module can't)

var _shell: Node3D
var _seed_node: Node3D
var _light: OmniLight3D
var _it: Node3D
var _body: StaticBody3D
var _t: float = 0.0
var _tween: Tween


func setup(p: Dictionary) -> void:
	ceiling_points = p.get("ceiling", ceiling_points)
	fallback_mode = bool(p.get("fallback", fallback_mode))


func _ready() -> void:
	_seed_node = Node3D.new()
	add_child(_seed_node)
	_seed_node.position = Vector3(0, 1.25, 0)
	Kit.add(_seed_node, Kit.sphere(0.26, Mat.glow(Palette.HEART_GLOW, 3.0), 12, 16), Vector3.ZERO, Vector3.ZERO, Vector3(0.85, 1.0, 0.85))
	Kit.add(_seed_node, Kit.sphere(0.12, Mat.glow(Color("fff0f4"), 4.0), 8, 10), Vector3(0, 0.05, 0))
	_light = OmniLight3D.new()
	_light.light_color = Palette.HEART_GLOW
	_light.light_energy = 1.3
	_light.omni_range = 7.0
	_light.shadow_enabled = true
	_light.shadow_bias = 0.1
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 40.0
	_light.distance_fade_length = 10.0
	_light.light_volumetric_fog_energy = 0.6
	add_child(_light)
	_light.position = Vector3(0, 1.3, 0)
	opened = bool(GameState.get_flag("weaver_defeated"))
	_build_shell()
	Events.settings_changed.connect(_on_settings_changed)
	Events.boss_defeated.connect(_on_boss_defeated)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	var bcs := CollisionShape3D.new()
	var bsh := CylinderShape3D.new()
	bsh.radius = 0.95
	bsh.height = 2.6
	bcs.shape = bsh
	bcs.position = Vector3(0, 1.3, 0)
	_body.add_child(bcs)
	add_child(_body)
	_it = Interactable.new()
	_it.setup({"size": Vector3(2.2, 2.4, 2.2), "text_func": Callable(self, "_interaction"), "handler": Callable(self, "_on_interact")})
	add_child(_it)
	_apply_state()


func _on_settings_changed(key: String) -> void:
	if key == "arachnophobia":
		_build_shell()
		_apply_state()


func _build_shell() -> void:
	if _shell != null:
		_shell.queue_free()
	_shell = Node3D.new()
	_shell.name = "Shell"
	add_child(_shell)
	var arachno := bool(Settings.get_value("arachnophobia"))
	var group := "below_root" if arachno else "below_web"
	if arachno:
		var root_mat := Mat.outlined(Mat.toon(Color("8a7560"), {"rim": 0.4, "noise": 0.15}), 0.02)
		var pale := Mat.toon(Color("cdbfa3"), {"rim": 0.5, "emission": Color("cdbfa3"), "emission_energy": 0.06})
		for i in 8:
			var a := float(i) / 8.0 * TAU + (0.2 if i % 2 == 0 else -0.15)
			var half := Node3D.new()
			_shell.add_child(half)
			half.rotation.y = a
			# Each root bulges out around the seed and closes over it: a gnarled cage
			var bulge := 1.05 if i % 2 == 0 else 0.9
			var pts := [Vector3(0.95, 0.0, 0.0), Vector3(bulge * 1.15, 0.7, 0.12), Vector3(bulge, 1.55, -0.1), Vector3(0.55, 2.25, 0.08), Vector3(0.05, 2.6, 0.0)]
			for k in 4:
				_seg(half, pts[k], pts[k + 1], 0.2 - float(k) * 0.035, root_mat)
				Kit.add(half, Kit.sphere(0.2 - float(k) * 0.035, root_mat, 6, 8), pts[k + 1])
		Kit.add(_shell, Kit.blob(1.2, root_mat, 55, 0.35, 0.3), Vector3(0, 0.05, 0))
		Kit.add(_shell, Kit.blob(0.35, root_mat, 56, 0.3, 0.9), Vector3(0, 2.6, 0))
		for p in ceiling_points:
			var top: Vector3 = p
			_seg(_shell, Vector3(0, 2.7, 0), top - global_position, 0.05, pale)
		for i in 5:
			var a := float(i) / 5.0 * TAU + 0.3
			Kit.add(_shell, Kit.sphere(0.06, Mat.glow(Color("d9f2c4"), 1.2), 4, 6), Vector3(cos(a) * 0.9, 1.6 + sin(a * 2.0) * 0.4, sin(a) * 0.9))
	else:
		var silk := Mat.transparent(Color(0.92, 0.88, 0.95, 0.78))
		var silk_solid := Mat.toon(Palette.SILK_WEB, {"rim": 0.7, "emission": Palette.SILK_WEB, "emission_energy": 0.15})
		var left := Node3D.new()
		left.name = "HalfL"
		_shell.add_child(left)
		var right := Node3D.new()
		right.name = "HalfR"
		_shell.add_child(right)
		Kit.add(left, Kit.blob(0.62, silk, 71, 0.12, 1.9), Vector3(-0.14, 1.25, 0), Vector3(0, 0, 4), Vector3(0.8, 1.0, 1.05))
		Kit.add(right, Kit.blob(0.62, silk, 72, 0.12, 1.9), Vector3(0.14, 1.25, 0), Vector3(0, 0, -4), Vector3(0.8, 1.0, 1.05))
		for k in 5:
			var y := 0.45 + float(k) * 0.42
			var w := 0.62 * (1.0 - absf(float(k) - 2.0) * 0.2)
			Kit.add(left if k % 2 == 0 else right, Kit.torus(w * 0.95, w, silk_solid), Vector3(0, y, 0), Vector3(randf_range(-14, 14), 0, randf_range(-14, 14)))
		for p in ceiling_points:
			var top: Vector3 = p
			_seg(_shell, Vector3(0, 2.3, 0), top - global_position, 0.018, silk_solid)
		for i in 8:
			var a := float(i) / 8.0 * TAU
			_seg(_shell, Vector3(0, 0.4, 0), Vector3(cos(a) * 2.4, 0.02, sin(a) * 2.4), 0.012, silk_solid)
	for c in _shell.get_children():
		_tag(c, group)


func _tag(n: Node, group: String) -> void:
	if n is GeometryInstance3D:
		n.add_to_group(group)
	for c in n.get_children():
		_tag(c, group)


func _seg(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var up := d / length
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := up.cross(ref).normalized()
	var z := x.cross(up).normalized()
	var mi := Kit.cylinder(radius * 0.7, radius, length, mat, 6)
	parent.add_child(mi)
	mi.transform = Transform3D(Basis(x, up, z), (a + b) * 0.5)


func _process(delta: float) -> void:
	_t += delta
	if opened:
		_light.light_energy = 0.9 + sin(_t * 1.2) * 0.1
		return
	# Heartbeat: two quick pulses, then a rest.
	var ph := fmod(_t, 1.6)
	var beat := exp(-pow((ph - 0.1) * 12.0, 2.0)) + 0.7 * exp(-pow((ph - 0.42) * 12.0, 2.0))
	_light.light_energy = 0.9 + beat * 1.1
	_seed_node.scale = Vector3.ONE * (1.0 + beat * 0.12)


func _apply_state() -> void:
	_light.light_color = Palette.HEART_GLOW if not opened else Color("ffd2a8")
	_seed_node.visible = not opened
	if opened:
		_open_pose()
		if _body != null:
			_body.collision_layer = 0     # the split husk no longer blocks the way to the seed


func _open_pose() -> void:
	var l := _shell.get_node_or_null("HalfL")
	var r := _shell.get_node_or_null("HalfR")
	if l is Node3D:
		(l as Node3D).position = Vector3(-0.7, -0.35, 0.1)
		(l as Node3D).rotation = Vector3(0, 0, 0.9)
	if r is Node3D:
		(r as Node3D).position = Vector3(0.7, -0.35, -0.1)
		(r as Node3D).rotation = Vector3(0, 0, -0.9)
	if bool(Settings.get_value("arachnophobia")):
		_shell.scale = Vector3(1.25, 0.55, 1.25)


## Only the Weaver Matron opens the cocoon: Chapter Two bosses (Crossing Matron, Count Velour, the
## Choir, the Quarry Warden...) emit boss_defeated too (R72).
func _on_boss_defeated(boss_id: String) -> void:
	if boss_id != BOSS_ID or opened:
		return
	open_cocoon(true)


func open_cocoon(animate: bool) -> void:
	opened = true
	if not animate:
		_apply_state()
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	Audio.play_3d("heartseed_pulse", global_position + Vector3(0, 1.3, 0))
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_light, "light_energy", 4.0, 0.4)
	_tween.tween_property(_seed_node, "scale", Vector3.ONE * 1.6, 0.4)
	_tween.chain().tween_callback(_apply_state)
	var l := _shell.get_node_or_null("HalfL")
	var r := _shell.get_node_or_null("HalfR")
	if l is Node3D and r is Node3D:
		var t2 := create_tween().set_parallel(true)
		t2.tween_property(l, "position", Vector3(-0.7, -0.35, 0.1), 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t2.tween_property(l, "rotation", Vector3(0, 0, 0.9), 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t2.tween_property(r, "position", Vector3(0.7, -0.35, -0.1), 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		t2.tween_property(r, "rotation", Vector3(0, 0, -0.9), 1.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		var t3 := create_tween()
		t3.tween_property(_shell, "scale", Vector3(1.25, 0.55, 1.25), 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## True when the seed has been lost after the boss (not held, not dropped, not yet returned).
static func seed_missing() -> bool:
	if not bool(GameState.get_flag("weaver_defeated")) or bool(GameState.get_flag("ward_restored")):
		return false
	if GameState.has_item(SEED):
		return false
	for d in GameState.dropped:
		if String(d.get("item", "")) == SEED:
			return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.get_nodes_in_group("heartseed_pickup").is_empty():
		return false
	return bool(GameState.get_flag("heartseed_spawned_checked"))


func _interaction() -> Dictionary:
	if fallback_mode and not opened:
		return {"text": "Free the Heartseed", "enabled": true}
	if opened and safety_net and seed_missing():
		return {"text": "Take the Heartseed", "enabled": true}
	return {}


func _on_interact(_player: Node) -> void:
	if fallback_mode and not opened:
		push_warning("Below: boss unavailable - freeing the Heartseed directly (fallback).")
		GameState.set_flag("weaver_defeated", true)
		GameState.give_item(SEED, 1)
		Events.boss_defeated.emit(BOSS_ID)
		return
	if opened and safety_net and seed_missing():
		GameState.give_item(SEED, 1)
		Audio.play_3d("heartseed_pulse", global_position + Vector3(0, 1.3, 0))

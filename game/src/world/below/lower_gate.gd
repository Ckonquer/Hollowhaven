extends Node3D
## The Lower Gate: an old carved stone arch the miners fitted with heavy iron-banded doors.
## Locked: "The gate is locked. The foreman kept the key." With the Foreman's Key: "Unlock the gate"
## -> gate_unlock sound, the doors swing open, flag "lower_gate_open" (stays open after reload).
## The node sits at the centre of the passage floor; the passage runs along -z (north).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const FLAG := "lower_gate_open"
const KEY := "foreman_key"
const OPEN_ANGLE := 86.0

## Configurable for other locked gates (defaults = the Below's lower gate).
var flag: String = FLAG
var key: String = KEY
var locked_text: String = "The gate is locked. The foreman kept the key."
var width: float = 4.0
var height: float = 3.4
var is_open: bool = false
var animating: bool = false

var _left: Node3D
var _right: Node3D
var _area: Area3D
var _lock_glow: Node3D
var _tween: Tween


func setup(p: Dictionary) -> void:
	flag = String(p.get("flag", flag))
	key = String(p.get("key", key))
	locked_text = String(p.get("locked_text", locked_text))
	width = float(p.get("width", width))
	height = float(p.get("height", height))


func _ready() -> void:
	_build()
	if bool(GameState.get_flag(flag)):
		_set_open_immediate()
	else:
		add_to_group("interactable")


func _build() -> void:
	var stone := Mat.toon(Palette.RUIN_STONE, {"rim": 0.25})
	var stone_dark := Mat.toon(Palette.RUIN_STONE_DARK)
	var half := width * 0.5
	# Carved arch (older than the mine)
	for s in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.7, height + 0.3, 0.9), stone), Vector3(s * (half + 0.3), (height + 0.3) * 0.5, 0))
		Kit.add(self, Kit.box(Vector3(0.9, 0.25, 1.05), stone_dark), Vector3(s * (half + 0.3), 0.12, 0))
		Kit.add(self, Kit.box(Vector3(0.85, 0.2, 1.0), stone_dark), Vector3(s * (half + 0.3), height + 0.35, 0))
	Kit.add(self, Kit.box(Vector3(width + 1.5, 0.55, 1.0), stone), Vector3(0, height + 0.62, 0))
	# Keystone with a closed carved eye
	Kit.add(self, Kit.box(Vector3(0.8, 0.8, 1.1), stone_dark), Vector3(0, height + 0.65, 0))
	Kit.add(self, Kit.box(Vector3(0.45, 0.05, 0.05), Mat.toon(Color(0.12, 0.13, 0.15))), Vector3(0, height + 0.66, 0.56))
	# Warning boards nailed across the arch top by the miners
	var plank := Mat.outlined(Mat.toon(Color("8e6340")), 0.015)
	var b1 := Kit.add(self, Kit.box(Vector3(width * 0.9, 0.22, 0.05), plank), Vector3(0, height + 0.15, 0.52), Vector3(0, 0, 4))
	var paint := Mat.toon(Color("c84b3c"))
	Kit.add(b1, Kit.box(Vector3(width * 0.5, 0.08, 0.02), paint), Vector3(0, 0, 0.035))
	_left = _make_leaf(-1.0)
	_right = _make_leaf(1.0)
	# Probe collider
	_area = Area3D.new()
	_area.collision_layer = 16
	_area.collision_mask = 0
	_area.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 2.6, 1.2)
	cs.shape = sh
	cs.position = Vector3(0, 1.3, 0)
	_area.add_child(cs)
	add_child(_area)


## A door leaf hinged at x = side * width/2, extending toward the centre.
func _make_leaf(side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Leaf%s" % ("L" if side < 0.0 else "R")
	add_child(pivot)
	pivot.position = Vector3(side * width * 0.5, 0.0, 0.0)
	var leaf_w := width * 0.5 - 0.04
	var wood := Mat.outlined(Mat.toon(Color("6e4a31")), 0.02)
	var wood2 := Mat.outlined(Mat.toon(Color("7d5538")), 0.02)
	var iron := Mat.outlined(Mat.toon(Color("4a4048"), {"rim": 0.45}), 0.015)
	var dir := -side     # toward the centre
	var n := 4
	for i in n:
		var pw := leaf_w / float(n)
		Kit.add(pivot, Kit.box(Vector3(pw - 0.03, height - 0.1, 0.14), wood if i % 2 == 0 else wood2), Vector3(dir * (pw * (float(i) + 0.5)), (height - 0.1) * 0.5 + 0.05, 0))
	for y in [0.45, height * 0.5, height - 0.45]:
		Kit.add(pivot, Kit.box(Vector3(leaf_w, 0.14, 0.2), iron), Vector3(dir * leaf_w * 0.5, y, 0))
		for k in 3:
			Kit.add(pivot, Kit.sphere(0.035, iron, 6, 8), Vector3(dir * leaf_w * (0.2 + 0.3 * float(k)), y, 0.11))
	if side > 0.0:
		# Lock plate with a faint brass glint so it reads in the dark
		Kit.add(pivot, Kit.box(Vector3(0.3, 0.42, 0.08), Mat.outlined(Mat.toon(Color("c9b27a"), {"rim": 0.6, "emission": Color("c9a25a"), "emission_energy": 0.25}), 0.015)), Vector3(dir * (leaf_w - 0.22), height * 0.45, 0.12))
		_lock_glow = Kit.add(pivot, Kit.sphere(0.04, Mat.glow(Color("ffd27a"), 1.2), 6, 8), Vector3(dir * (leaf_w - 0.22), height * 0.45 - 0.06, 0.17))
	else:
		Kit.add(pivot, Kit.torus(0.07, 0.11, iron), Vector3(dir * (leaf_w - 0.25), height * 0.45, 0.15), Vector3(90, 0, 0))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(leaf_w, height, 0.24)
	cs.shape = sh
	cs.position = Vector3(dir * leaf_w * 0.5, height * 0.5, 0)
	body.add_child(cs)
	pivot.add_child(body)
	return pivot


func _open_rotation(side: float) -> float:
	# Leaves swing north (-z), away from the gallery.
	return deg_to_rad(OPEN_ANGLE) * (1.0 if side < 0.0 else -1.0)


func get_interaction(_player: Node = null) -> Dictionary:
	if is_open or animating:
		return {}
	if GameState.has_item(key):
		return {"text": "Unlock the gate", "enabled": true}
	return {"text": "Try the gate", "enabled": true}


func interact(_player: Node = null) -> void:
	if is_open or animating:
		return
	if not GameState.has_item(key):
		Events.say.emit("", locked_text, 3.5)
		Audio.play_3d("door_creak", global_position + Vector3(0, 1.5, 0), -8.0)
		GameState.set_flag("lower_gate_tried", true)
		_rattle()
		return
	unlock()


func unlock(animate: bool = true) -> void:
	if is_open:
		return
	GameState.set_flag(flag, true)
	remove_from_group("interactable")
	if _area != null:
		_area.queue_free()
		_area = null
	if not animate:
		_set_open_immediate()
		return
	animating = true
	Audio.play_3d("gate_unlock", global_position + Vector3(0, 1.5, 0))
	Events.caption.emit("[the lock turns with a heavy clunk]")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(0.7)
	_tween.tween_callback(func() -> void: Audio.play_3d("door_creak", global_position + Vector3(0, 1.5, 0)))
	_tween.set_parallel(true)
	_tween.tween_property(_left, "rotation:y", _open_rotation(-1.0), 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_right, "rotation:y", _open_rotation(1.0), 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.set_parallel(false)
	_tween.tween_callback(_on_open_done)
	if _lock_glow != null:
		_lock_glow.visible = false


func _on_open_done() -> void:
	animating = false
	is_open = true


func _set_open_immediate() -> void:
	is_open = true
	animating = false
	remove_from_group("interactable")
	if _area != null:
		_area.queue_free()
		_area = null
	_left.rotation.y = _open_rotation(-1.0)
	_right.rotation.y = _open_rotation(1.0)
	if _lock_glow != null:
		_lock_glow.visible = false


func _rattle() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_left.rotation.y = 0.0
	_right.rotation.y = 0.0
	_tween = create_tween()
	_tween.tween_property(_right, "rotation:y", -0.03, 0.06)
	_tween.tween_property(_right, "rotation:y", 0.02, 0.07)
	_tween.tween_property(_right, "rotation:y", -0.01, 0.07)
	_tween.tween_property(_right, "rotation:y", 0.0, 0.08)

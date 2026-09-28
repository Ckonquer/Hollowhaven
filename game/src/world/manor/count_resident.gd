extends Node3D
## Count Velour after his enchantment is broken (MP §13.1): an eccentric, NON-hostile manor resident.
## A small floating bat-masked figure in an oversized velvet cape, a flamboyant collar and a tiny crown; he
## hovers, his cape sways and he bows when spoken to. No branching dialogue: each talk says the next line
## of data/manor_layout.gd RESIDENT_LINES (the first is MP §17 verbatim). Never in group "enemy".
##   setup({"lines": [...], "greet": true})   # greet = say the first line on appearing (right after the win),
##                                              GREET_DELAY s of unpaused time later

signal spoke(line_index: int)

const Layout := preload("res://data/manor_layout.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const VELVET := Color("7d1e3c")
const LINING := Color("c2587e")
const MASK := Color("2a1830")
const SKIN := Color("d9c8e8")
const GOLD := Color("e2bd5e")
const GLOVE := Color("f6efe6")
const GREET_DELAY := 1.2

var lines: Array = Layout.RESIDENT_LINES
var greet: bool = false
var line_index: int = 0
var talks: int = 0
var _body: Node3D
var _cape: Node3D
var _t := 0.0
var _bow := 0.0


func setup(params: Dictionary) -> void:
	var l: Variant = params.get("lines", null)
	if l is Array and not (l as Array).is_empty():
		lines = l
	greet = bool(params.get("greet", greet))


func _ready() -> void:
	name = "CountVelourResident"
	add_to_group("interactable")
	add_to_group("mm_resident")
	_build()
	if greet:
		# Pause-aware (process_always = false): the greeting never fires behind the pause menu.
		get_tree().create_timer(GREET_DELAY, false).timeout.connect(_greet)


func _greet() -> void:
	if is_instance_valid(self) and is_inside_tree():
		say_next()


func get_interaction(_player: Node = null) -> Dictionary:
	return {"text": "Talk to Count Velour", "enabled": true}


func interact(_player: Node = null) -> void:
	say_next()


## Says the next line (wrapping around). Returns the line.
func say_next() -> String:
	if lines.is_empty():
		return ""
	var i := line_index % lines.size()
	var line := String(lines[i])
	line_index = (i + 1) % lines.size()
	talks += 1
	_bow = 1.0
	Events.say.emit(Layout.VELOUR_NAME, line, 6.5)
	spoke.emit(i)
	return line


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Figure"
	add_child(_body)
	var velvet := Mat.outlined(Mat.toon(VELVET, {"rim": 0.55, "noise": 0.1}), 0.016)
	var lining := Mat.toon(LINING, {"rim": 0.4})
	var mask := Mat.outlined(Mat.toon(MASK, {"rim": 0.5}), 0.012)
	var skin := Mat.outlined(Mat.toon(SKIN, {"rim": 0.45}), 0.012)
	var gold := Mat.toon(GOLD, {"rim": 0.6, "specular": 0.45})
	var glove := Mat.toon(GLOVE, {"rim": 0.3})
	_cape = Node3D.new()
	_cape.name = "Cape"
	_body.add_child(_cape)
	Kit.add(_cape, Kit.cylinder(0.2, 0.62, 1.15, velvet, 16), Vector3(0, 0.62, 0))
	Kit.add(_cape, Kit.cylinder(0.18, 0.5, 1.0, lining, 14), Vector3(0, 0.6, 0.12))
	for s in [-1.0, 1.0]:
		Kit.add(_cape, Kit.sphere(0.22, velvet, 8, 12), Vector3(float(s) * 0.45, 0.2, 0.0), Vector3.ZERO, Vector3(0.7, 0.5, 0.9))
	# Flamboyant collar: two tall fans behind the head + the golden neck ring (his tell in the fight).
	for s in [-1.0, 1.0]:
		Kit.add(_body, Kit.sphere(0.3, velvet, 10, 12), Vector3(float(s) * 0.22, 1.42, -0.1), Vector3(0, 0, float(s) * -18.0), Vector3(0.9, 1.25, 0.18))
		Kit.add(_body, Kit.sphere(0.26, lining, 10, 12), Vector3(float(s) * 0.21, 1.41, -0.07), Vector3(0, 0, float(s) * -18.0), Vector3(0.8, 1.1, 0.1))
	Kit.add(_body, Kit.torus(0.16, 0.22, gold), Vector3(0, 1.22, 0))
	# Head, bat mask, ears and the tiny crown.
	Kit.add(_body, Kit.sphere(0.25, skin, 12, 16), Vector3(0, 1.5, 0.02))
	Kit.add(_body, Kit.sphere(0.2, mask, 8, 12), Vector3(0, 1.55, 0.14), Vector3.ZERO, Vector3(1.45, 0.55, 0.6))
	for s in [-1.0, 1.0]:
		Kit.add(_body, Kit.sphere(0.12, mask, 8, 10), Vector3(float(s) * 0.27, 1.6, 0.1), Vector3(0, 0, float(s) * -25.0), Vector3(1.4, 0.6, 0.3))
		Kit.add(_body, Kit.sphere(0.035, Mat.glow(Color("ffd27a"), 2.0), 6, 8), Vector3(float(s) * 0.085, 1.56, 0.25))
		Kit.add(_body, Kit.cone(0.08, 0.22, mask, 8), Vector3(float(s) * 0.15, 1.78, 0.0), Vector3(0, 0, float(s) * -15.0))
	Kit.add(_body, Kit.cylinder(0.1, 0.09, 0.08, gold, 10), Vector3(0.04, 1.8, 0.02), Vector3(0, 0, -12))
	for k in 5:
		var a := TAU * float(k) / 5.0
		Kit.add(_body, Kit.cone(0.025, 0.08, gold, 6), Vector3(0.04 + cos(a) * 0.085, 1.87, 0.02 + sin(a) * 0.085), Vector3(0, 0, -12))
	Kit.add(_body, Kit.sphere(0.03, Mat.glow(Color("ff6f9a"), 1.6), 6, 8), Vector3(0.04, 1.84, 0.12))
	# Little gloved hands, one on his heart.
	Kit.add(_body, Kit.sphere(0.08, glove, 8, 10), Vector3(-0.12, 1.02, 0.3))
	Kit.add(_body, Kit.sphere(0.08, glove, 8, 10), Vector3(0.3, 0.9, 0.2))
	var l := OmniLight3D.new()
	l.name = "ResidentGlow"
	l.light_color = Color("ffb0c8")
	l.light_energy = 0.4
	l.omni_range = 2.5
	l.shadow_enabled = false
	l.position = Vector3(0, 1.6, 0.8)
	add_child(l)
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.1
	cs.shape = sph
	cs.position = Vector3(0, 1.4, 0)
	ib.add_child(cs)
	add_child(ib)


func _process(delta: float) -> void:
	_t += delta
	_bow = maxf(_bow - delta * 0.8, 0.0)
	if _body != null:
		_body.position.y = 0.55 + sin(_t * 1.6) * 0.08
		_body.rotation.x = -sin(_bow * PI) * 0.45
		_cape.rotation.z = sin(_t * 1.1) * 0.05
		_cape.scale = Vector3(1.0 + sin(_t * 2.0) * 0.03, 1.0, 1.0)

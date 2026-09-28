extends Node3D
## A light fixture in The Below: miner's lantern (hanging / wall / post / floor / dropped), a ruin
## fire-bowl, or a bare glow. Group "flicker_light": flicker(seconds) makes it stutter for a while
## (horror director), then it recovers. The lamp applies the "reduce_flashing" setting itself: with it
## on, the stutter becomes one slow dip to ~55 % and back (like the runner's gentle dim for plain
## lights). A gentle idle shimmer keeps flames alive.
##   var l = Lamp.new(); l.setup({"style": "hanging", "color": Palette.MINE_LIGHT, "energy": 1.6, "range": 7.0})

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const IRON := Color("3b3238")
const GENTLE_DEPTH := 0.45         # reduce_flashing: the flicker dims to 55 % at most
const GENTLE_IN := 0.5             # seconds to ease down into the dip
const GENTLE_OUT := 0.8            # seconds to ease back up (finishes as the flicker ends)

var style: String = "hanging"      # hanging | wall | post | floor | dropped | bowl | none
var color: Color = Palette.MINE_LIGHT
var energy: float = 1.6
var light_range: float = 7.0
var shadow: bool = false
var idle_flicker: float = 0.07
var fog_energy: float = 0.3
var hang: float = 0.8              # chain length for hanging lanterns
var flame_color: Color = Palette.LANTERN_GLOW
var light: OmniLight3D
var dim_mult: float = 1.0          # set by the area (darkness / story state)

var _flame: Node3D
var _flicker_left: float = 0.0
var _dip: float = 0.0              # 0..1 depth of the reduce_flashing dip (rate-limited: never jumps)
var _t: float = 0.0
var _flame_base: Vector3 = Vector3.ONE


func setup(p: Dictionary) -> void:
	style = String(p.get("style", style))
	color = p.get("color", color)
	energy = float(p.get("energy", energy))
	light_range = float(p.get("range", light_range))
	shadow = bool(p.get("shadow", shadow))
	idle_flicker = float(p.get("idle", idle_flicker))
	fog_energy = float(p.get("fog", fog_energy))
	hang = float(p.get("hang", hang))
	flame_color = p.get("flame", flame_color)


func _ready() -> void:
	add_to_group("flicker_light")
	var light_pos := _build_visual()
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.1
	light.shadow_enabled = shadow
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 1.5
	light.light_volumetric_fog_energy = fog_energy
	light.distance_fade_enabled = true
	light.distance_fade_begin = 34.0
	light.distance_fade_length = 10.0
	light.distance_fade_shadow = 22.0
	light.light_specular = 0.35
	add_child(light)
	light.position = light_pos
	_t = randf() * 20.0


func _build_visual() -> Vector3:
	var flame_mat := Mat.glow(flame_color, 3.0)
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.4}), 0.012)
	match style:
		"hanging", "wall", "post", "floor", "dropped":
			var lantern := Node3D.new()
			add_child(lantern)
			var base_y := 0.0
			if style == "hanging":
				base_y = -hang - 0.36
				Kit.add(self, Kit.cylinder(0.012, 0.012, hang, iron, 6), Vector3(0, -hang * 0.5, 0))
			elif style == "wall":
				Kit.add(self, Kit.box(Vector3(0.06, 0.06, 0.5), iron), Vector3(0, 0.1, 0.22))
				Kit.add(self, Kit.box(Vector3(0.1, 0.22, 0.04), iron), Vector3(0, 0.02, 0.02))
				base_y = -0.32
				lantern.position.z = 0.44
			elif style == "post":
				var wood := Mat.outlined(Mat.toon(Palette.MINE_TIMBER), 0.015)
				Kit.add(self, Kit.box(Vector3(0.16, 1.9, 0.16), wood), Vector3(0, 0.95, 0))
				Kit.add(self, Kit.box(Vector3(0.1, 0.1, 0.55), wood), Vector3(0, 1.8, 0.22))
				Kit.add(self, Kit.cylinder(0.01, 0.01, 0.2, iron, 6), Vector3(0, 1.68, 0.44))
				base_y = 1.2
				lantern.position.z = 0.44
			elif style == "dropped":
				lantern.rotation_degrees = Vector3(0, 30, 82)
				base_y = 0.0
				lantern.position = Vector3(0.0, 0.14, 0.0)
			lantern.position.y += base_y
			_lantern_mesh(lantern, iron, flame_mat)
			return lantern.position + Vector3(0, 0.18, 0) if style != "dropped" else Vector3(0.0, 0.2, 0.0)
		"bowl":
			var stone := Mat.toon(Palette.RUIN_STONE_DARK, {"rim": 0.3})
			Kit.add(self, Kit.cylinder(0.22, 0.3, 0.8, stone, 10), Vector3(0, 0.4, 0))
			Kit.add(self, Kit.cylinder(0.42, 0.24, 0.26, stone, 12), Vector3(0, 0.93, 0))
			Kit.add(self, Kit.torus(0.34, 0.46, stone), Vector3(0, 1.05, 0))
			_flame = Node3D.new()
			add_child(_flame)
			_flame.position = Vector3(0, 1.08, 0)
			Kit.add(_flame, Kit.sphere(0.2, flame_mat, 8, 10), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
			Kit.add(_flame, Kit.cone(0.13, 0.42, flame_mat, 8), Vector3(0, 0.3, 0))
			_flame_base = _flame.scale
			return Vector3(0, 1.5, 0)
		"glow":
			_flame = Kit.add(self, Kit.sphere(0.07, flame_mat, 6, 8), Vector3.ZERO)
			_flame_base = _flame.scale
	return Vector3.ZERO


func _lantern_mesh(lantern: Node3D, iron: Material, flame_mat: Material) -> void:
	Kit.add(lantern, Kit.cylinder(0.13, 0.15, 0.05, iron, 10), Vector3(0, 0.0, 0))
	Kit.add(lantern, Kit.cone(0.15, 0.12, iron, 10), Vector3(0, 0.36, 0))
	Kit.add(lantern, Kit.torus(0.02, 0.05, iron), Vector3(0, 0.45, 0), Vector3(90, 0, 0))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		Kit.add(lantern, Kit.box(Vector3(0.025, 0.3, 0.025), iron), Vector3(cos(a) * 0.11, 0.17, sin(a) * 0.11))
	var glass := Mat.transparent(Color(flame_color.r, flame_color.g, flame_color.b, 0.35), true)
	Kit.add(lantern, Kit.cylinder(0.1, 0.1, 0.28, glass, 10), Vector3(0, 0.17, 0))
	_flame = Node3D.new()
	lantern.add_child(_flame)
	_flame.position = Vector3(0, 0.14, 0)
	Kit.add(_flame, Kit.sphere(0.05, flame_mat, 6, 8), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.5, 1.0))
	_flame_base = _flame.scale


func _process(delta: float) -> void:
	if light == null:
		return
	_t += delta
	var e := energy
	if idle_flicker > 0.0:
		e *= 1.0 + (sin(_t * 7.3) * 0.5 + sin(_t * 12.7 + 1.3) * 0.3 + sin(_t * 23.1 + 0.4) * 0.2) * idle_flicker
	var gentle := false
	if _flicker_left > 0.0:
		_flicker_left -= delta
		# Read live so turning the option on mid-flicker calms it at once.
		gentle = bool(Settings.get_value("reduce_flashing"))
		if not gentle:
			var ph := fmod(_t * 9.0 + sin(_t * 3.1) * 2.0, 1.0)
			if ph < 0.3:
				e *= 0.08
			elif ph < 0.55:
				e *= 0.5
			elif ph < 0.62:
				e *= 0.02
	# Reduce flashing: one slow dip instead of the stutter (eases down, holds, eases back up by the end).
	var want := 1.0 if gentle and _flicker_left > GENTLE_OUT else 0.0
	if _dip != want:
		_dip = move_toward(_dip, want, delta / (GENTLE_IN if want > _dip else GENTLE_OUT))
	if _dip > 0.0:
		e *= 1.0 - GENTLE_DEPTH * smoothstep(0.0, 1.0, _dip)
	light.light_energy = e * dim_mult
	if _flame != null:
		var k := clampf(e / maxf(energy, 0.001), 0.05, 1.3)
		_flame.scale = _flame_base * (0.55 + 0.45 * k)
		_flame.visible = dim_mult > 0.05


## Horror director hook: stutter for `seconds`, then recover (one slow dip with reduce_flashing on).
func flicker(seconds: float) -> void:
	_flicker_left = maxf(_flicker_left, seconds)


func is_flickering() -> bool:
	return _flicker_left > 0.0

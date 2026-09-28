extends RefCounted
## Shared art + settings helpers for the deep Works (rooms 9-14). Static only; materials and meshes come
## from Mat / Kit (cached), so every node here shares them.
##   const Art := preload("res://src/world/works/deep/deep_art.gd")
##   Art.bold_ring(parent, 1.2)            high-visibility floor ring (outlined, never colour alone)
##   Art.symbol(parent, "moon", 0.9)       a large readable bell symbol (moon / leaf / bell / star / flame...)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HorrorData := preload("res://data/horror_events.gd")

# Room palettes (materials and light temperature differ per room: MP §10 "distinct places").
const IRON := Color("3a3034")
const IRON_RUST := Color("6b4a3c")
const TIMBER := Color("7a5236")
const TIMBER_DARK := Color("5a3b27")
const PLATE := Color("5a5052")
const SLATE := Color("4a5566")
const SLATE_DARK := Color("2e3644")
const DECK := Color("8a6a4a")
const TILE := Color("c9d2c4")
const TILE_DARK := Color("8fa596")
const GREEN_IRON := Color("4f6e5c")
const GREEN_WALL := Color("5e7a68")
const VIOLET_ROCK := Color("3a3044")
const VIOLET_DARK := Color("2e2638")
const SAND := Color("b89a70")
const SAND_DARK := Color("8a7050")
const BRASS := Color("c89a4a")
const PALE := Color("c8c0cc")
const PALE_DARK := Color("9a92a4")
const WARM_BAND := Color("d8c8a8")
const CREAM := Color("efe0c4")
const PLUM := Color("6a4a6e")
const PUMPKIN := Color("f08a2e")
const RIBBONS := [Color("e4665c"), Color("f2c14e"), Color("b48ad8"), Color("6fae4f"), Color("f28bb0")]

const HV_COLOR := Color("fff1c8")
const SYMBOL_DARK := Color(0.12, 0.09, 0.12)
const HV_OUTLINE := Color(0.08, 0.05, 0.1)


static func arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))


static func high_visibility() -> bool:
	return bool(Settings.get_value("high_visibility_cues"))


static func timing_assist() -> bool:
	return bool(Settings.get_value("timing_assist"))


## 0 Gentle, 1 Standard, 2 Intense.
static func intensity() -> int:
	return clampi(int(Settings.get_value("horror_intensity")), 0, HorrorData.INTENSITY.size() - 1)


static func captions_on() -> bool:
	return bool(Settings.get_value("captions"))


## Bold, outlined floor ring used by the high_visibility_cues option (shape + outline, not colour alone).
static func bold_ring(parent: Node3D, radius: float, color: Color = HV_COLOR, y: float = 0.04) -> MeshInstance3D:
	var mat := Mat.outlined(Mat.toon(color, {"emission": color, "emission_energy": 0.8, "rim": 0.2}), 0.05, HV_OUTLINE)
	var ring := Kit.torus(radius - 0.09, radius + 0.09, mat)
	Kit.add(parent, ring, Vector3(0.0, y, 0.0), Vector3.ZERO, Vector3(1.0, 0.35, 1.0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.name = "HvRing"
	return ring


## A bold vertical frame around an opening/panel (width x height, centred on local x, from y 0).
static func bold_frame(parent: Node3D, width: float, height: float, color: Color = HV_COLOR) -> Node3D:
	var n := Node3D.new()
	n.name = "HvFrame"
	parent.add_child(n)
	var mat := Mat.outlined(Mat.toon(color, {"emission": color, "emission_energy": 0.7}), 0.04, HV_OUTLINE)
	for sx in [-1.0, 1.0]:
		Kit.add(n, Kit.box(Vector3(0.1, height, 0.1), mat), Vector3(sx * width * 0.5, height * 0.5, 0.0))
	Kit.add(n, Kit.box(Vector3(width, 0.1, 0.1), mat), Vector3(0.0, height, 0.0))
	return n


static func label(parent: Node3D, text: String, pos: Vector3, size: int = 48, color: Color = Color(1.0, 0.95, 0.85, 0.95), billboard: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.008
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0.08, 0.05, 0.08, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	# An authored sign is read from its front only: seen from behind, a double-sided label shows mirrored
	# letters through / past its board (VISUAL_BUGS IN-08). A caller that mirrors a label on purpose (scale.x < 0,
	# the false lift's backwards sign) must set double_sided back to true: a mirrored single-sided label is culled
	# from the front.
	l.double_sided = billboard
	l.position = pos
	parent.add_child(l)
	return l


## Width in metres a label's text takes on screen (font + outline, at its pixel size).
static func label_width(l: Label3D) -> float:
	var f: Font = l.font if l.font != null else ThemeDB.fallback_font
	var w := 0.0
	for line in l.text.split("\n"):
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x)
	return (w + float(l.outline_size)) * l.pixel_size


## Shrinks a label's font until its text fits inside `max_width` metres (its board). Returns the new width.
static func fit_label(l: Label3D, max_width: float) -> float:
	var w := label_width(l)
	while w > max_width and l.font_size > 8:
		l.font_size = maxi(int(floorf(float(l.font_size) * max_width / w)), 8) if w > max_width * 1.05 else l.font_size - 1
		w = label_width(l)
	return w


## A large readable symbol plate shape (+ its name as a label below it, never colour alone). Faces +z.
## Known ids: moon, leaf, bell, star, flame, key, heart; anything else shows its first letter.
## `backdrop`: the colour of whatever the symbol is painted on - the Moon's "bite" uses it, so on a light board
## the crescent reads as a crescent instead of a black hole (VISUAL_BUGS IN-11). Default: a dark plate.
static func symbol(parent: Node3D, symbol_id: String, size: float, color: Color, display_name: String = "", backdrop: Color = SYMBOL_DARK) -> Node3D:
	var n := Node3D.new()
	n.name = "Symbol_" + symbol_id
	parent.add_child(n)
	var mat := Mat.outlined(Mat.toon(color, {"emission": color, "emission_energy": 0.35, "rim": 0.4}), 0.03)
	var dark := Mat.toon(SYMBOL_DARK)
	var bite: Material = dark if backdrop == SYMBOL_DARK else Mat.toon(backdrop, {"emission": backdrop, "emission_energy": 0.12, "rim": 0.0, "noise": 0.0})
	match symbol_id:
		"moon":
			Kit.add(n, Kit.cylinder(size * 0.5, size * 0.5, 0.06, mat, 24), Vector3.ZERO, Vector3(90, 0, 0))
			Kit.add(n, Kit.cylinder(size * 0.42, size * 0.42, 0.08, bite, 24), Vector3(size * 0.22, size * 0.08, 0.02), Vector3(90, 0, 0))
		"leaf":
			Kit.add(n, Kit.sphere(size * 0.5, mat, 10, 14), Vector3.ZERO, Vector3(0, 0, 35), Vector3(0.55, 1.0, 0.12))
			Kit.add(n, Kit.box(Vector3(0.05, size * 0.95, 0.05), dark), Vector3(0, 0, 0.07), Vector3(0, 0, 35))
		"bell":
			Kit.add(n, Kit.cylinder(size * 0.18, size * 0.46, size * 0.7, mat, 16), Vector3(0, size * 0.05, 0))
			Kit.add(n, Kit.sphere(size * 0.12, mat, 8, 10), Vector3(0, -size * 0.38, 0))
			Kit.add(n, Kit.torus(size * 0.06, size * 0.13, mat), Vector3(0, size * 0.47, 0), Vector3(90, 0, 0))
		"star":
			for i in 5:
				Kit.add(n, Kit.box(Vector3(size * 0.16, size * 0.52, 0.06), mat), Vector3(0, 0, 0), Vector3(0, 0, float(i) * 72.0)).translate_object_local(Vector3(0, size * 0.22, 0))
		"flame":
			Kit.add(n, Kit.cone(size * 0.34, size * 0.8, mat, 12), Vector3(0, size * 0.1, 0))
			Kit.add(n, Kit.sphere(size * 0.3, mat, 8, 10), Vector3(0, -size * 0.22, 0))
		"heart":
			for sx in [-1.0, 1.0]:
				Kit.add(n, Kit.sphere(size * 0.26, mat, 8, 10), Vector3(sx * size * 0.18, size * 0.1, 0), Vector3.ZERO, Vector3(1, 1, 0.3))
			Kit.add(n, Kit.box(Vector3(size * 0.46, size * 0.46, 0.08), mat), Vector3(0, -size * 0.12, 0), Vector3(0, 0, 45))
		"key":
			Kit.add(n, Kit.torus(size * 0.12, size * 0.24, mat), Vector3(0, size * 0.25, 0), Vector3(90, 0, 0))
			Kit.add(n, Kit.box(Vector3(0.08, size * 0.6, 0.06), mat), Vector3(0, -size * 0.12, 0))
			Kit.add(n, Kit.box(Vector3(size * 0.2, 0.08, 0.06), mat), Vector3(size * 0.08, -size * 0.36, 0))
		_:
			var l := label(n, symbol_id.substr(0, 1).to_upper(), Vector3.ZERO, 180, color)
			l.pixel_size = 0.01
	var nm := display_name if display_name != "" else symbol_id.capitalize()
	var tag := label(n, nm, Vector3(0, -size * 0.72, 0.05), 40)
	tag.name = "Name"
	return n


## One-shot drifting dust (the "Scratching Above" tell). Frees itself. No light.
static func dust(parent: Node, pos: Vector3, amount: int = 24) -> CPUParticles3D:
	if parent == null or not is_instance_valid(parent) or not (parent as Node).is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.name = "Dust"
	p.one_shot = true
	p.amount = amount
	p.lifetime = 2.6
	p.explosiveness = 0.5
	p.randomness = 0.5
	p.mesh = _dust_mesh()
	p.material_override = Mat.toon(Palette.DIRT, {"rim": 0.1, "noise": 0.0})
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.8, 0.05, 0.4)
	p.direction = Vector3.DOWN
	p.spread = 18.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0.0, -1.1, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static var _dust: SphereMesh


static func _dust_mesh() -> SphereMesh:
	if _dust == null:
		_dust = SphereMesh.new()
		_dust.radius = 0.022
		_dust.height = 0.044
		_dust.radial_segments = 6
		_dust.rings = 3
	return _dust


## Sets `disabled` on every CollisionShape3D under `n` (deferred: safe inside physics callbacks).
static func set_collision(n: Node, enabled: bool) -> void:
	if n == null:
		return
	if n is CollisionShape3D:
		(n as CollisionShape3D).set_deferred("disabled", not enabled)
	for c in n.get_children():
		set_collision(c, enabled)


## The player the deep rooms react to: an explicit override (tests) or Game.player.
static func player_or(override_node: Node3D) -> Node3D:
	if override_node != null and is_instance_valid(override_node):
		return override_node
	var p: Variant = Game.player
	if p is Node3D and is_instance_valid(p) and (p as Node3D).is_inside_tree():
		return p
	return null


static func lantern_raised(p: Node) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	var v: Variant = p.get("lantern_on")
	return v is bool and v


## Director helpers: through the Works area's API when it has one (director_suppress / director_hold /
## director_release / set_fight), else straight to Game.director (null-safe everywhere).
static func director_suppress(area: Node, seconds: float) -> void:
	if area != null and is_instance_valid(area) and area.has_method("director_suppress"):
		area.call("director_suppress", seconds)
		return
	var d: Variant = Game.director
	if d is Node and is_instance_valid(d) and (d as Node).has_method("suppress"):
		(d as Node).call("suppress", seconds)


static func director_hold(area: Node, hold_id: String) -> void:
	if area != null and is_instance_valid(area) and area.has_method("director_hold"):
		area.call("director_hold", hold_id)
	else:
		director_suppress(area, 10.0)


static func director_release(area: Node, hold_id: String) -> void:
	if area != null and is_instance_valid(area) and area.has_method("director_release"):
		area.call("director_release", hold_id)


## Adds a safe circle through whatever the area offers (below_world-style add_safe_area(center, r, zone),
## the Works area's 2-argument add_safe_area, the placeholder's add_safe_spot, else a safe zone circle).
static func add_safe(area: Node, center: Vector3, radius: float, zone: String) -> void:
	if area == null or not is_instance_valid(area):
		return
	if area.has_method("add_safe_area"):
		if area.get_method_argument_count("add_safe_area") >= 3:
			area.call("add_safe_area", center, radius, zone)
		else:
			area.call("add_safe_area", center, radius)
	elif area.has_method("add_safe_spot"):
		area.call("add_safe_spot", center, radius)
	elif area.has_method("add_zone"):
		area.call("add_zone", zone, center, radius, true)


## Boss fight on/off: area.set_fight (fight_active for Game.boss_active + a director hold) or a plain hold.
static func set_fight(area: Node, boss_id: String, active: bool) -> void:
	if area != null and is_instance_valid(area) and area.has_method("set_fight"):
		area.call("set_fight", boss_id, active)
		return
	director_suppress(area, 9999.0 if active else 20.0)


static func say(text: String, seconds: float = 5.0, speaker: String = "") -> void:
	Events.say.emit(speaker, text, seconds)


static func caption(text: String) -> void:
	if text != "":
		Events.caption.emit(text)


static func sfx3d(sound: String, pos: Vector3, db: float = 0.0) -> void:
	if Audio.has_method("has_sound") and not Audio.has_sound(sound):
		return
	Audio.play_3d(sound, pos, db)

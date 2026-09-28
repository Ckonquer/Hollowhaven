extends Node3D
## The hanging thread the Matron lowers onto a brazier while she tries to smother it (phase 3;
## arachnophobia: a pale root tether). A clearly visible line from her body down to the bowl with a
## glowing knot at reachable height: striking the knot (any attack: health 1, group "enemy") snaps the
## thread and interrupts the channel. The boss updates both ends every tick (no allocations).
##   var th = BossThread.new(); th.setup({"alt": false}); field.add_child(th); th.set_ends(top, bottom)

signal snapped(source: Node)

const Art := preload("res://src/enemies/boss_hazards/hazard_art.gd")
const Health := preload("res://src/combat/health.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")

const AIM_HEIGHT := 1.9          # above the floor: inside every melee reach from the floor

var kind := "thread"
var alt := false
var top := Vector3.ZERO
var bottom := Vector3.ZERO
var floor_y: float = 0.0
var health: Node
var hit_radius: float = 0.5
var hit_color := Art.SILK
var cut := false

var high_vis := false             # Settings "high_visibility_cues" (the field toggles it live)

var _mi: MeshInstance3D
var _knot: MeshInstance3D
var _bold: MeshInstance3D         # bold collar round the knot (high_vis)
var _t: float = 0.0


func setup(p: Dictionary) -> void:
	alt = bool(p.get("alt", alt))
	floor_y = float(p.get("floor_y", floor_y))
	hit_color = Art.ROOT if alt else Art.SILK


func _ready() -> void:
	top_level = true
	add_to_group("enemy")
	health = Health.new()
	health.name = "Health"
	health.max_hp = 1.0
	add_child(health)
	health.damaged.connect(_on_damaged)
	high_vis = Art.high_vis()
	_build()


# --- Combat contract -------------------------------------------------------------------------------------

## Krystal and her companions may both strike the thread.
func can_be_hit_by(_source: Node) -> bool:
	return not cut


func is_threatening() -> bool:
	return false


## The knot: where the thread passes AIM_HEIGHT above the floor (clamped onto the thread).
func get_aim_point() -> Vector3:
	var d := top - bottom
	if absf(d.y) < 0.01:
		return bottom
	var k := clampf((floor_y + AIM_HEIGHT - bottom.y) / d.y, 0.0, 1.0)
	return bottom + d * k


func hit_flash(_d: float = 0.1) -> void:
	pass


func knockback(_dir: Vector3, _force: float) -> void:
	pass


func _on_damaged(_amount: float, source: Node, _dir: Vector3) -> void:
	if cut:
		return
	cut = true
	remove_from_group("enemy")
	_apply_high_vis()
	Audio.play_3d("dir_root_creak" if alt else "dir_web_rustle", get_aim_point(), -2.0, 0.1, 30.0)
	snapped.emit(source)


# --- Placement ---------------------------------------------------------------------------------------------

func set_ends(p_top: Vector3, p_bottom: Vector3) -> void:
	top = p_top
	bottom = p_bottom
	if not is_inside_tree():
		return
	global_position = get_aim_point()
	if _mi != null:
		Art.place_line(_mi, top, bottom, 0.035 if alt else 0.022)
	if _knot != null:
		_knot.global_position = get_aim_point()
	if _bold != null:
		_bold.global_position = get_aim_point()


## Settings "high_visibility_cues": a bold collar round the knot (where to strike) until it snaps.
func set_high_vis(on: bool) -> void:
	high_vis = on
	_apply_high_vis()


func bold_visible() -> bool:
	return _bold != null and is_instance_valid(_bold) and _bold.visible


func _apply_high_vis() -> void:
	if _bold != null and is_instance_valid(_bold):
		_bold.visible = high_vis and not cut


func tick(delta: float) -> void:
	_t += delta
	if _knot != null:
		_knot.scale = Vector3.ONE * (1.0 if bool(Settings.get_value("reduce_flashing")) else 0.85 + 0.3 * (0.5 + 0.5 * sin(_t * 6.0)))


func set_alt(on: bool) -> void:
	if on == alt:
		return
	alt = on
	hit_color = Art.ROOT if alt else Art.SILK
	for c in get_children():
		if c != health:
			c.queue_free()
	_mi = null
	_knot = null
	_bold = null
	_build()
	set_ends(top, bottom)


func _build() -> void:
	_mi = Art.line(self, Art.strand_mat(alt))
	_knot = Kit.sphere(0.13, Mat.glow(Art.ROOT if alt else Art.SILK, 1.6), 8, 10)
	_knot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_knot)
	_bold = Kit.torus(0.24, 0.31, Art.bold_mat())
	_bold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bold)
	_apply_high_vis()

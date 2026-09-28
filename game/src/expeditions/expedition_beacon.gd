extends Node3D
## The ribbon lantern that marks the current expedition stop (or the cache) in Hallowmere Reach (module D2):
## a festival pole with a warm lantern, two ribbons and a soft, tall light column so it can be found from the
## roads. Decoration only (no collision, not interactable, never an enemy). Comfort: the column never pulses
## or flashes; only the little lantern bobs (and not at all with Settings "reduce_flashing"). One small
## shadowless light. Built from shared Mat / Kit resources.
##   var b = Beacon.new(); add_child(b); b.place(ground_pos, "stop" | "cache")

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")

const POLE_HEIGHT := 2.7
const COLUMN_HEIGHT := 18.0
const COLORS := {"stop": Color(1.0, 0.72, 0.52), "cache": Color(1.0, 0.86, 0.48)}

var kind: String = "stop"
var lantern: Node3D
var column: MeshInstance3D
var light: OmniLight3D
var _t: float = 0.0
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var pole := Kit.cylinder(0.06, 0.08, POLE_HEIGHT, Mat.outlined(Mat.toon(Palette.WOOD_DARK), 0.02))
	Kit.add(self, pole, Vector3(0, POLE_HEIGHT * 0.5, 0))
	var arm := Kit.box(Vector3(0.5, 0.06, 0.06), Mat.toon(Palette.WOOD_DARK))
	Kit.add(self, arm, Vector3(0.2, POLE_HEIGHT - 0.1, 0))
	lantern = Node3D.new()
	lantern.name = "Lantern"
	add_child(lantern)
	lantern.position = Vector3(0.4, POLE_HEIGHT - 0.42, 0)
	Kit.add(lantern, Kit.cylinder(0.12, 0.16, 0.08, Mat.toon(Palette.COPPER)), Vector3(0, 0.2, 0))
	Kit.add(lantern, Kit.sphere(0.15, Mat.glow(Palette.LANTERN_GLOW, 2.4), 10, 14), Vector3.ZERO)
	Kit.add(lantern, Kit.cylinder(0.14, 0.1, 0.06, Mat.toon(Palette.COPPER)), Vector3(0, -0.17, 0))
	for i in 2:
		var ribbon := Kit.box(Vector3(0.07, 0.8, 0.015), Mat.toon(Palette.CLOTH_RED if i == 0 else Palette.FLOWER_PURPLE))
		Kit.add(self, ribbon, Vector3(-0.07 + 0.14 * float(i), POLE_HEIGHT - 0.55, 0.07), Vector3(0, 0, -8.0 + 16.0 * float(i)))
	column = Kit.cylinder(0.3, 0.55, COLUMN_HEIGHT, Mat.transparent(Color(1.0, 0.8, 0.55, 0.12), true), 12)
	column.name = "LightColumn"
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(self, column, Vector3(0, COLUMN_HEIGHT * 0.5 + 0.4, 0))
	light = OmniLight3D.new()
	light.shadow_enabled = false
	light.omni_range = 6.0
	light.light_energy = 1.1
	light.light_color = Palette.LANTERN_GLOW
	light.position = lantern.position
	add_child(light)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_kind()


## Moves the lantern to `pos` (ground) and styles it for a "stop" or the "cache".
func place(pos: Vector3, p_kind: String = "stop") -> void:
	kind = p_kind
	_build()
	if is_inside_tree():
		global_position = pos
	else:
		position = pos
	_apply_kind()


func _apply_kind() -> void:
	if column == null:
		return
	var c: Color = COLORS.get(kind, COLORS["stop"])
	column.material_override = Mat.transparent(Color(c.r, c.g, c.b, 0.12), true)
	light.light_color = c


func _process(delta: float) -> void:
	if lantern == null or bool(Settings.get_value("reduce_flashing")):
		return
	_t += delta
	lantern.position.y = POLE_HEIGHT - 0.42 + sin(_t * 1.6) * 0.04

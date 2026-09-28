extends Node3D
## Wayfinding along the Reach roads: tall festival signposts at the Lantern Crossroads (visible from the
## arrival), at the Conservatory's north door and at the Bellhouse fork, plus a few ribboned fence runs
## and lantern-topped markers where each branch road reaches its arch. Pure decoration + collision.

const Reach := preload("res://data/hallowmere_layout.gd")
const Props := preload("res://src/world/reach/reach_props.gd")
const Mat := preload("res://src/art/mat.gd")
const Palette := preload("res://src/art/palette.gd")

## [position, [[pointing target, label, board colour], ...]]
const SIGNPOSTS := [
	[Vector2(3.6, 35.2), [[Vector2(-60, 50), "Pumpkintide Orchard", "pumpkin"], [Vector2(62, 38), "Ashbell Quarry", "red"],
		[Vector2(0, 6), "The Conservatory", "forest"], [Vector2(0, 60), "Lanternwake Commons", "mustard"]]],
	[Vector2(3.4, -5.5), [[Vector2(10, -50), "Moonveil Manor", "plum"], [Vector2(72, -74), "Sunken Bellhouse", "midnight"],
		[Vector2(-44, -8), "Thimblebrook Pools", "forest"]]],
	[Vector2(4.2, -39.8), [[Vector2(10, -50), "Moonveil Manor", "plum"], [Vector2(72, -74), "Sunken Bellhouse", "midnight"]]],
	[Vector2(-12.5, 17.8), [[Vector2(-44, 10), "Thimblebrook Pools", "forest"], [Vector2(-82, 36), "Pumpkintide Orchard", "pumpkin"]]],
]

var terrain: RefCounted
var signposts: Array = []


func _ready() -> void:
	name = "Roads"
	var body := StaticBody3D.new()
	body.name = "SignCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	add_child(body)
	for s in SIGNPOSTS:
		_signpost(body, s[0], s[1])


func _signpost(body: StaticBody3D, p: Vector2, arms: Array) -> void:
	var root := Node3D.new()
	root.name = "Signpost_%d" % signposts.size()
	add_child(root)
	root.position = Vector3(p.x, terrain.height_at(p.x, p.y) - 0.05, p.y)
	var post := Props.wood_mat()
	var mi := MeshInstance3D.new()
	mi.mesh = Props.signpost_mesh()
	mi.material_override = post
	mi.visibility_range_end = 160.0
	root.add_child(mi)
	# a lantern on top so the crossroads reads from far away
	var glass := MeshInstance3D.new()
	glass.mesh = Props.lantern_glass_mesh()
	glass.material_override = Mat.glow(Color("ffc66e"), 2.0)
	glass.position = Vector3(0, 3.95, 0)
	glass.scale = Vector3.ONE * 1.3
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	for i in arms.size():
		var arm: Array = arms[i]
		var target: Vector2 = arm[0]
		var d := target - p
		var yaw := atan2(-d.y, d.x)          # local +X toward the target
		var holder := Node3D.new()
		holder.position = Vector3(0, 3.1 - float(i) * 0.46, 0)
		holder.rotation.y = yaw
		root.add_child(holder)
		var col: Color = Props.CLOTH.get(String(arm[2]), Palette.WOOD)
		var board := MeshInstance3D.new()
		board.mesh = Props.sign_arm_mesh(col.lerp(Palette.WOOD_LIGHT, 0.35))
		board.material_override = post
		holder.add_child(board)
		for side in [0, 1]:
			var z := 0.045 if side == 0 else -0.045
			var l := Props.label(holder, String(arm[1]), Vector3(0.78, 0.0, z), 34, Color("3b2a22"), 0.0 if side == 0 else PI, 0.0036)
			l.width = 340.0
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
	Props.cyl_col(body, root.position, 0.16, 3.6)
	signposts.append(root)

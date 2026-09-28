extends "res://src/world/areas_ch2/placeholder_area.gd"
## PLACEHOLDER Hallowmere Reach (area "hallowmere_reach", docs/CHAPTER_TWO_SPEC.md §1, §7.2). A flat
## autumn-coloured floor over the whole 280 x 220 m extent, the eight landmark zones as flat discs, the
## five Lantern Road arches, the mirror waygate home and placeholder doors to the Manor, the Bellhouse
## stair and the refuge shortcut. EVERY coordinate comes from data/hallowmere_layout.gd so wave C's real
## Reach (terrain, paths, festival) lines up with saves made on this stand-in.
## Safe: the Commons and the Conservatory (zones), every arch and the waygate arrival (safe spots).
## Outdoor area: Game resumes Continue at the saved position here (validate_position).

const Reach := preload("res://data/hallowmere_layout.gd")
const WaygateScript := preload("res://src/world/surface/waygate.gd")
const ArchScript := preload("res://src/world/common/lantern_arch.gd")

const LANDMARK_COLORS := {
	"hr_commons": Color("e0a45c"), "hr_conservatory": Color("9fbf7a"), "hr_orchard": Color("d9822f"),
	"hr_pools": Color("6fa9b8"), "hr_candleyard": Color("7d6a9a"), "hr_quarry": Color("b8674a"),
	"hr_manor_grounds": Color("6e4a6a"), "hr_bellhouse": Color("5f6f7a"),
}

var arches: Dictionary = {}       # arch id -> lantern_arch node
var waygate: Node3D = null


func _ready() -> void:
	area_id = Reach.AREA_ID
	ambience = "amb_forest_day"
	bounds = Rect2(-Reach.HALF_X, -Reach.HALF_Z, Reach.HALF_X * 2.0, Reach.HALF_Z * 2.0)
	build_environment({"bg": Color("5a3f5c"), "ambient": Color("c9a38a"), "ambient_energy": 0.55,
		"sun": true, "sun_color": Color("ffc98a"), "sun_energy": 1.05, "sun_pitch": -38.0, "sun_yaw": 140.0,
		"fog": true, "fog_color": Color("7a5a6e"), "fog_density": 0.004})
	add_ground(bounds, floor_y, Color("a8703f"), "grass")
	add_walls(bounds.grow(-1.0), floor_y, 12.0)
	add_label("PLACEHOLDER - Hallowmere Reach (wave C builds the real region)", Vector3(0, 6.0, 90), 96)
	for id in Reach.LANDMARKS:
		var l: Dictionary = Reach.LANDMARKS[id]
		var p: Vector2 = l["pos"]
		add_zone(String(id), Vector3(p.x, floor_y, p.y), float(l["radius"]), bool(l["safe"]))
		_disc(p, float(l["radius"]), LANDMARK_COLORS.get(id, Color("8a7a6a")))
		add_label(String(l["name"]), Vector3(p.x, floor_y + 4.0, p.y), 72)
	_register_spawns()
	_build_arches()
	_build_waygate()
	_build_exits()


func _disc(p: Vector2, r: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.04
	cm.radial_segments = 32
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = Vector3(p.x, floor_y + 0.02, p.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _register_spawns() -> void:
	for id in Reach.SPAWNS:
		var s: Dictionary = Reach.SPAWNS[id]
		var p: Vector2 = s["pos"]
		place_spawn(String(id), Vector3(p.x, height_at(p.x, p.y), p.y), Reach.yaw_towards(p, s["look"]))
	var arrival: Vector2 = Reach.POINTS["waygate_arrival"]
	add_safe_spot(Vector3(arrival.x, floor_y, arrival.y), Reach.ARRIVAL_SAFE_RADIUS)


func _build_arches() -> void:
	for id in Reach.ARCH_ORDER:
		var a: Dictionary = Reach.ARCHES[id]
		var p: Vector2 = a["pos"]
		var lm: Vector2 = Reach.LANDMARKS[String(a["landmark"])]["pos"]
		var arch: Node3D = ArchScript.new()
		arch.setup({"id": id, "area": area_id, "spawn": a["spawn"], "name": a["name"]})
		add_child(arch)
		arch.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		arch.rotation.y = Reach.yaw_towards(p, lm)
		arches[String(id)] = arch
		add_safe_spot(Vector3(p.x, floor_y, p.y), Reach.ARCH_SAFE_RADIUS)


## The Reach side of the Lanternwake waygate, just behind the arrival point: always leads home.
func _build_waygate() -> void:
	var p: Vector2 = Reach.POINTS["mirror_waygate"]
	waygate = WaygateScript.new()
	waygate.setup({"side": "reach", "target_area": "surface", "target_spawn": "waygate"})
	add_child(waygate)
	waygate.position = Vector3(p.x, height_at(p.x, p.y), p.y)
	waygate.rotation.y = 0.0


func _build_exits() -> void:
	var door: Vector2 = Reach.POINTS["manor_door"]
	add_exit("manor_door", {"text": "Enter Moonveil Manor", "target_area": "moonveil_manor", "target_spawn": "manor_entry"},
		Vector3(door.x, floor_y, door.y), 0.0)
	var stair: Vector2 = Reach.POINTS["bellhouse_stair"]
	add_exit("bellhouse_stair", {"text": "Take the Bellhouse stair down", "target_area": "hushed_works",
		"target_spawn": "service_landing", "requires_flag": "ch2_lamps_linked", "style": "stair",
		"locked_text": "The stair is sealed. Perhaps linking the three lanterns will open it."},
		Vector3(stair.x, floor_y, stair.y), 0.0)
	var hatch: Vector2 = Reach.POINTS["refuge_hatch"]
	add_exit("refuge_hatch", {"text": "Climb down to the refuge", "target_area": "hushed_works",
		"target_spawn": "refuge", "requires_flag": "ch2_refuge_shortcut", "style": "hatch",
		"locked_text": "A heavy hatch, bolted from below."},
		Vector3(hatch.x, floor_y, hatch.y), Reach.yaw_towards(hatch, Vector2(0, 6)))

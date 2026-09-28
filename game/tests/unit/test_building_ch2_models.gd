extends "res://tests/test_case.gd"
## Every Chapter Two structure has its own procedural model that builds and fits its footprint (wall-mounted
## pieces hug the back edge), the stair ramp is walkable, lazily mapped behaviour scripts load safely (a
## missing one falls back to the base structure), the Thread Veil has its arachnophobia drape, pumpkin faces
## differ, and no decoration is ever an enemy.

const Models := preload("res://src/building/structure_models.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const Storey := preload("res://src/building/models_storey.gd")
const Seasonal := preload("res://src/building/models_seasonal.gd")
const P := preload("res://src/building/placement.gd")
const AreaBase := preload("res://src/world/area_base.gd")

const LEGACY := ["workbench", "storage_chest", "bed", "crop_plot", "wood_floor", "wood_wall", "wood_window", "wood_doorway",
	"wood_roof", "fence", "lantern_post", "flower_pot", "rug", "table", "stool", "pebble_cairn", "echo_chime",
	"heartbloom_lamp", "haven_banner"]

var _area: Node3D
var _arachno: Variant = false


func before_each() -> void:
	fresh_state()
	_arachno = Settings.values.get("arachnophobia", false)
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)


func after_each() -> void:
	Settings.values["arachnophobia"] = _arachno
	if is_instance_valid(_area):
		_area.free()


func _new_ids() -> Array:
	var out: Array = []
	for sid in ItemDB.all_structure_ids():
		if not LEGACY.has(sid):
			out.append(sid)
	return out


## Bounds of every mesh under `root`, in root space.
func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := root.global_transform.affine_inverse() * mi.global_transform
		var b := xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_the_catalogue_has_every_new_piece() -> void:
	var ids := _new_ids()
	for sid in ["wood_stairs", "upper_floor", "wood_railing", "half_wall", "porch_post", "arched_window", "gable_roof", "roof_corner",
		"flower_box", "curtain", "bookshelf", "wardrobe", "vanity_mirror", "kitchen_counter", "furnace", "loom", "companion_bed",
		"companion_perch", "sturdy_planter", "cottage_bench", "pumpkin_lantern", "pumpkin_lights", "bat_bunting", "ghost_lantern",
		"crescent_window", "candy_bowl", "scarecrow", "gothic_trim", "music_box", "expedition_board", "wardlight", "miner_lamp",
		"thread_veil", "lanternwake_table"]:
		assert_true(ids.has(sid), sid + " is in data/structures.gd")


func test_every_new_structure_has_its_own_model_that_fits_its_footprint() -> void:
	var report: PackedStringArray = []
	for sid in _new_ids():
		var def := ItemDB.structure(sid)
		var root := Node3D.new()
		add_child(root)
		var parts: Dictionary = Models.build(sid, root)
		assert_true(root.get_child_count() > 0, sid + " builds a model")
		# Not the generic crate: the fallback is keyed "fallback|<id>".
		var fallback := false
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh == preload("res://src/building/model_util.gd")._cache.get("baked|fallback|" + sid):
				fallback = true
		assert_false(fallback, sid + " has its own model, not the fallback crate")
		var box := _aabb(root)
		var size: Vector2i = def.get("size", Vector2i.ONE)
		var snap := String(def.get("snap", "cell"))
		var tol := 0.36 if snap == "roof2" else 0.13
		var hx := float(size.x) * 0.5 + tol
		var hz := float(size.y) * 0.5 + tol
		assert_true(box.position.x >= -hx and box.end.x <= hx, "%s fits in x: %s" % [sid, str(box)])
		assert_true(box.position.z >= -hz and box.end.z <= hz, "%s fits in z: %s" % [sid, str(box)])
		var h := float(def.get("height", 1.0))
		var top_tol := 1.2 if sid == "wood_stairs" else 0.36
		assert_true(box.end.y <= h + top_tol, "%s is not taller than its data (%.2f > %.2f)" % [sid, box.end.y, h])
		assert_true(box.position.y >= -0.3, "%s does not sink into the ground (%.2f)" % [sid, box.position.y])
		if String(def.get("mount", "")) == "wall":
			assert_true(box.position.z <= -0.3 and box.end.z <= 0.2, "%s hugs the wall behind its cell: %s" % [sid, str(box)])
		if def.has("light"):
			assert_true(parts.has("light_pos"), sid + " says where its light sits")
		report.append("%s[%.2f..%.2f x %.2f..%.2f y %.2f..%.2f]" % [sid, box.position.x, box.end.x, box.position.z, box.end.z, box.position.y, box.end.y])
		root.free()
	print("Chapter Two model bounds: ", ", ".join(report))


func test_stairs_ramp_is_walkable_and_meets_the_landing() -> void:
	var pts := Storey.stair_collision_points()
	var top := -INF
	var zmin := INF
	var zmax := -INF
	for p in pts:
		top = maxf(top, p.y)
		zmin = minf(zmin, p.z)
		zmax = maxf(zmax, p.z)
	assert_almost(top, P.STAIR_RISE, 0.001, "ends flush with the landing's walkable top")
	var slope := rad_to_deg(atan2(top, zmax - zmin))
	assert_true(slope < 46.0, "ramp %.1f deg is below the player's 46 deg floor limit" % slope)
	var shapes: Array = Models.collision_shapes("wood_stairs")
	assert_eq(shapes.size(), 1)
	assert_true(shapes[0][0] is ConvexPolygonShape3D)
	var up: Array = Models.collision_shapes("upper_floor")
	var slab := up[0][0] as BoxShape3D
	var xf: Transform3D = up[0][1]
	assert_almost(xf.origin.y + slab.size.y * 0.5, P.UPPER_TOP, 0.001, "upper floor walkable top")


func test_lazy_scripts_load_safely() -> void:
	for sid in Factory.LAZY_SCRIPTS:
		var s: Script = Factory.script_for(String(sid))
		assert_not_null(s, sid)
		var n := Factory.create(String(sid), "", {})
		assert_true(n.has_method("get_interaction"), sid + " honours the interaction contract")
		n.free()
	assert_true(Factory.lazy_script_ready("pumpkin_lantern"), "the pumpkin lantern script is this module's own")
	assert_true(Factory._load_lazy("res://src/building/structures/does_not_exist.gd") == Factory.BASE, "missing script -> base structure")
	# Every structure spawns, whatever its (lazy) script.
	for sid in ["furnace", "companion_bed", "companion_perch", "wardrobe", "vanity_mirror", "loom", "kitchen_counter", "sturdy_planter", "pumpkin_lantern"]:
		var n2 := Factory.spawn_structure(_area, GameState.add_structure(sid, Vector3(0, 0, 0), 0))
		assert_not_null(n2, sid + " spawns")
		var info: Dictionary = n2.get_interaction(null)
		assert_true(info.has("text") and info.has("enabled"), sid + " interaction contract")
		n2.free()


func test_thread_veil_has_a_pale_drape_for_arachnophobia() -> void:
	Settings.values["arachnophobia"] = false
	var a := Node3D.new()
	add_child(a)
	Models.build("thread_veil", a)
	Settings.values["arachnophobia"] = true
	var b := Node3D.new()
	add_child(b)
	Models.build("thread_veil", b)
	var ma: Mesh = (a.get_child(0) as MeshInstance3D).mesh
	var mb: Mesh = (b.get_child(0) as MeshInstance3D).mesh
	assert_ne(ma, mb, "a different model with the setting on")
	assert_eq(ItemDB.structure_display_name("thread_veil"), "Pale Veil Drape")
	a.free()
	b.free()
	# A placed veil follows the setting live.
	var n := Factory.spawn_structure(_area, GameState.add_structure("thread_veil", Vector3(0.5, 0, 0.5), 0))
	var shown: Mesh = (n.get_node("Model").get_child(0) as MeshInstance3D).mesh
	assert_eq(shown, mb, "built as the drape")
	Settings.values["arachnophobia"] = false
	Events.settings_changed.emit("arachnophobia")
	await wait_frames(1)
	var after: Mesh = null
	for c in n.get_node("Model").get_children():
		if c is MeshInstance3D and not (c as Node).is_queued_for_deletion():
			after = (c as MeshInstance3D).mesh
	assert_eq(after, ma, "rebuilt with the thread strands when the setting is turned off")
	assert_eq(String(n.display_name()), "Thread Veil")


## Build messages use the display name: with arachnophobia on, the veil is never called a "Thread Veil".
func test_build_messages_use_the_arachnophobia_name() -> void:
	Settings.values["arachnophobia"] = true
	var uid := GameState.add_structure("thread_veil", Vector3(0.5, 0, 0.5), 0)
	var ctx := {"structures": GameState.structures, "area_id": "surface", "build_area": {"center": Vector2.ZERO, "radius": 30.0, "blocked": []},
		"height_fn": func(_x: float, _z: float) -> float: return 0.0}
	var res := P.validate("candy_bowl", Vector3(0.5, 0, 0.5), 0, ctx)
	assert_false(bool(res["ok"]))
	assert_eq(String(res["blocker"]), uid)
	assert_eq(String(res["reason"]), "The Pale Veil Drape is in the way")
	var n := Factory.spawn_structure(_area, uid)
	assert_eq(String(n.display_name()), "Pale Veil Drape")
	Settings.values["arachnophobia"] = false
	assert_eq(String(P.validate("candy_bowl", Vector3(0.5, 0, 0.5), 0, ctx)["reason"]), "The Thread Veil is in the way")
	# Legacy pieces keep their legacy wording.
	GameState.add_structure("table", Vector3(3.5, 0, 0.5), 0)
	ctx.erase("occupancy")      # ctx caches the occupancy of the pieces it has seen
	assert_eq(String(P.validate("stool", Vector3(3.5, 0, 0.5), 0, ctx)["reason"]), "The Table is in the way")


## The Expedition Board opens the journal on its Optional tab (the "goals" alias would be the Story tab).
func test_expedition_board_opens_the_optional_goals() -> void:
	var Journal := load("res://src/ui/panels/journal_panel.gd")
	var n := Factory.spawn_structure(_area, GameState.add_structure("expedition_board", Vector3(1, 0, 0.5), 0))
	assert_true(n.has_method("panel_args"))
	var tab := String(n.panel_args()["tab"])
	assert_eq(String(Journal.TAB_ALIASES.get(tab, tab)), "optional", "the board shows optional discoveries, not the story")
	assert_true(bool(n.get_interaction(null)["enabled"]))


func test_every_pumpkin_face_is_its_own_carving() -> void:
	var seen := {}
	for face in ItemDB.structure("pumpkin_lantern").get("faces", []):
		var root := Node3D.new()
		add_child(root)
		var parts: Dictionary = Seasonal.pumpkin_lantern(root, String(face))
		var m: Mesh = (parts["face"] as MeshInstance3D).mesh
		assert_false(seen.has(m), "%s has its own carving" % face)
		seen[m] = face
		root.free()
	assert_eq(seen.size(), 6)
	var root2 := Node3D.new()
	add_child(root2)
	var p2: Dictionary = Seasonal.pumpkin_lantern(root2, "not-a-face")
	assert_eq((p2["face"] as MeshInstance3D).mesh, seen.keys()[0], "unknown face ids fall back to the first")
	root2.free()


func test_decorations_are_never_hostile() -> void:
	for sid in _new_ids():
		var n := Factory.spawn_structure(_area, GameState.add_structure(sid, Vector3(0, 0, 0), 0))
		for g in ["enemy", "stalker", "director_anchor"]:
			assert_false(n.is_in_group(g), "%s is never %s" % [sid, g])
		assert_false(n.has_method("is_threatening"), sid + " never threatens")
		assert_false(n.get("health") is Node, sid + " has no health to fight with")
		n.free()

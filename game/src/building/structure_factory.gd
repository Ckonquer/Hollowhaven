extends RefCounted
## Creates structure nodes for ids in data/structures.gd and spawns saved structures into an area.
##   StructureFactory.create("bed", uid)            -> Node3D (not yet in the tree)
##   StructureFactory.spawn_structure(area, uid)    -> Node3D placed from GameState.structures[uid]
## Nodes live under a "Structures" Node3D child of the area and are named "S_<uid>".

const Placement := preload("res://src/building/placement.gd")
const BASE := preload("res://src/building/structure.gd")
const SCRIPTS := {
	"workbench": preload("res://src/building/structures/workbench.gd"),
	"storage_chest": preload("res://src/building/structures/storage_chest.gd"),
	"bed": preload("res://src/building/structures/bed.gd"),
	"lantern_post": preload("res://src/building/structures/lamp.gd"),
	"heartbloom_lamp": preload("res://src/building/structures/lamp.gd"),
	"echo_chime": preload("res://src/building/structures/echo_chime.gd"),
	"haven_banner": preload("res://src/building/structures/banner.gd"),
	"crop_plot": preload("res://src/farming/crop_plot.gd"),
}
const CONTAINER := "Structures"


static func script_for(structure_id: String) -> Script:
	return SCRIPTS.get(structure_id, BASE)


static func create(structure_id: String, uid: String = "", params: Dictionary = {}) -> Node3D:
	var n: Node3D = script_for(structure_id).new()
	var p := {"uid": uid, "id": structure_id}
	p.merge(params, true)
	n.setup(p)
	n.name = ("S_" + uid) if uid != "" else ("Preview_" + structure_id)
	return n


static func structures_root(area: Node) -> Node3D:
	var c := area.get_node_or_null(CONTAINER) as Node3D
	if c == null:
		c = Node3D.new()
		c.name = CONTAINER
		area.add_child(c)
	return c


## Spawns the saved structure `uid` into `area`. Returns the node (or null if the record is invalid).
static func spawn_structure(area: Node, uid: String) -> Node3D:
	if area == null or not is_instance_valid(area):
		return null
	var rec: Variant = GameState.structures.get(uid)
	if not (rec is Dictionary):
		return null
	var sid: String = String(rec.get("id", ""))
	if ItemDB.structure(sid).is_empty():
		push_warning("StructureFactory: unknown structure '%s' (uid %s) skipped" % [sid, uid])
		return null
	var root := structures_root(area)
	var existing := root.get_node_or_null("S_" + uid)
	if existing != null:
		return existing as Node3D
	var n := create(sid, uid)
	n.position = Placement.vec_from(rec.get("pos"))
	n.rotation.y = deg_to_rad(float(rec.get("rot", 0.0)))
	root.add_child(n)
	return n


static func find_node(area: Node, uid: String) -> Node3D:
	if area == null or not is_instance_valid(area):
		return null
	var root := area.get_node_or_null(CONTAINER)
	if root == null:
		return null
	return root.get_node_or_null("S_" + uid) as Node3D

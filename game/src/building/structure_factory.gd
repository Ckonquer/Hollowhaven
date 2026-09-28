extends RefCounted
## Creates structure nodes for ids in data/structures.gd and spawns saved structures into an area.
##   StructureFactory.create("bed", uid)            -> Node3D (not yet in the tree)
##   StructureFactory.spawn_structure(area, uid)    -> Node3D placed from GameState.structures[uid]
## Nodes live under a "Structures" Node3D child of the area and are named "S_<uid>".
## Behaviour scripts: SCRIPTS (this module, preloaded) and LAZY_SCRIPTS (docs/CHAPTER_TWO_SPEC.md §9: scripts
## other modules own, loaded on first use). A lazy script that is missing or fails to load falls back to the
## base structure (which still honours the interaction contract), so one broken module never stops the Haven
## from loading.

const Placement := preload("res://src/building/placement.gd")
const BASE := preload("res://src/building/structure.gd")
const LAMP := preload("res://src/building/structures/lamp.gd")
const SCRIPTS := {
	"workbench": preload("res://src/building/structures/workbench.gd"),
	"storage_chest": preload("res://src/building/structures/storage_chest.gd"),
	"bed": preload("res://src/building/structures/bed.gd"),
	"lantern_post": LAMP,
	"heartbloom_lamp": LAMP,
	"echo_chime": preload("res://src/building/structures/echo_chime.gd"),
	"haven_banner": preload("res://src/building/structures/banner.gd"),
	"crop_plot": preload("res://src/farming/crop_plot.gd"),
	# Chapter Two (building module): lights, keepsakes and furniture that do things.
	"wardlight": LAMP,
	"miner_lamp": LAMP,
	"ghost_lantern": LAMP,
	"pumpkin_lights": LAMP,
	"lanternwake_table": LAMP,
	"music_box": preload("res://src/building/structures/music_box.gd"),
	"expedition_board": preload("res://src/building/structures/expedition_board.gd"),
	"thread_veil": preload("res://src/building/structures/thread_veil.gd"),
}
## Structure id -> script path owned by another module (safe-loaded, spec §9). The pumpkin lantern is this
## module's own script but stays lazy per the contract.
const LAZY_SCRIPTS := {
	"furnace": "res://src/building/structures/furnace.gd",
	"companion_bed": "res://src/building/structures/companion_nook.gd",
	"companion_perch": "res://src/building/structures/companion_nook.gd",
	"wardrobe": "res://src/building/structures/wardrobe.gd",
	"vanity_mirror": "res://src/building/structures/wardrobe.gd",
	"pumpkin_lantern": "res://src/building/structures/pumpkin_lantern.gd",
	"loom": "res://src/building/structures/workbench.gd",
	"kitchen_counter": "res://src/building/structures/workbench.gd",
	"sturdy_planter": "res://src/farming/crop_plot.gd",
}
const CONTAINER := "Structures"

static var _lazy: Dictionary = {}      # path -> Script (BASE when the script can't be used)


static func script_for(structure_id: String) -> Script:
	if SCRIPTS.has(structure_id):
		return SCRIPTS[structure_id]
	if LAZY_SCRIPTS.has(structure_id):
		return _load_lazy(String(LAZY_SCRIPTS[structure_id]))
	return BASE


## True when the lazy script of `structure_id` is present and usable (tests / diagnostics).
static func lazy_script_ready(structure_id: String) -> bool:
	return LAZY_SCRIPTS.has(structure_id) and _load_lazy(String(LAZY_SCRIPTS[structure_id])) != BASE


static func _load_lazy(path: String) -> Script:
	if _lazy.has(path):
		return _lazy[path]
	var s: Script = BASE
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is Script and (res as Script).can_instantiate() and _extends_base(res as Script):
			s = res
		else:
			push_warning("StructureFactory: '%s' can't be used, using the base structure" % path)
	_lazy[path] = s
	return s


static func _extends_base(s: Script) -> bool:
	var cur: Script = s
	while cur != null:
		if cur == BASE:
			return true
		cur = cur.get_base_script()
	return false


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

extends Node
## Finds what Krystal can interact with / harvest (throttled, ~12 Hz).
## Candidates come from two queries on the interact layer (16):
##   1. a sphere in front of the player (what she is facing)
##   2. the camera-centre ray (what the player is looking at), limited to reach
## Each collider is resolved up its parent chain to the node implementing get_interaction or
## get_harvest_info (see ARCHITECTURE.md "Interaction contract"). Candidates are scored by distance to
## their collision surface and angle to the facing (player_logic.score_candidate); the best valid one
## becomes the focus. Walls (world|structure) between the player and a candidate block it.

const Logic := preload("res://src/player/player_logic.gd")

const INTERACT_LAYER := 16
const BLOCK_MASK := 1 | 32
const INTERVAL := 0.08
const MAX_PARENT_WALK := 6

var player: Node3D = null
var max_dist: float = Logic.INTERACT_RANGE
var enabled: bool = true

var focus: Node = null                 # node implementing the interaction/harvest methods
var focus_interaction: Dictionary = {}
var focus_harvest: Dictionary = {}
var prompt: Dictionary = {}

var _timer: float = 0.0
var _sphere := SphereShape3D.new()
var _shape_q := PhysicsShapeQueryParameters3D.new()
var _ray_q := PhysicsRayQueryParameters3D.new()
var _los_q := PhysicsRayQueryParameters3D.new()
var _best: Node = null
var _best_score: float = INF
var _best_info: Dictionary = {}
var _best_harvest: Dictionary = {}
var _seen: Array = []


func _ready() -> void:
	_sphere.radius = 1.3
	_shape_q.shape = _sphere
	_shape_q.collision_mask = INTERACT_LAYER
	_shape_q.collide_with_areas = true
	_shape_q.collide_with_bodies = true
	_ray_q.collision_mask = INTERACT_LAYER | BLOCK_MASK
	_ray_q.collide_with_areas = true
	_ray_q.collide_with_bodies = true
	_los_q.collision_mask = BLOCK_MASK
	_los_q.collide_with_areas = false
	_los_q.collide_with_bodies = true


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	refresh()


## Forces a re-evaluation now (e.g. right before interacting).
const COMPANION_FOCUS_PENALTY := 1.2


func refresh() -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree() or not enabled:
		_set_focus(null, {}, {})
		return
	if player.has_method("can_probe") and not bool(player.can_probe()):
		_set_focus(null, {}, {})
		return
	var space := player.get_world_3d().direct_space_state
	var ppos := player.global_position
	var facing: Vector3 = player.get_facing() if player.has_method("get_facing") else -player.global_basis.z
	_best = null
	_best_score = INF
	_best_info = {}
	_best_harvest = {}
	_seen.clear()
	var excl: Array[RID] = []
	if player is CollisionObject3D:
		excl.append((player as CollisionObject3D).get_rid())
	# 1) Sphere in front of the player
	_shape_q.transform = Transform3D(Basis.IDENTITY, ppos + facing * 1.05 + Vector3.UP * 0.8)
	_shape_q.exclude = excl
	for h in space.intersect_shape(_shape_q, 16):
		_consider(space, h.get("collider"), ppos, facing, false)
	# 2) Camera-centre ray (limited to the reach around the player)
	var cam: Camera3D = player.get_camera() if player.has_method("get_camera") else null
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree() and cam.current:
		var from := cam.global_position
		var dir := -cam.global_basis.z
		var reach := from.distance_to(ppos + Vector3.UP * 1.0) + max_dist + 0.5
		_ray_q.from = from
		_ray_q.to = from + dir * reach
		_ray_q.exclude = excl
		var hit := space.intersect_ray(_ray_q)
		if not hit.is_empty():
			var col: Object = hit.get("collider")
			if col is CollisionObject3D and ((col as CollisionObject3D).collision_layer & INTERACT_LAYER) != 0:
				_consider(space, col, ppos, facing, true)
			elif col is Node and resolve_owner(col as Node) != null:
				_consider(space, col, ppos, facing, true)   # e.g. a tree trunk (world layer) owned by a harvestable
	_set_focus(_best, _best_info, _best_harvest)


func _consider(space: PhysicsDirectSpaceState3D, collider: Object, ppos: Vector3, facing: Vector3, from_ray: bool) -> void:
	if collider == null or not (collider is Node3D):
		return
	var owner_node := resolve_owner(collider as Node)
	if owner_node == null or owner_node == player:
		return
	var col3 := collider as Node3D
	var surf := surface_distance(col3, ppos)
	var score := Logic.score_candidate(ppos, facing, col3.global_position, surf, max_dist, from_ray)
	# A befriended companion trotting at Krystal's heels must not steal the focus from the grass, bush or stone she
	# is actually reaching for: companions only win when looked at directly or when nothing else is near.
	if score != INF and not from_ray and (owner_node as Node).is_in_group("companion") and owner_node.has_method("is_befriended") and bool(owner_node.is_befriended()):
		score += COMPANION_FOCUS_PENALTY
	if score == INF or score >= _best_score:
		return
	if _seen.has(owner_node) and not from_ray:
		return
	_seen.append(owner_node)
	if not _line_of_sight(space, ppos, col3, owner_node, surf):
		return
	var info: Dictionary = {}
	var harvest: Dictionary = {}
	if owner_node.has_method("get_interaction"):
		var r: Variant = owner_node.get_interaction(player)
		if r is Dictionary:
			info = r
	if owner_node.has_method("get_harvest_info"):
		var r2: Variant = owner_node.get_harvest_info()
		# A depleted node (felled tree stump, emptied rock) is not a harvest target any more; its stump
		# collider can still be hit by the camera ray, which used to show "Chop Oak Tree" on a stump.
		if r2 is Dictionary and not is_depleted_info(r2):
			harvest = r2
	if info.is_empty() and harvest.is_empty():
		return
	_best = owner_node
	_best_score = score
	_best_info = info
	_best_harvest = harvest


func _line_of_sight(space: PhysicsDirectSpaceState3D, ppos: Vector3, col: Node3D, owner_node: Node, surf: float) -> bool:
	var from := ppos + Vector3.UP * 1.0
	var to := col.global_position + Vector3.UP * 0.3
	if from.distance_to(to) < 0.3:
		return true
	_los_q.from = from
	_los_q.to = to
	var excl: Array[RID] = []
	if player is CollisionObject3D:
		excl.append((player as CollisionObject3D).get_rid())
	_los_q.exclude = excl
	var hit := space.intersect_ray(_los_q)
	if hit.is_empty():
		return true
	var blocker: Object = hit.get("collider")
	if blocker is Node and resolve_owner(blocker as Node) == owner_node:
		return true
	if blocker == col:
		return true
	var hp: Vector3 = hit.get("position", to)
	var hflat := Vector2(hp.x - ppos.x, hp.z - ppos.z).length()
	# Blockers right at the candidate's own surface (e.g. its base on the ground) don't count.
	return hflat >= surf - 0.35


func _set_focus(node: Node, info: Dictionary, harvest: Dictionary) -> void:
	var changed := node != focus
	if changed and focus != null and is_instance_valid(focus) and focus.has_method("set_focused"):
		focus.set_focused(false)
	focus = node
	focus_interaction = info
	focus_harvest = harvest
	if node == null:
		prompt = {}
	else:
		prompt = Logic.build_prompt(info, harvest, _owned_tool(harvest))
	if changed and focus != null and focus.has_method("set_focused"):
		focus.set_focused(true)


func _owned_tool(harvest: Dictionary) -> String:
	if harvest.is_empty():
		return ""
	var tool := String(harvest.get("tool", "hand"))
	if tool == "hand" or tool == "":
		return "hand"
	return GameState.best_tool(tool)


## The focused node if it is (still) a harvestable, else null.
func focused_harvestable() -> Node:
	if focus != null and is_instance_valid(focus) and focus.has_method("get_harvest_info") and not focus_harvest.is_empty():
		return focus
	return null


func clear() -> void:
	_set_focus(null, {}, {})


# --- Static helpers ------------------------------------------------------------------------------------

## True when a get_harvest_info() result says the node is used up ({"depleted": true}).
static func is_depleted_info(info: Dictionary) -> bool:
	var d: Variant = info.get("depleted", false)
	return (d is bool and d) or ((d is int or d is float) and d != 0)


## Walks up the parent chain to the node that implements the interaction/harvest contract.
static func resolve_owner(n: Node) -> Node:
	var cur: Node = n
	for i in MAX_PARENT_WALK:
		if cur == null:
			return null
		if cur.has_method("get_interaction") or cur.has_method("get_harvest_info"):
			return cur
		cur = cur.get_parent()
	return null


## Horizontal distance from `from` to the collision surface of `col` (approximated per shape type).
static func surface_distance(col: Node3D, from: Vector3) -> float:
	var best := INF
	if col is CollisionObject3D:
		var co := col as CollisionObject3D
		for owner_id in co.get_shape_owners():
			if co.is_shape_owner_disabled(owner_id):
				continue
			var xf: Transform3D = co.global_transform * co.shape_owner_get_transform(owner_id)
			for i in co.shape_owner_get_shape_count(owner_id):
				var sh: Shape3D = co.shape_owner_get_shape(owner_id, i)
				best = minf(best, _shape_distance(sh, xf, from))
	if best == INF:
		best = Vector2(col.global_position.x - from.x, col.global_position.z - from.z).length()
	return maxf(best, 0.0)


static func _shape_distance(sh: Shape3D, xf: Transform3D, from: Vector3) -> float:
	var flat := Vector2(xf.origin.x - from.x, xf.origin.z - from.z).length()
	if sh is SphereShape3D:
		return flat - (sh as SphereShape3D).radius
	if sh is CapsuleShape3D:
		return flat - (sh as CapsuleShape3D).radius
	if sh is CylinderShape3D:
		return flat - (sh as CylinderShape3D).radius
	if sh is BoxShape3D:
		var local := xf.affine_inverse() * from
		var he: Vector3 = (sh as BoxShape3D).size * 0.5
		var c := Vector3(clampf(local.x, -he.x, he.x), clampf(local.y, -he.y, he.y), clampf(local.z, -he.z, he.z))
		var world_c := xf * c
		return Vector2(world_c.x - from.x, world_c.z - from.z).length()
	return flat

extends RefCounted
## Creates the companion nodes for an area from GameState (called by Game.load_area):
##   static spawn_for_area(area, area_id, player) -> Dictionary (id -> companion node)
## Surface / arena: wild creatures at companion_wild_<id> (Pebble pinned under its boulder until
## it is broken), home ones at companion_home_<id>, waiting ones at their saved spot (same area)
## or else home, the follower beside Krystal. Arriving at mine_exit, a companion waiting at the
## mine threshold happily rejoins. Below: only the follower, and only if it dares (enters_below);
## Mochi is set to wait at the surface threshold instead.
## The decision itself is the pure Logic.plan_spawns (unit tested); this file applies it.
## The follow/wait hotkey (G) is handled by the player, which calls companion.command().

const Logic := preload("res://src/companions/companion_logic.gd")
const CompanionScript := preload("res://src/companions/companion.gd")
const BoulderScript := preload("res://src/companions/pebble_boulder.gd")
const Layout := preload("res://data/world_layout.gd")
const DEBUG_SCRIPT := "res://src/companions/companion_debug.gd"
const Icons := preload("res://src/companions/emote_icons.gd")


static func spawn_for_area(area: Node, area_id: String, player: Node3D) -> Dictionary:
	var out: Dictionary = {}
	if area == null or not is_instance_valid(area):
		return out
	_apply_debug_overrides()
	Icons.prewarm()
	var surface := Logic.is_surface_area(area_id)
	var defs: Dictionary = {}
	for id in ItemDB.creature_ids():
		defs[id] = ItemDB.creature(id)
	var threshold: Variant = null
	if surface:
		threshold = _spawn_pos(area, "mine_threshold", false)
	else:
		var h: Vector2 = Layout.SPAWN_HINTS.get("mine_threshold", Vector2(50, -66))
		threshold = Vector3(h.x, 0.0, h.y)
	var plan := Logic.plan_spawns(area_id, GameState.companions, GameState.active_companion,
		String(GameState.player.get("spawn", "")), defs, GameState.is_depleted(Logic.PINNED_BOULDER_ID), threshold)
	for ch in plan["changes"]:
		GameState.set_companion_assignment(String(ch["id"]), String(ch["assignment"]),
			String(ch.get("wait_area", "")), ch.get("wait_pos"))
	for sp in plan["spawns"]:
		var node := _spawn_one(area, sp, surface, threshold, player)
		if node != null:
			out[String(sp["id"])] = node
	if Debug.is_cheat_allowed() and (Debug.has_arg("companion-walk") or Debug.has_arg("companion-log")) and ResourceLoader.exists(DEBUG_SCRIPT):
		if area.get_node_or_null("CompanionDebug") == null:
			var dbg: Node = load(DEBUG_SCRIPT).new()
			dbg.name = "CompanionDebug"
			area.add_child(dbg)
	return out


static func _spawn_one(area: Node, sp: Dictionary, surface: bool, threshold: Variant, player: Node3D) -> Node3D:
	var id := String(sp["id"])
	var mode := String(sp["mode"])
	var home: Vector3 = _spawn_pos(area, "companion_home_" + id, true)
	var wild: Vector3 = _spawn_pos(area, "companion_wild_" + id, true)
	var params := {"id": id, "mode": mode, "home": home, "wild": wild}
	if surface and threshold is Vector3:
		params["threshold"] = threshold
	var pos := home
	match mode:
		"wild", "pinned":
			pos = wild
		"wait", "reunite", "reunite_home":
			var wp: Variant = Logic.vec_from(sp.get("pos"))
			pos = _ground(area, wp) if wp is Vector3 else home
			params["wait"] = pos
		"follow":
			pos = player.global_position if player != null and is_instance_valid(player) else home
	var front := Vector3.BACK
	if mode == "pinned":
		# Pebble peeks out (feet first) from under the boulder, on the side facing the Haven.
		var to_haven := Vector3(Layout.HAVEN_CENTER.x - wild.x, 0.0, Layout.HAVEN_CENTER.y - wild.z)
		if to_haven.length() > 0.5:
			front = to_haven.normalized()
		pos = wild + front * 0.6
	var c: Node3D = CompanionScript.new()
	c.setup(params)
	area.add_child(c)
	c.global_position = pos
	if mode == "follow":
		c.place_near_player()
	elif mode == "pinned":
		c.visual.rotation.y = atan2(front.x, front.z)
		c.set("_yaw", atan2(front.x, front.z))
		var b: Node3D = BoulderScript.new()
		b.setup({"pebble": c, "front": front})
		area.add_child(b)
		b.global_position = wild
	return c


## Position of a registered spawn; falls back to the layout hint (snapped to the terrain).
static func _spawn_pos(area: Node, spawn_id: String, required: bool) -> Variant:
	var spawns: Variant = area.get("spawns")
	if spawns is Dictionary and (spawns as Dictionary).has(spawn_id):
		var t: Transform3D = spawns[spawn_id]
		return t.origin
	if Layout.SPAWN_HINTS.has(spawn_id):
		var h: Vector2 = Layout.SPAWN_HINTS[spawn_id]
		return _ground(area, Vector3(h.x, 0.0, h.y))
	if not required:
		return null
	if area.has_method("get_spawn"):
		var t2: Transform3D = area.get_spawn(spawn_id)
		return t2.origin
	return Vector3.ZERO


## Puts a saved position back on the ground (raycast first, then the area's height_at()).
static func _ground(area: Node, p: Vector3) -> Vector3:
	if area is Node3D and (area as Node3D).is_inside_tree():
		var space := (area as Node3D).get_world_3d().direct_space_state
		for top in [2.0, 40.0]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * float(top), p + Vector3.DOWN * (float(top) + 60.0), 1 | 32)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var hp: Vector3 = hit["position"]
				return hp + Vector3.UP * 0.05
	if area.has_method("height_at"):
		return Vector3(p.x, float(area.height_at(p.x, p.z)) + 0.05, p.z)
	return p


## Debug-only (editor builds): --companion-follow=<id> makes a befriended companion the follower.
static func _apply_debug_overrides() -> void:
	if not Debug.is_cheat_allowed() or not Debug.has_arg("companion-follow"):
		return
	var id := Debug.arg("companion-follow")
	if GameState.companions.has(id):
		if not GameState.is_befriended(id):
			GameState.companion(id)["befriended"] = true
		if GameState.active_companion != id:
			GameState.set_companion_assignment(id, "follow")

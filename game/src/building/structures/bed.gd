extends "res://src/building/structure.gd"
## Cozy bed: sleep until morning (fade, skip the clock, heal fully), wake beside the bed from now on
## (area spawn "bed" + Game.set_respawn) and save the journey.
## The bed Krystal last slept in is remembered in GameState.structures[uid]["data"]["respawn"], so the
## "bed" spawn is registered again when the Haven loads, and again after every piece built or taken
## apart nearby (the wake spot moves if something is built on it). If walls shut the bed in, the "bed"
## spawn points at the Haven's own wake-up spot until there is a way back (death / "Return to the
## Haven" never seal her in).

const Placement := preload("res://src/building/placement.gd")

const DANGER_RADIUS := 20.0
## Wake spots beside the bed in its local frame, in order of preference (long sides, then the ends).
const WAKE_SPOTS := [Vector3(1.05, 0.0, 0.25), Vector3(-1.05, 0.0, 0.25), Vector3(0.0, 0.0, 1.55), Vector3(0.0, 0.0, -1.55)]
const SIGHT_HEIGHT := 1.2     # line-of-sight height: above the 0.7 m bed, below every wall top
const ON_BED := 0.7           # top of the bed's collider (last-resort wake spot)
const MSG_SHUT_IN := "Your bed is walled in. Until there's a way back to it, you'll wake up in the Haven clearing."
const MSG_OPEN_AGAIN := "There's a way back to your bed again. You'll wake up beside it."

var _sleeping := false
var _danger_cache := ""
var _danger_checked_ms := -100000
var _spawn_refresh_queued := false
var _spawn_shut_in := false


func _setup_behaviour() -> void:
	Events.structure_placed.connect(_on_structures_changed)
	Events.structure_removed.connect(_on_structures_changed)
	if _is_respawn_bed():
		_register_spawn.call_deferred()


func _is_respawn_bed() -> bool:
	var data: Variant = record().get("data", {})
	return data is Dictionary and bool((data as Dictionary).get("respawn", false))


func is_sleeping() -> bool:
	return _sleeping


func get_interaction(_player: Node) -> Dictionary:
	if _sleeping:
		return {"text": "Sleeping...", "enabled": false}
	var danger := _danger_reason()
	if danger != "":
		return {"text": danger, "enabled": false}
	return {"text": "Sleep until morning", "enabled": true}


func interact(player: Node) -> void:
	if _sleeping or _danger_reason() != "":
		return
	sleep(player)


## Coroutine: the whole sleep sequence.
func sleep(player: Node = null) -> void:
	_sleeping = true
	var p: Node = player if player != null and is_instance_valid(player) else Game.player
	if p != null and p.has_method("set_input_enabled"):
		p.set_input_enabled(false)
	if p != null and p.has_method("play_emote"):
		p.play_emote("sleep")
	Audio.play_sfx("sleep")
	if Game.ui != null and Game.ui.has_method("fade_out"):
		await Game.ui.fade_out(0.9)
	else:
		await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	GameState.skip_to_morning()
	_heal(p)
	var xf := wake_transform()
	_mark_respawn()
	_register_spawn()
	Game.set_respawn(Game.area_id if Game.area_id != "" else "surface", "bed")
	if p != null and is_instance_valid(p) and p.has_method("teleport"):
		p.teleport(xf)
	var saved := SaveSystem.save_game()
	await get_tree().create_timer(0.6).timeout
	if Game.ui != null and Game.ui.has_method("fade_in"):
		await Game.ui.fade_in(1.0)
	if p != null and is_instance_valid(p) and p.has_method("set_input_enabled"):
		p.set_input_enabled(true)
	_sleeping = false
	Events.notify.emit("Slept until morning. Journey saved." if saved else "Slept until morning.", "success")
	Events.hint.emit("bed_respawn", "Your bed is now where you'll wake up if something goes wrong.")


func _heal(p: Node) -> void:
	GameState.player["hp"] = float(GameState.player.get("max_hp", 100.0))
	GameState.player["stamina"] = float(GameState.player.get("max_stamina", 100.0))
	if p == null or not is_instance_valid(p):
		return
	var h: Variant = p.get("health")
	if h is Node and is_instance_valid(h):
		if h.has_method("heal"):
			h.heal(float(h.get("max_hp")))
	if "stamina" in p:
		p.set("stamina", float(GameState.player.get("max_stamina", 100.0)))


## Where Krystal wakes: beside the bed on a free side, facing away from it.
func wake_transform() -> Transform3D:
	return _wake_spot()["xf"]


## {"xf": Transform3D, "shut_in": bool}. A side only counts when nothing solid stands between it and
## the bed: walls are only 0.22 m thick, so a spot 1 m past the side of a bed pushed against a wall
## has room on the far side of it. Among the sides in clear sight: one with a way out (not shut in by
## walls) beats one without, then one with room for Krystal beats one a small piece crowds (she is
## nudged free). With every side out of sight she wakes on top of the bed, never behind a wall.
## A bed upstairs (Chapter Two storeys) only wakes her on a side with the upper floor under it: never in
## the air past the floor's edge (with no such side, on top of the bed). Ground beds are unchanged.
func _wake_spot() -> Dictionary:
	if not is_inside_tree():
		return {"xf": _wake_xf(position, transform * (WAKE_SPOTS[0] as Vector3)), "shut_in": false}
	var centre := global_position
	var space := get_world_3d().direct_space_state
	var own := _own_rids()
	var level := Placement.level_of(record())
	var floors: Dictionary = {}
	if level >= 1:
		var occ := Placement.build_occupancy(GameState.structures, String(record().get("area", "surface")))
		floors = occ.get(Placement.layer_key("floor", level), {})
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.6
	var best := centre
	var best_rank := 0
	var best_shut := false
	for c in WAKE_SPOTS:
		var at: Vector3 = global_transform * (c as Vector3)
		var ray := PhysicsRayQueryParameters3D.create(centre + Vector3.UP * SIGHT_HEIGHT, at + Vector3.UP * SIGHT_HEIGHT, 1 | 32, own)
		if not space.intersect_ray(ray).is_empty():
			continue
		if level >= 1 and not floors.has(Vector2i(floori(at.x), floori(at.z))):
			continue      # past the edge of the upper floor (or over the stairwell)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
		q.collision_mask = 1 | 32
		q.exclude = own
		var fits: bool = space.intersect_shape(q, 1).is_empty()
		var shut := _is_shut_in(at)
		var rank: int = 1 + (0 if shut else 2) + (1 if fits else 0)
		if rank > best_rank:
			best_rank = rank
			best = at
			best_shut = shut
			if rank == 4:
				break
	if best_rank == 0:
		return {"xf": _wake_xf(centre, centre + Vector3.UP * ON_BED), "shut_in": _is_shut_in(centre, true)}
	return {"xf": _wake_xf(centre, best), "shut_in": best_shut}


func _wake_xf(centre: Vector3, at: Vector3) -> Transform3D:
	var d := Vector3(at.x - centre.x, 0.0, at.z - centre.z)
	var yaw: float = atan2(-d.x, -d.z) if d.length() > 0.01 else rotation.y
	return Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.05)


func _own_rids() -> Array[RID]:
	var out: Array[RID] = []
	for b in _bodies:
		if is_instance_valid(b) and b is CollisionObject3D:
			out.append((b as CollisionObject3D).get_rid())
	return out


## True when built pieces leave no way out from `pos` (the build mode's enclosure rule).
## `ignore_self` leaves this bed out (for the spot on top of it). `level`: the storey `pos` is on (-1 = the
## bed's own storey; a bed upstairs is checked on the upper floor, where the stairwell is a way out).
func _is_shut_in(pos: Vector3, ignore_self: bool = false, level: int = -1) -> bool:
	var aid: String = String(record().get("area", "surface"))
	var recs: Dictionary = GameState.structures
	if ignore_self and recs.has(uid):
		recs = recs.duplicate()
		recs.erase(uid)
	var ops: Script = load("res://src/building/build_ops.gd")   # load, not preload: build_ops -> factory -> bed
	var lv: int = level if level >= 0 else Placement.level_of(record())
	var ctx := {"structures": recs, "area_id": aid, "build_area": ops.build_area_for(aid), "player_level": lv}
	return Placement.would_enclose(pos, ctx)


func _mark_respawn() -> void:
	for id in GameState.structures:
		var rec: Dictionary = GameState.structures[id]
		if String(rec.get("id", "")) != "bed":
			continue
		if not (rec.get("data") is Dictionary):
			rec["data"] = {}
		if id == uid:
			rec["data"]["respawn"] = true
		else:
			rec["data"].erase("respawn")


## Registers the area's "bed" spawn (used by respawn after a fall and Pause > "Return to the Haven").
## While the bed is walled in it points at the Haven's own wake-up spot instead; `announce` tells
## Krystal when that changes.
func _register_spawn(announce: bool = false) -> void:
	var a := _area()
	if a == null or not a.has_method("register_spawn"):
		return
	var spot := _wake_spot()
	var xf: Transform3D = spot["xf"]
	var shut: bool = bool(spot["shut_in"])
	if shut:
		xf = _open_haven_spawn(a, xf)
	if announce and shut != _spawn_shut_in:
		Events.notify.emit(MSG_SHUT_IN if shut else MSG_OPEN_AGAIN, "info")
	_spawn_shut_in = shut
	a.register_spawn("bed", xf)


func _open_haven_spawn(a: Node, fallback: Transform3D) -> Transform3D:
	var sp: Variant = a.get("spawns")
	if sp is Dictionary:
		for id in ["haven_respawn", "haven_start"]:
			var xf: Variant = (sp as Dictionary).get(id)
			# The Haven's wake-up spots are on the ground, whatever storey the bed is on.
			if xf is Transform3D and not _is_shut_in((xf as Transform3D).origin, false, 0):
				return xf
	return fallback


## A piece was built or taken apart: refresh the wake spot once the physics space has caught up
## (a new collider is in, a removed one is gone).
func _on_structures_changed(_uid: String, _sid: String) -> void:
	if _spawn_refresh_queued or _removing or not is_inside_tree() or not _is_respawn_bed():
		return
	_spawn_refresh_queued = true
	get_tree().physics_frame.connect(_refresh_spawn, CONNECT_ONE_SHOT)


func _refresh_spawn() -> void:
	_spawn_refresh_queued = false
	if not _removing and is_inside_tree() and _is_respawn_bed():
		_register_spawn(true)


func _area() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("register_spawn"):
			return n
		n = n.get_parent()
	return Game.area


func _danger_reason() -> String:
	var now := Time.get_ticks_msec()
	if now - _danger_checked_ms < 500:
		return _danger_cache
	_danger_checked_ms = now
	_danger_cache = ""
	if is_inside_tree():
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is Node3D and e.has_method("is_threatening") and e.is_threatening() and (e as Node3D).global_position.distance_to(global_position) < DANGER_RADIUS:
				_danger_cache = "You can't sleep with danger nearby"
				break
	return _danger_cache

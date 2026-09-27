extends "res://src/building/structure.gd"
## Cozy bed: sleep until morning (fade, skip the clock, heal fully), wake beside the bed from now on
## (area spawn "bed" + Game.set_respawn) and save the journey.
## The bed Krystal last slept in is remembered in GameState.structures[uid]["data"]["respawn"], so the
## "bed" spawn is registered again when the Haven loads.

const DANGER_RADIUS := 20.0

var _sleeping := false
var _danger_cache := ""
var _danger_checked_ms := -100000


func _setup_behaviour() -> void:
	var data: Variant = record().get("data", {})
	if data is Dictionary and bool(data.get("respawn", false)):
		_register_spawn.call_deferred()


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
	var candidates := [Vector3(1.05, 0.0, 0.25), Vector3(-1.05, 0.0, 0.25), Vector3(0.0, 0.0, 1.55), Vector3(0.0, 0.0, -1.55)]
	var centre := global_position
	var chosen: Vector3 = global_transform * (candidates[0] as Vector3)
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		var cap := CapsuleShape3D.new()
		cap.radius = 0.36
		cap.height = 1.6
		for c in candidates:
			var at: Vector3 = global_transform * (c as Vector3)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
			q.collision_mask = 1 | 32
			if space.intersect_shape(q, 1).is_empty():
				chosen = at
				break
	var d := Vector3(chosen.x - centre.x, 0.0, chosen.z - centre.z)
	var yaw: float = atan2(-d.x, -d.z) if d.length() > 0.01 else rotation.y
	return Transform3D(Basis(Vector3.UP, yaw), chosen + Vector3.UP * 0.05)


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


func _register_spawn() -> void:
	var a := _area()
	if a != null and a.has_method("register_spawn"):
		a.register_spawn("bed", wake_transform())


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

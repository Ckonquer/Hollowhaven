extends Node3D
## Persistent world pickup: items dropped because the backpack was full, enemy drops, gifts.
## Items on the ground are never destroyed: each persistent pickup mirrors one entry of
## GameState.dropped ({uid, item, count, area, pos}) and is re-created when its area loads.
##
## API (stable, used by Game, GameState overflow, enemies, the Below):
##   static func spawn_from_state(area: Node, uid: String) -> Node3D
##       (Re)creates the pickup for GameState.dropped entry `uid` under `area`. Returns the existing
##       node if one is already present, null if the uid is unknown.
##   static func spawn(item_id: String, count: int, pos: Vector3, persistent := true, parent: Node = null) -> Node3D
##       Drops a new pickup at `pos` (settles onto the ground). persistent=true records it in
##       GameState.dropped for the current area (Game.area / the area's area_id) so it survives saves.
##   collect(player = null) -> int      picks up as much as fits in the backpack; returns the amount taken.
##       Fully collected pickups call GameState.remove_dropped(uid) and vanish; partial pickups update
##       the stored count. Quest items always fit (key pouch).
## Interaction: groups "interactable", "pickup", "world_item"; a StaticBody3D on layers 16|64.
## E picks it up; walking over it also collects it (after a short delay so drops don't vanish instantly).

const ItemVisual := preload("res://src/world/common/item_visual.gd")
const Fx := preload("res://src/world/common/fx.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const SELF_PATH := "res://src/world/common/world_item.gd"
const PICKUP_DELAY := 0.9
const AUTO_RADIUS := 1.3
const LAYER_INTERACT := 16
const LAYER_PICKUP := 64

var uid: String = ""
var item_id: String = "wood"
var count: int = 1
var persistent: bool = true

var _age := 0.0
var _spin: Node3D
var _ring: MeshInstance3D
var _body: StaticBody3D
var _collected := false
var _check_t := 0.0
var _full_warn_ms := -100000
var _phase := 0.0


# --- Static API ------------------------------------------------------------------------------------

static func spawn_from_state(area: Node, p_uid: String) -> Node3D:
	var d: Dictionary = GameState.get_dropped(p_uid)
	if d.is_empty() or area == null or not is_instance_valid(area):
		return null
	var tree := area.get_tree()
	if tree != null:
		for n in tree.get_nodes_in_group("world_item"):
			if is_instance_valid(n) and not n.is_queued_for_deletion() and String(n.get("uid")) == p_uid:
				return n
	var script: GDScript = load(SELF_PATH)
	var node: Node3D = script.new()
	node.uid = p_uid
	node.item_id = String(d.get("item", "wood"))
	node.count = maxi(1, int(d.get("count", 1)))
	node.persistent = true
	var p: Variant = d.get("pos", null)
	var pos := Vector3.ZERO
	if p is Array and (p as Array).size() == 3:
		pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
	node.position = pos
	area.add_child(node)
	node.global_position = pos
	return node


static func spawn(p_item: String, p_count: int, pos: Vector3, p_persistent: bool = true, parent: Node = null) -> Node3D:
	if p_count <= 0 or not ItemDB.has_item(p_item):
		return null
	var area: Node = parent
	if area == null:
		if Game.area != null and is_instance_valid(Game.area):
			area = Game.area
		else:
			var tree := Engine.get_main_loop() as SceneTree
			area = tree.current_scene if tree != null else null
	if area == null:
		return null
	if p_persistent:
		var area_id := Game.area_id
		var aid: Variant = area.get("area_id")
		if aid is String and String(aid) != "":
			area_id = String(aid)
		if area_id == "":
			area_id = String(GameState.player.get("area", "surface"))
		var new_uid := GameState.add_dropped(p_item, p_count, area_id, pos)
		return spawn_from_state(area, new_uid)
	var script: GDScript = load(SELF_PATH)
	var node: Node3D = script.new()
	node.item_id = p_item
	node.count = p_count
	node.persistent = false
	node.position = pos
	area.add_child(node)
	node.global_position = pos
	return node


# --- Node -------------------------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("world_item")
	add_to_group("interactable")
	add_to_group("pickup")
	_phase = float(hash(uid if uid != "" else str(get_instance_id())) % 1000) * 0.0063
	_settle_initial()
	_spin = Node3D.new()
	_spin.name = "Spin"
	add_child(_spin)
	_spin.add_child(ItemVisual.build(item_id))
	_ring = Kit.torus(0.2, 0.3, Mat.glow(Palette.WARD_GLOW, 0.9))
	_ring.name = "Glow"
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(1, 0.15, 1)
	_ring.position = Vector3(0, 0.03, 0)
	add_child(_ring)
	_body = StaticBody3D.new()
	_body.name = "Interact"
	_body.collision_layer = LAYER_INTERACT | LAYER_PICKUP
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.55
	cs.shape = sh
	cs.position = Vector3(0, 0.35, 0)
	_body.add_child(cs)
	add_child(_body)
	# Spawn pop: a little hop.
	_spin.scale = Vector3.ONE * 0.2
	_spin.position = Vector3(0, 0.6, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_spin, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_spin, "position:y", 0.2, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_settle_ray.call_deferred()


## Puts the pickup on the terrain right away when the area knows its height.
func _settle_initial() -> void:
	var area := _area()
	if area != null and area.has_method("height_at"):
		var h: float = area.height_at(global_position.x, global_position.z)
		if global_position.y < h or global_position.y > h + 2.5:
			global_position.y = h


## After physics has the colliders, snap onto the ground / structures below.
func _settle_ray() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.2
	var q := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * 30.0)
	q.collision_mask = 1 | 32
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"] + Vector3.UP * 0.02
		_store_pos()


func _store_pos() -> void:
	if not persistent or uid == "":
		return
	var d: Dictionary = GameState.get_dropped(uid)
	if not d.is_empty():
		d["pos"] = [global_position.x, global_position.y, global_position.z]


func _area() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("get_spawn"):
			return n
		n = n.get_parent()
	return null


func _process(delta: float) -> void:
	if _collected:
		return
	_age += delta
	if _spin != null and _age > 0.5:
		_spin.position.y = 0.2 + sin(_age * 2.2 + _phase) * 0.06
		_spin.rotation.y += delta * 1.1
	if _ring != null:
		var s := 1.0 + sin(_age * 3.0 + _phase) * 0.08
		_ring.scale = Vector3(s, 0.15, s)
	_check_t += delta
	if _check_t >= 0.2 and _age >= PICKUP_DELAY:
		_check_t = 0.0
		var p: Node = Game.player
		if p != null and is_instance_valid(p) and p is Node3D:
			var pp := (p as Node3D).global_position
			if Vector2(pp.x - global_position.x, pp.z - global_position.z).length() < AUTO_RADIUS and absf(pp.y - global_position.y) < 2.0:
				collect(p)


# --- Interaction contract ------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if _collected:
		return {}
	var nm := ItemDB.display_name(item_id)
	var label: String = ("Pick up %s" % nm) if count <= 1 else ("Pick up %s x%d" % [nm, count])
	if not ItemDB.is_quest_item(item_id) and GameState.inventory.space_for(item_id) <= 0:
		return {"text": "%s - backpack full" % nm, "enabled": false, "reason": "Backpack full"}
	return {"text": label, "enabled": true}


func interact(player: Node = null) -> void:
	collect(player)


## Picks up as much as fits. Returns how many were taken (0 if the backpack is full).
func collect(_player: Node = null) -> int:
	if _collected or count <= 0:
		return 0
	var fit: int = count
	if not ItemDB.is_quest_item(item_id):
		fit = mini(count, GameState.inventory.space_for(item_id))
	if fit <= 0:
		_warn_full()
		return 0
	GameState.give_item(item_id, fit, global_position)   # the HUD shows "+n Item" from Events.item_added
	count -= fit
	Audio.play_3d("pickup", global_position + Vector3.UP * 0.3, -3.0)
	if count <= 0:
		_collected = true
		if persistent and uid != "":
			GameState.remove_dropped(uid)
		_vanish()
	elif persistent and uid != "":
		var d: Dictionary = GameState.get_dropped(uid)
		if not d.is_empty():
			d["count"] = count
	return fit


func is_collected() -> bool:
	return _collected


func _warn_full() -> void:
	var now := Time.get_ticks_msec()
	if now - _full_warn_ms < 4000:
		return
	_full_warn_ms = now
	Events.notify.emit("Backpack full! Make some room to pick this up.", "warn")


func _vanish() -> void:
	remove_from_group("interactable")
	remove_from_group("pickup")
	if _body != null:
		_body.collision_layer = 0
	if not is_inside_tree():
		queue_free()
		return
	Fx.burst(get_parent(), global_position + Vector3.UP * 0.3, "sparkle", 0.6)
	var tw := create_tween().set_parallel(true)
	if _spin != null:
		tw.tween_property(_spin, "position:y", 0.9, 0.22).set_ease(Tween.EASE_OUT)
		tw.tween_property(_spin, "scale", Vector3.ONE * 0.05, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if _ring != null:
		tw.tween_property(_ring, "scale", Vector3(0.01, 0.15, 0.01), 0.2)
	tw.chain().tween_callback(queue_free)

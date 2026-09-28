extends RefCounted
## The Tailor's Cache (MP 7 "The Tailor's Cache"; spec 7.1; optional goal opt_tailors_cache).
## A small ribbon-tied cache between the north roots of the Old Oak. The environmental clue: four ribbons tied
## to low, crooked branches lead to it from the Old Oak path (data/c1x_layout.gd TAILOR_RIBBONS). Opening it grants
## the content bundle rw_c1x_tailor_cache ONCE (GameState.grant_once through the ledger): its flag c1x_tailor_cache
## unlocks the Loom recipe and the ribbon bow pattern and completes the optional goal (whose own reward, woven cloth,
## is paid by the optional log). Opened state persists through the ledger / flag, so the lid stays open on reload.
## No enemy, no timer, no requirement: always completable.
##   Tailor.build(area)                  (called by src/world/surface/annexes.gd)
##   Tailor.grass_clearings() -> Array   ([[Vector2, radius]], applied before the grass is built)
## The cache node (group "interactable", "c1x_tailor_cache"): is_open() -> bool, open() -> bool (true on the first
## opening only), get_interaction(player) / interact(player).

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")


static func build(area: Node3D) -> void:
	if area == null:
		return
	var parent := Common.sub_root(area, "TailorCache")
	for i in L.TAILOR_RIBBONS.size():
		var r: Dictionary = L.TAILOR_RIBBONS[i]
		var col: Color = Common.RIBBON_COLORS.get(String(r.get("color", "rose")), Common.RIBBON_COLORS["rose"])
		var marker := Common.ribbon_marker(col, i, true)
		marker.name = String(r["id"])
		Common.place(parent, marker, area, r["pos"], float(r.get("yaw_deg", 0.0)), -0.02)
	var cache := Cache.new()
	cache.node_id = String(L.TAILOR_CACHE["id"])
	Common.place(parent, cache, area, L.TAILOR_CACHE["pos"], float(L.TAILOR_CACHE["yaw_deg"]), -0.03)


static func grass_clearings() -> Array:
	var out: Array = [[L.TAILOR_CACHE["pos"], 1.4]]
	for r in L.TAILOR_RIBBONS:
		out.append([r["pos"], 0.5])
	return out


class Cache extends Node3D:
	const L := preload("res://data/c1x_layout.gd")
	const Common := preload("res://src/world/surface/c1x/common.gd")
	const Fx := preload("res://src/world/common/fx.gd")
	const OPEN_ANGLE := -1.9          # lid rotation about the hinge (radians) when open
	const MESSAGE := "Inside: plans for a loom, a ribbon bow pattern and a pouch of sunflax seeds. You can build a Loom now."
	const NOTE := "Pinned inside the lid: \"For whoever follows my ribbons - may your stitches stay straight. A loom is only wood and patience.\""

	var node_id: String = ""
	var lid: Node3D
	var _busy := false

	func _ready() -> void:
		name = node_id if node_id != "" else "TailorCache"
		add_to_group("interactable")
		add_to_group("c1x_tailor_cache")
		var meshes := Common.cache_meshes()
		add_child(Common.mi(meshes["body"], Common.prop_material(0.016), "Body", 80.0, true))
		lid = Node3D.new()
		lid.name = "Lid"
		lid.position = Vector3(0, 0.4, -0.25)      # hinge on the back edge
		add_child(lid)
		lid.add_child(Common.mi(meshes["lid"], Common.prop_material(0.016), "LidMesh", 80.0, true))
		var body := StaticBody3D.new()
		body.name = "Solid"
		body.collision_layer = Common.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("surface", "wood")
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.82, 0.55, 0.54)
		cs.shape = box
		cs.position = Vector3(0, 0.275, 0)
		body.add_child(cs)
		add_child(body)
		Common.interact_sphere(self, 0.85, 0.4)
		_apply(false)

	func is_open() -> bool:
		return GameState.has_reward(L.REWARD_TAILOR) or bool(GameState.get_flag(L.FLAG_TAILOR_CACHE))

	func get_interaction(_player: Node = null) -> Dictionary:
		if _busy:
			return {}
		if is_open():
			return {"text": "Look in the Tailor's Cache", "enabled": true}
		return {"text": "Open the Tailor's Cache", "enabled": true}

	func interact(_player: Node = null) -> void:
		if _busy:
			return
		if is_open():
			Events.say.emit("", NOTE, 5.5)
			return
		open()

	## Opens the cache: grants rw_c1x_tailor_cache once. True only the first time.
	func open() -> bool:
		var first := Common.grant_content(L.REWARD_TAILOR, MESSAGE)
		if first:
			Events.say.emit("", NOTE, 6.0)
			Events.hint.emit("c1x_loom", "The Loom turns sunflax and fiber into woven cloth. Find it in your workbench recipes.")
			Common.play_3d("chest_open", global_position + Vector3.UP * 0.4)
			if is_inside_tree():
				Fx.burst(get_parent(), global_position + Vector3(0, 0.7, 0), "sparkle", 0.8)
		_apply(first)
		return first

	func _apply(animate: bool) -> void:
		if lid == null:
			return
		var target := OPEN_ANGLE if is_open() else 0.0
		if animate and is_inside_tree():
			_busy = true
			var tw := create_tween()
			tw.tween_property(lid, "rotation:x", target, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func() -> void: _busy = false)
		else:
			lid.rotation.x = target

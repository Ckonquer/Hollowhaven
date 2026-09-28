extends Node3D
## Gathering mastery rank 4 (reward "highlight_radius", data/mastery.gd): a soft, STEADY sparkle (never blinking
## or flashing: comfort rule) floating over the nearest non-depleted harvestables around Krystal.
## ONE helper per scene tree: resource_node.gd creates it (under the tree root) when the first node registers and
## hands it its static registry (the same Array). Every HIGHLIGHT_REFRESH seconds it picks at most HIGHLIGHT_MAX
## nodes from that registry (no per-frame work, no group scans) and moves a fixed pool of quads (one shared mesh +
## material) over them; with the reward not reached it only reads the rank. It frees itself once no resource node
## is left (and hides everything as soon as an area starts unloading).
## Selection (candidates): in range, not depleted, still harvestable; never trees (big and obvious) or quest rubble
## (HIGHLIGHT_SKIP_KINDS); special materials first (everything not in SPOT_SKIP_KINDS), then the everyday
## ones, each nearest first.

const Mastery := preload("res://src/core/mastery.gd")
const MasteryData := preload("res://data/mastery.gd")

const QUAD_SIZE := 0.42
const TEX_SIZE := 32

## resource_node.gd's static registry of live resource nodes (never copied).
var registry: Array = []
## Nodes sparkling right now, nearest / most special first (tests and QA).
var shown: Array = []
## Refreshes done (tests).
var refreshes := 0
var _t := 0.0
var _pool: Array = []

static var _mesh: QuadMesh


func _ready() -> void:
	if not Events.area_exiting.is_connected(_on_area_exiting):
		Events.area_exiting.connect(_on_area_exiting)


func _process(delta: float) -> void:
	_t += delta
	if _t < float(MasteryData.HIGHLIGHT_REFRESH):
		return
	_t = 0.0
	if registry.is_empty():
		queue_free()
		return
	refresh()


## Re-picks the sparkling nodes around `center` (default: Krystal) and moves the pool. Off (all hidden) while
## the rank reward is not reached, the journey is not active or there is no player.
func refresh(center: Variant = null) -> void:
	refreshes += 1
	var picks: Array = []
	var radius := Mastery.highlight_radius()
	if radius > 0.0 and GameState.active:
		var c: Variant = center if center is Vector3 else _player_pos()
		if c is Vector3:
			picks = candidates(registry, c, radius, int(MasteryData.HIGHLIGHT_MAX))
	shown = picks
	if picks.is_empty() and _pool.is_empty():
		return
	_ensure_pool()
	for i in _pool.size():
		var mi: MeshInstance3D = _pool[i]
		if i < picks.size():
			var n: Node = picks[i]
			mi.global_position = n.call("sparkle_point") if n.has_method("sparkle_point") else (n as Node3D).global_position + Vector3.UP
			mi.visible = true
		else:
			mi.visible = false


## Pure selection over `nodes` (resource nodes, duck typed: depleted / kind / global_position): up to `cap`
## non-depleted harvestables within `radius` of `center`, special materials first, then nearest first.
static func candidates(nodes: Array, center: Vector3, radius: float, cap: int) -> Array:
	var r2 := radius * radius
	var scored: Array = []
	for n in nodes:
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var node := n as Node3D
		var d2 := node.global_position.distance_squared_to(center)
		if d2 > r2:
			continue
		var dep: Variant = node.get("depleted")
		if (dep is bool and dep) or not node.is_in_group("harvestable"):
			continue
		var kind := String(node.get("kind"))
		if MasteryData.HIGHLIGHT_SKIP_KINDS.has(kind):
			continue
		scored.append([d2 + (1.0e6 if MasteryData.SPOT_SKIP_KINDS.has(kind) else 0.0), node])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var out: Array = []
	for i in mini(scored.size(), maxi(cap, 0)):
		out.append(scored[i][1])
	return out


## Number of sparkle quads visible right now (tests).
func visible_count() -> int:
	var n := 0
	for mi in _pool:
		if (mi as MeshInstance3D).visible:
			n += 1
	return n


func hide_all() -> void:
	shown = []
	for mi in _pool:
		(mi as MeshInstance3D).visible = false


func _on_area_exiting(_area_id: String = "") -> void:
	hide_all()


func _player_pos() -> Variant:
	var p: Variant = Game.player
	if p is Node3D and is_instance_valid(p) and (p as Node3D).is_inside_tree():
		return (p as Node3D).global_position
	return null


func _ensure_pool() -> void:
	if not _pool.is_empty():
		return
	var mesh := _shared_mesh()
	for i in int(MasteryData.HIGHLIGHT_MAX):
		var mi := MeshInstance3D.new()
		mi.name = "Sparkle%d" % i
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pool.append(mi)


## One quad + one unshaded billboard material for every sparkle (built once).
static func _shared_mesh() -> QuadMesh:
	if _mesh != null:
		return _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	mat.albedo_texture = _star_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var q := QuadMesh.new()
	q.size = Vector2(QUAD_SIZE, QUAD_SIZE)
	q.material = mat
	_mesh = q
	return q


## A soft warm glow with a four-point star (generated once, no image files).
static func _star_texture() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := float(TEX_SIZE - 1) * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var u := (float(x) - half) / half
			var v := (float(y) - half) / half
			var r := sqrt(u * u + v * v)
			var glow := pow(clampf(1.0 - r, 0.0, 1.0), 2.0) * 0.5
			var arm_h := clampf(1.0 - absf(v) * 9.0 - absf(u) * 1.05, 0.0, 1.0)
			var arm_v := clampf(1.0 - absf(u) * 9.0 - absf(v) * 1.05, 0.0, 1.0)
			var core := clampf(1.0 - r * 4.0, 0.0, 1.0)
			var a := clampf(glow + maxf(arm_h, arm_v) * 0.9 + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.97, 0.84, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

extends Node3D
## The Lanternwake lantern at Lanternwake Commons (module C9; MP §9 / §11 step 20 / §17). Built by
## reach_dressing.gd once the Borrowed Choir is gone. Two looks:
##   * attach mode (setup {"attach": true}): the region already has a central lantern pole (Reach.COMMONS
##     "pole", built by src/world/reach/commons.gd); this node only adds the interaction, a soft festival glow
##     that swells when the chimes ring, and the high-visibility marker - no second pole, no extra collider;
##   * stand-alone (no region pole, e.g. the placeholder region): a tall wooden pole with a big paper-lantern
##     crown, four small lanterns on arms, ribbons and two pumpkins; setup {"candidates": [Vector2...]} - two
##     physics frames after entering the tree it stands on the first candidate with nothing solid around it.
## Interaction (group "interactable", layer-16 sphere):
##   Choir defeated, not home yet   -> "Celebrate the Lanternwake" greyed: bring the news home first
##   after the homecoming           -> "Celebrate the Lanternwake": a short confirm, then story_ch2.celebrate("commons")
##                                     (Game.complete_chapter_two: rewards committed and saved first)
##   after the Lanternwake          -> "Ring the festival chimes": friends nearby celebrate, the lantern glows up
##                                     and settles (a caption for the sound), and it is a lasting safe light
## Settings: high_visibility_cues adds a bold floating marker while celebrating is possible; nothing flashes.

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const FestivalLights := preload("res://src/world/story_ch2/festival_lights.gd")

const CROWN_Y := 3.55             # stand-alone crown height
const ATTACH_TOP := 6.4           # the region pole's cap is ~6.3 m high
const CLEAR_RADIUS := 1.0         # nothing solid within this of the pole between 0.5 m and 2.5 m up
const WORLD_MASK := 1 | 32
const TITLE := "The Lanternwake"
const ASK_TEXT := "Celebrate the Lanternwake here at the Commons? (You can also celebrate at home with the Ward Stone.)"
const NOT_YET := "Bring the news home to the Ward Stone first."
const CHIME_CAPTION := "[festival chimes ring across the Commons]"
const CELEBRATED_LIGHT_RADIUS := 9.0

var candidates: Array = []
var stage := 2
var attach := false
## Tests / scripted runs: the answer to the next confirm instead of asking the UI (consumed once).
var forced_choice: String = ""
var placed := false               # true once the placement is final
var light: OmniLight3D
var crown_material: StandardMaterial3D = null
var marker: MeshInstance3D
var body: StaticBody3D = null     # stand-alone only (the region pole is solid itself)
var interact_body: StaticBody3D
var light_radius: float = 0.0     # light-source contract (Combat.light_at): only after the Lanternwake
var _busy := false
var _t := 0.0
var _marker_t := 0.0
var _glow := 0.0
var _glow_tw: Tween


func setup(params: Dictionary) -> void:
	var c: Variant = params.get("candidates", [])
	candidates = (c as Array).duplicate() if c is Array else []
	stage = int(params.get("stage", stage))
	attach = bool(params.get("attach", false))


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("lanternwake_pole")
	if attach:
		_build_attached()
	else:
		_build_standalone()
	_build_common()
	if stage >= 3:
		light_radius = CELEBRATED_LIGHT_RADIUS
		add_to_group("light_source")
	if attach or candidates.is_empty():
		placed = true
	else:
		_place_when_settled.call_deferred()


func is_light_active() -> bool:
	return stage >= 3


func _base_light() -> float:
	if attach:
		return 0.35 if stage >= 3 else 0.0      # the region pole has its own lamp; this only adds festival warmth
	return 1.1 if stage >= 3 else 0.8


func _top() -> float:
	return ATTACH_TOP if attach else CROWN_Y + 0.7


# --- Look ----------------------------------------------------------------------------------------------------

func _build_attached() -> void:
	light = FestivalLights.warm_light(_base_light(), 10.0, Color("ffc98a"))
	light.name = "FestivalGlow"
	light.position = Vector3(0, 4.4, 0)
	add_child(light)


func _build_standalone() -> void:
	var wood := Mat.outlined(Mat.toon(Palette.WOOD_DARK, {"noise": 0.12}), 0.014)
	var stone := Mat.outlined(Mat.toon(Palette.STONE, {"noise": 0.15}), 0.014)
	Kit.add(self, Kit.cylinder(0.62, 0.7, 0.26, stone, 14), Vector3(0, 0.13, 0))
	Kit.add(self, Kit.cylinder(0.08, 0.12, 3.5, wood, 10), Vector3(0, 1.95, 0))
	# Four little arms with hanging lanterns (rose, lavender, cream, amber).
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		Kit.add(self, Kit.box(Vector3(0.9, 0.06, 0.06), wood), d * 0.42 + Vector3(0, 3.05, 0), Vector3(0, -rad_to_deg(a), 0))
	var small: Array = []
	for i in 4:
		var a2 := TAU * float(i) / 4.0 + PI * 0.25
		small.append({"pos": Vector3(cos(a2) * 0.82, 2.78, sin(a2) * 0.82), "color": FestivalLights.color_for(i + 1), "scale": 0.85, "yaw": a2})
	add_child(FestivalLights.lanterns(small, "ArmLanterns", 90.0))
	# The crown: one big paper lantern (its own material so it can glow brighter when the chimes ring).
	crown_material = StandardMaterial3D.new()
	crown_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crown_material.albedo_color = Color("ffc070") * 1.3
	var crown := MeshInstance3D.new()
	crown.name = "Crown"
	crown.mesh = FestivalLights.body_mesh()
	crown.material_override = crown_material
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(self, crown, Vector3(0, CROWN_Y, 0), Vector3.ZERO, Vector3(1.9, 1.9, 1.9))
	Kit.add(self, Kit.cylinder(0.14, 0.24, 0.16, Mat.toon(Palette.BARK_DARK), 10), Vector3(0, CROWN_Y + 0.6, 0))
	# Ribbons hanging from the crown (still shapes: no strobe, no motion sickness).
	var ribbon_cols := [Color("e98aa5"), Color("7d5a9a"), Color("f2a24a")]
	for i in 3:
		var a3 := TAU * float(i) / 3.0
		var rb := Kit.box(Vector3(0.1, 1.5, 0.02), Mat.toon(ribbon_cols[i], {"rim": 0.25}))
		Kit.add(self, rb, Vector3(cos(a3) * 0.3, CROWN_Y - 1.1, sin(a3) * 0.3), Vector3(0, -rad_to_deg(a3), 14))
		rb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Two pumpkins at its foot.
	var pumpkin := Mat.outlined(Mat.toon(Color("e8812f"), {"rim": 0.3}), 0.014)
	for i in 2:
		var pk := Kit.blob(0.26 - 0.06 * float(i), pumpkin, 811 + i, 0.12, 0.72, 2)
		Kit.add(self, pk, Vector3(0.62 - 1.2 * float(i), 0.2, 0.42 + 0.2 * float(i)))
	light = FestivalLights.warm_light(_base_light(), 11.0 if stage >= 3 else 7.0)
	light.name = "FestivalGlow"
	light.position = Vector3(0, CROWN_Y - 0.4, 0)
	add_child(light)
	body = StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.26
	cyl.height = 3.6
	cs.shape = cyl
	cs.position = Vector3(0, 1.8, 0)
	body.add_child(cs)
	add_child(body)


## The interaction sphere (layer 16) and the high-visibility marker, in both looks.
func _build_common() -> void:
	marker = MeshInstance3D.new()
	marker.name = "CueMarker"
	var pm := PrismMesh.new()
	pm.size = Vector3(0.5, 0.6, 0.12)
	marker.mesh = pm
	marker.material_override = Mat.outlined(Mat.glow(Color("fff1b0"), 2.0), 0.03)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.rotation_degrees = Vector3(180, 0, 0)
	add_child(marker)
	marker.position = Vector3(0, _top() + 0.65, 0)
	interact_body = StaticBody3D.new()
	interact_body.name = "Interact"
	interact_body.collision_layer = 16
	interact_body.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.5 if attach else 1.4
	ics.shape = sph
	ics.position = Vector3(0, 1.2, 0)
	interact_body.add_child(ics)
	add_child(interact_body)
	_update_marker()


func _process(delta: float) -> void:
	_t += delta
	if marker.visible:
		marker.position.y = _top() + 0.65 + sin(_t * 1.6) * 0.12
		marker.rotation.y = _t * 0.8
	if crown_material != null:
		var k := 1.3 + _glow * 0.6
		crown_material.albedo_color = Color(1.0 * k, 0.75 * k, 0.44 * k)
	if light != null:
		light.light_energy = _base_light() + _glow * (1.2 if attach else 0.6)
	_marker_t += delta
	if _marker_t >= 0.5:
		_marker_t = 0.0
		_update_marker()


func _update_marker() -> void:
	if marker != null:
		marker.visible = bool(Settings.get_value("high_visibility_cues")) and Story.can_celebrate()


# --- Placement (stand-alone only) --------------------------------------------------------------------------

## Waits for the region's colliders to be registered, then stands on the first clear candidate.
func _place_when_settled() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var best := choose_spot(get_world_3d().direct_space_state, candidates, _own_rids(), global_position.y)
	if best != Vector3.INF:
		global_position = best
	placed = true


func _own_rids() -> Array:
	var out: Array = []
	for b in [body, interact_body]:
		if b != null and is_instance_valid(b):
			out.append((b as CollisionObject3D).get_rid())
	return out


## The first candidate with nothing solid within CLEAR_RADIUS between 0.5 m and 2.5 m above its ground, the
## ground found by a ray down (world layer). Vector3.INF when none is clear (the pole keeps its spot).
static func choose_spot(space: PhysicsDirectSpaceState3D, cands: Array, exclude: Array, fallback_y: float) -> Vector3:
	if space == null:
		return Vector3.INF
	var shape := CylinderShape3D.new()
	shape.radius = CLEAR_RADIUS
	shape.height = 2.0
	for c in cands:
		if not (c is Vector2):
			continue
		var p: Vector2 = c
		var ground := fallback_y
		var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x, fallback_y + 40.0, p.y), Vector3(p.x, fallback_y - 40.0, p.y), 1)
		ray.exclude = exclude
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			ground = (hit["position"] as Vector3).y
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, ground + 1.5, p.y))
		q.collision_mask = WORLD_MASK
		q.exclude = exclude
		if space.intersect_shape(q, 1).is_empty():
			return Vector3(p.x, ground, p.y)
	return Vector3.INF


# --- Interaction --------------------------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if Story.flag(Story.COMPLETE_FLAG):
		return {"text": "Ring the festival chimes", "enabled": true}
	if Story.can_celebrate():
		return {"text": "Celebrate the Lanternwake", "enabled": true}
	return {"text": "Celebrate the Lanternwake", "enabled": false, "reason": NOT_YET}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	if Story.flag(Story.COMPLETE_FLAG):
		ring_chimes()
		return
	if not Story.can_celebrate():
		Events.notify.emit(NOT_YET, "info")
		return
	var pick := await _ask(_player)
	if not is_instance_valid(self) or pick != "celebrate":
		return
	_busy = true
	await Story.celebrate("commons")
	if is_instance_valid(self):
		_busy = false


func _ask(who: Node) -> String:
	if forced_choice != "":
		var f := forced_choice
		forced_choice = ""
		return f
	var ui: Node = Game.ui
	if who == null or ui == null or not is_instance_valid(ui) or not ui.has_method("confirm") or Game.mode != "playing":
		return "cancel"
	_busy = true
	var pick: Variant = await ui.confirm(TITLE, ASK_TEXT, [["celebrate", "Celebrate", "AccentButton"], ["cancel", "Not yet", ""]])
	if is_instance_valid(self):
		_busy = false
	return String(pick) if (pick is String or pick is StringName) else "cancel"


## A pleasant, repeatable interaction after the Lanternwake: the lantern glows up and settles (no flash),
## a caption for the chime sound, and any friend within 14 m celebrates.
func ring_chimes() -> void:
	Audio.play_3d("checkpoint_light", global_position + Vector3.UP * _top(), -4.0)
	Events.caption.emit(CHIME_CAPTION)
	if _glow_tw != null and _glow_tw.is_valid():
		_glow_tw.kill()
	_glow_tw = create_tween()
	_glow_tw.tween_property(self, "_glow", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	_glow_tw.tween_property(self, "_glow", 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	for id in Game.companion_nodes:
		var c: Variant = Game.companion_nodes[id]
		if c != null and is_instance_valid(c) and c is Node3D and (c as Node3D).is_inside_tree() \
				and (c as Node3D).global_position.distance_to(global_position) < 14.0 and (c as Node).has_method("react"):
			(c as Node).react("celebrate")

extends Node3D
## The Lanternwake waygate: two old standing stones under a lintel. One stands north of the Moonlit Ruin
## in Hollowhaven Woods (side "surface", placed by src/world/surface/annexes.gd), its mirror behind the
## arrival point of Hallowmere Reach (side "reach"). Interaction contract: group "interactable" + a
## layer-16 sphere; solid pillars on layer 1. Surface states (flags, docs/CHAPTER_TWO_SPEC.md 7.1):
##   cold    - before chapter_one_complete: mossy old stones, a flavour line, nothing to do
##   dormant - chapter_one_complete, not ch2_accepted: "a dormant waygate" that points to the Ward Stone
##   woken   - ch2_accepted: "Repair the waygate (8 Wood, 4 Stone, 2 Copper Ore)", transactional (every
##             cost is checked before anything is taken) -> flag ch2_waygate_repaired + a light-up effect
##   lit     - ch2_waygate_repaired: "Travel to Hallowmere Reach" -> Game.change_area(target)
## The Reach side is always lit and always leads home ("Return to Hollowhaven Woods"), so Krystal can
## never be trapped across the boundary. Travel only ever happens from interact(): never automatically.
##   setup({"side": "surface"|"reach", "target_area": String, "target_spawn": String})

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")
const Fx := preload("res://src/world/common/fx.gd")

const REPAIRED_FLAG := "ch2_waygate_repaired"
const ACCEPTED_FLAG := "ch2_accepted"
const AVAILABLE_FLAG := "chapter_one_complete"
## Repair cost (MP §11 step 2). Order = order shown in the prompt.
const REPAIR_COST := [["wood", 8], ["stone", 4], ["copper_ore", 2]]
const PILLAR_X := 1.55
const PILLAR_SIZE := Vector3(0.85, 3.1, 0.75)
const GLOW := Color("ffc978")
## Radius of the ground the gate occupies (pillars + plinths); used by placement checks.
const FOOTPRINT_RADIUS := 2.4

var side: String = "surface"
var target_area: String = "hallowmere_reach"
var target_spawn: String = "waygate_arrival"

var rune_material: StandardMaterial3D
var veil_material: StandardMaterial3D
var light: OmniLight3D
var vines: Node3D
var veil: MeshInstance3D
var _glow := 0.0             # 0 = cold, ~0.35 = woken shimmer, 1 = lit
var _t := 0.0
var _busy := false
var _tw: Tween


func setup(params: Dictionary) -> void:
	side = String(params.get("side", side))
	if side == "reach":
		target_area = "surface"
		target_spawn = "waygate"
	target_area = String(params.get("target_area", target_area))
	target_spawn = String(params.get("target_spawn", target_spawn))


func _ready() -> void:
	name = "Waygate" if side == "surface" else "WaygateMirror"
	add_to_group("interactable")
	add_to_group("waygate")
	_build()
	_apply_state(true)
	if not Events.flag_set.is_connected(_on_flag_set):
		Events.flag_set.connect(_on_flag_set)


# --- State ------------------------------------------------------------------------------------------

## "cold" | "dormant" | "woken" | "lit" (the Reach side is always "lit").
func state() -> String:
	if side != "surface":
		return "lit"
	if bool(GameState.get_flag(REPAIRED_FLAG)):
		return "lit"
	if bool(GameState.get_flag(ACCEPTED_FLAG)):
		return "woken"
	if bool(GameState.get_flag(AVAILABLE_FLAG)):
		return "dormant"
	return "cold"


## Items still missing for the repair: {item_id: missing count} (empty = she has everything).
static func missing_materials() -> Dictionary:
	var out := {}
	for c in REPAIR_COST:
		var have: int = GameState.count_item(String(c[0]))
		if have < int(c[1]):
			out[String(c[0])] = int(c[1]) - have
	return out


static func cost_text() -> String:
	var parts: Array = []
	for c in REPAIR_COST:
		parts.append("%d %s" % [int(c[1]), ItemDB.display_name(String(c[0]))])
	return ", ".join(parts)


static func _missing_text(missing: Dictionary) -> String:
	var parts: Array = []
	for c in REPAIR_COST:
		var id := String(c[0])
		if missing.has(id):
			parts.append("%d more %s" % [int(missing[id]), ItemDB.display_name(id)])
	return "Needs " + ", ".join(parts)


func _on_flag_set(flag: String, _value: Variant) -> void:
	if flag == REPAIRED_FLAG or flag == ACCEPTED_FLAG or flag == AVAILABLE_FLAG:
		_apply_state(false)


# --- Interaction -------------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	match state():
		"cold":
			return {"text": "Look at the old standing stones", "enabled": true}
		"dormant":
			return {"text": "Examine the dormant waygate", "enabled": true}
		"woken":
			var text := "Repair the waygate (%s)" % cost_text()
			var missing := missing_materials()
			if missing.is_empty():
				return {"text": text, "enabled": true}
			return {"text": text, "enabled": false, "reason": _missing_text(missing)}
	if side == "surface":
		return {"text": "Travel to Hallowmere Reach", "enabled": true}
	return {"text": "Return to Hollowhaven Woods", "enabled": true}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	match state():
		"cold":
			Events.say.emit("", "Two old standing stones under a mossy lintel, cold to the touch. Whatever they once framed is long asleep.", 5.5)
		"dormant":
			Events.say.emit("", "A dormant waygate. Its runes are dark, as if waiting for word from the Ward Stone at home.", 5.5)
		"woken":
			repair()
		_:
			travel()


## Takes the repair cost only if EVERY item is there (nothing is taken otherwise), then lights the gate.
## Returns true when the gate was repaired by this call.
func repair() -> bool:
	if state() != "woken":
		return false
	var missing := missing_materials()
	if not missing.is_empty():
		Events.notify.emit(_missing_text(missing) + " to repair the waygate.", "warn")
		return false
	var taken: Array = []
	for c in REPAIR_COST:
		if GameState.take_item(String(c[0]), int(c[1])):
			taken.append(c)
		else:
			# Should never happen after the check above; put back anything already taken.
			for t in taken:
				GameState.give_item(String(t[0]), int(t[1]))
			Events.notify.emit("The waygate couldn't be repaired right now.", "warn")
			return false
	GameState.set_flag(REPAIRED_FLAG, true)
	_play_light_up()
	Events.notify.emit("The Lanternwake waygate glows again. The road to Hallowmere Reach is open.", "success")
	return true


func travel() -> void:
	if state() != "lit" or target_area == "":
		return
	if Game.mode != "playing":
		return
	_busy = true
	if Audio.has_method("play_3d"):
		Audio.play_3d("gate_unlock", global_position + Vector3.UP * 1.5, -6.0)
	await Game.change_area(target_area, target_spawn)
	if is_instance_valid(self):
		_busy = false


# --- Visuals ------------------------------------------------------------------------------------------

func _build() -> void:
	var stone_mat := NodeVisuals.rock_material(0.03)
	var tint := Color("a7a393") if side == "surface" else Color("b39a86")
	for sx in [-1.0, 1.0]:
		var x: float = sx * PILLAR_X
		var plinth := Props.instance(Props.stone_block(31 + int(sx), Vector3(1.3, 0.35, 1.15), Palette.STONE_DARK, 0.4), stone_mat, 140.0)
		plinth.position = Vector3(x, -0.15, 0)
		add_child(plinth)
		var pillar := Props.instance(Props.stone_block(33 + int(sx), PILLAR_SIZE, tint, 0.7), stone_mat, 160.0)
		pillar.position = Vector3(x, 0.05, 0)
		pillar.rotation.y = deg_to_rad(4.0 * sx)
		add_child(pillar)
	var lintel := Props.instance(Props.stone_block(36, Vector3(4.3, 0.55, 0.9), tint.lightened(0.04), 0.8), stone_mat, 160.0)
	lintel.position = Vector3(0, 3.05, 0)
	lintel.rotation.z = deg_to_rad(-2.0)
	add_child(lintel)
	# Runes carved into both pillars and the lintel (one material so the glow can breathe).
	rune_material = StandardMaterial3D.new()
	rune_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_material.albedo_color = Palette.STONE_DARK
	var runes := NodeVisuals.Merger.new()
	var front := 0.39
	for sx in [-1.0, 1.0]:
		var x: float = sx * PILLAR_X
		runes.add(NodeVisuals._box(Vector3(0.06, 0.5, 0.04)), Transform3D(Basis(), Vector3(x, 1.9, front)), Color.WHITE)
		runes.add(NodeVisuals._box(Vector3(0.3, 0.06, 0.04)), Transform3D(Basis(), Vector3(x, 1.55, front)), Color.WHITE)
		runes.add(NodeVisuals._box(Vector3(0.06, 0.3, 0.04)), Transform3D(Basis(Vector3.BACK, 0.6 * sx), Vector3(x, 1.15, front)), Color.WHITE)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.2
	tor.outer_radius = 0.26
	tor.rings = 18
	tor.ring_segments = 6
	runes.add(tor, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(0, 3.05, 0.47)), Color.WHITE)
	var runes_mi := MeshInstance3D.new()
	runes_mi.mesh = runes.commit()
	runes_mi.material_override = rune_material
	runes_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(runes_mi)
	# Two small lanterns hanging from the lintel.
	for sx in [-1.0, 1.0]:
		var glass := MeshInstance3D.new()
		glass.mesh = Props.lantern_glass()
		glass.material_override = rune_material
		glass.position = Vector3(sx * 1.05, 2.45, 0.2)
		add_child(glass)
		var cap := Kit.cylinder(0.02, 0.15, 0.1, Palette.WOOD_DARK, 8)
		cap.position = Vector3(sx * 1.05, 2.6, 0.2)
		add_child(cap)
	# The shimmer between the stones (only once repaired).
	veil_material = Mat.transparent(Color(GLOW.r, GLOW.g, GLOW.b, 0.0), true)
	veil = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.7)
	veil.mesh = q
	veil.material_override = veil_material
	veil.position = Vector3(0, 1.45, 0)
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(veil)
	# Vines draped over the dormant gate.
	vines = Node3D.new()
	vines.name = "Vines"
	add_child(vines)
	var vine_mat := Mat.outlined(Mat.toon(Palette.FOLIAGE_DARK, {"noise": 0.2, "noise_scale": 2.2, "rim": 0.25}), 0.016)
	var spots := [Vector3(-1.4, 3.2, 0.3), Vector3(-0.5, 3.35, 0.25), Vector3(0.9, 3.25, 0.35), Vector3(1.7, 2.6, 0.35), Vector3(-1.8, 1.9, 0.3), Vector3(1.5, 0.9, 0.4)]
	for i in spots.size():
		var vb := MeshInstance3D.new()
		vb.mesh = Kit.blob_mesh(0.3 + float(i % 3) * 0.06, 9300 + i, 0.4, 0.55, 1)
		vb.material_override = vine_mat
		vb.position = spots[i]
		vines.add_child(vb)
	# Collision: the two pillars on the world layer; an interaction sphere between them.
	var body := StaticBody3D.new()
	body.name = "Stones"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	add_child(body)
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(PILLAR_SIZE.x, PILLAR_SIZE.y + 0.2, PILLAR_SIZE.z)
		cs.shape = box
		cs.position = Vector3(float(sx) * PILLAR_X, PILLAR_SIZE.y * 0.5, 0)
		body.add_child(cs)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.6
	ics.shape = sph
	ics.position = Vector3(0, 1.2, 0.2)
	ib.add_child(ics)
	add_child(ib)
	light = OmniLight3D.new()
	light.light_color = GLOW
	light.omni_range = 7.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position = Vector3(0, 2.2, 0.9)
	add_child(light)


## Brightness target for the current state (0 cold/dormant, a faint shimmer when woken, 1 lit).
func _target_glow() -> float:
	match state():
		"lit":
			return 1.0
		"woken":
			return 0.3
	return 0.0


func _apply_state(instant: bool) -> void:
	var s := state()
	if vines != null:
		vines.visible = s != "lit"
	if instant:
		_glow = _target_glow()
	elif _tw == null or not _tw.is_valid():
		_tw = create_tween()
		_tw.tween_property(self, "_glow", _target_glow(), 1.2).set_trans(Tween.TRANS_SINE)
	_apply_glow(0.5)


func _apply_glow(pulse: float) -> void:
	var g := _glow
	if rune_material != null:
		var c := Palette.STONE_DARK.lerp(GLOW, clampf(g, 0.0, 1.0))
		var k := 1.0 + g * (0.35 + pulse * 0.15)
		rune_material.albedo_color = Color(c.r * k, c.g * k, c.b * k)
	if veil_material != null:
		veil_material.albedo_color.a = clampf((g - 0.6) / 0.4, 0.0, 1.0) * (0.16 + pulse * 0.06)
	if veil != null:
		veil.visible = g > 0.6
	if light != null:
		light.light_energy = g * (0.9 + pulse * 0.2)
		light.visible = g > 0.05


func _process(delta: float) -> void:
	_t += delta
	if _glow <= 0.001:
		return
	_apply_glow(0.5 + 0.5 * sin(_t * 1.4))


func _play_light_up() -> void:
	if vines != null:
		vines.visible = false
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_glow = 0.3
	_tw = create_tween()
	_tw.tween_property(self, "_glow", 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if is_inside_tree():
		Fx.burst(get_parent(), global_position + Vector3(0, 1.6, 0.3), "sparkle", 2.0)
		Fx.burst(get_parent(), global_position + Vector3(0, 0.3, 0.3), "leaves", 1.0)
		if Audio.has_method("play_3d"):
			Audio.play_3d("checkpoint_light", global_position + Vector3.UP * 1.5, -2.0)
	Events.caption.emit("[The old stones hum and the lanterns catch]")

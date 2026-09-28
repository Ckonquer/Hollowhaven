extends Node3D
## Pumpkintide Orchard (Hallowmere Reach district, module C2; MP §9 / §11 step 5 / §12 / §14 / §16 / §17).
## Oversized pumpkins, roseberry rows along crooked fences, amber puddles, little harmless scarecrows, and:
##   * Irrigation (irrigation.gd): a cistern, a flume, two readable sluice levers (a big painted arrow on the
##     junction shows where the water goes; the garden gate paddle visibly rises), flowing water you can see.
##   * The festival garden: a raised bed that is dry until irrigated, a seed box holding the garden note
##     (lore_ch2_garden_note, read when she opens it) and the guaranteed festival seed (planted from the same box
##     once the bed is watered: a short scripted growth beat), a painted garden sign and the garden lamp.
##   * The garden lamp: flag ch2_found_orchard_lamp when she first approaches / sees it; lighting it needs the
##     irrigation repaired (Data.FLAG_IRRIGATED) AND the mimic pocket cleared (Data.FLAG_MIMICS_CLEARED) and sets
##     ch2_garden_lamp_lit ONCE. The Chapter Two quest layer pays rw_ch2_orchard (seal, seeds, recipes).
##   * The taught Pumpkin Mimic pocket (mimic_pocket.gd) and a separate, optional Patchwalker field
##     (spawner hr_sp_orchard_patchwalkers, guarded when the enemy script is missing).
##   * "The Pumpkin That Turned" (pumpkin_moment.gd) beside the arch lane.
##   * Renewable wild pumpkins hr_pumpkin_<n>, roseberry hedges hr_roseberry_<n>, wild sunflax hr_sunflax_<n> and two
##     marked sap stumps hr_resin_0/1 (shared resource_node; a tapped stump keeps standing, only its pail empties).
## Built once by districts/orchard.gd behind the load fade; all content in WORLD coordinates under this node
## (which stays at the origin). One throttled tick (5 Hz) drives the lamp discovery, the moment and the pocket.

const Data := preload("res://data/reach_west.gd")
const Art := preload("res://src/world/reach/west/west_art.gd")
const B := preload("res://src/world/reach/west/west_build.gd")
const Irrigation := preload("res://src/world/reach/west/irrigation.gd")
const WestInteractable := preload("res://src/world/reach/west/west_interactable.gd")
const MomentScript := preload("res://src/world/reach/west/pumpkin_moment.gd")
const PocketScript := preload("res://src/world/reach/west/mimic_pocket.gd")
const Props := preload("res://src/world/surface/props.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const Fx := preload("res://src/world/common/fx.gd")

const TICK := 0.2
const LUMI_LAMP_LINE := "Lumi's light answers the lantern, warm and gold."
const GROW_SECONDS := 3.2

var area: Node3D = null
var player_override: Node3D = null
var screen_override: int = -1         # tests: 0 = off screen, 1 = on screen, -1 = ask the camera
var build_ms: int = 0
var nodes: Dictionary = {}            # harvest node id -> resource node
var spawners: Dictionary = {}         # spawner id -> EnemySpawner (null while its enemy script is missing)
var irrigation: Dictionary = {}
var water: Dictionary = {}            # flow part -> MeshInstance3D
var interactables: Dictionary = {}    # id -> west_interactable
var moment: Node3D = null
var mimic_pocket: Node3D = null
var solids: StaticBody3D = null
var growing: bool = false
var instant_growth: bool = false      # tests: skip the growth beat tween

var _arrow: Node3D
var _junction_arm: Node3D
var _gate_arm: Node3D
var _paddle: Node3D
var _lamp_glass: MeshInstance3D
var _lamp_light: OmniLight3D
var _bed_soil: MeshInstance3D
var _festival: Node3D
var _festival_sprout: Node3D
var _festival_vine: Node3D
var _festival_pumpkin: Node3D
var _t: float = 0.0


func setup(p_area: Node3D) -> void:
	area = p_area


func build() -> void:
	var t0 := Time.get_ticks_usec()
	name = "District_Orchard"
	solids = B.solid_body(self, "OrchardSolids", "wood")
	_build_harvest_nodes()
	_build_irrigation()
	_build_garden()
	_build_decor()
	_build_pockets()
	_build_moment()
	irrigation = Irrigation.load_state()
	_apply_irrigation(false)
	_apply_lamp(false)
	_apply_festival(false)
	build_ms = int((Time.get_ticks_usec() - t0) / 1000)


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	var dt := _t
	_t = 0.0
	tick(dt)


## One throttled step (public for tests): lamp discovery, the turning pumpkin, the mimic pocket.
func tick(dt: float) -> void:
	var pp: Variant = player_position()
	if not (pp is Vector3):
		return
	var p: Vector3 = pp
	_check_lamp_found(p)
	if moment != null and moment.phase != MomentScript.DONE:
		moment.check(p, is_on_screen(moment.global_position + Vector3.UP * 0.7))
	if mimic_pocket != null:
		mimic_pocket.tick(p, dt)


func player_position() -> Variant:
	if player_override != null and is_instance_valid(player_override):
		return player_override.global_position
	var pl: Node3D = Game.player
	if pl != null and is_instance_valid(pl) and pl.is_inside_tree() and Game.area == area:
		return pl.global_position
	return null


func is_on_screen(pos: Vector3) -> bool:
	if screen_override >= 0:
		return screen_override == 1
	var pl: Node3D = Game.player
	if pl == null or not is_instance_valid(pl) or not pl.has_method("get_camera"):
		return false
	var cam: Camera3D = pl.get_camera()
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return false
	return not cam.is_position_behind(pos) and cam.is_position_in_frustum(pos)


# --- Harvest nodes --------------------------------------------------------------------------------------

func _build_harvest_nodes() -> void:
	var holder := Node3D.new()
	holder.name = "Harvest"
	add_child(holder)
	for e in Data.nodes_in(Data.ORCHARD):
		nodes[String(e["id"])] = B.harvest_node(holder, area, e)
	B.sap_stump_decor(self, solids, area, Data.ORCHARD)


# --- Irrigation -------------------------------------------------------------------------------------------

func _build_irrigation() -> void:
	var prop := Art.prop_material()
	var irr: Dictionary = Data.IRRIGATION
	var cp: Vector2 = irr["cistern"]
	var trunk_dir: Vector2 = (Data.FLUME_SEGMENTS[0][2] as Vector2) - (Data.FLUME_SEGMENTS[0][1] as Vector2)
	B.mesh_at(self, Art.cistern(), prop, Transform3D(Basis(Vector3.UP, atan2(trunk_dir.x, trunk_dir.y)), B.ground(area, cp)), "Cistern")
	B.cylinder(solids, B.ground(area, cp, -0.1), 1.4, 1.0)
	# Flume troughs (visual only: a shallow wooden channel she can step over) and the water inside them.
	var pieces: Array = []
	for seg in Data.FLUME_SEGMENTS:
		var a: Vector2 = seg[1]
		var b: Vector2 = seg[2]
		var dir := (b - a).normalized()
		var n := maxi(1, int(ceil(a.distance_to(b))))
		var step := a.distance_to(b) / float(n)
		for k in n:
			var p := a + dir * (float(k) * step)
			var h := B.height(area, p + dir * step * 0.5)
			pieces.append(Transform3D(Basis(Vector3.UP, B.yaw_to(a, b)) * Basis.from_scale(Vector3(1.0, 1.0, step)), Vector3(p.x, h, p.y)))
		var wm := MeshInstance3D.new()
		wm.name = "Water_" + String(seg[0])
		wm.mesh = B.draped_strip(area, [a, b], 0.52, 0.13, 0.9)
		wm.material_override = Art.flow_material()
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wm)
		water[String(seg[0])] = wm
	B.multi(self, Art.flume_piece(), prop, pieces, "Flume", 90.0)
	# The drain pond (starts full: this is where the water goes wrong) and the spill puddle before the gate.
	var dp: Vector2 = irr["drain_pond"]
	var mud := MeshInstance3D.new()
	mud.name = "DrainMud"
	mud.mesh = B.draped_disc(area, dp, float(irr["drain_pond_radius"]) + 0.4, 0.02)
	mud.material_override = Art.tinted(Art.SOIL, 0.0, 0.1)
	mud.position = B.ground(area, dp)
	mud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mud)
	water["drain_pond"] = _pool(dp, float(irr["drain_pond_radius"]), 0.06, "Water_drain_pond")
	water["spill"] = _pool(irr["spill"], float(irr["spill_radius"]), 0.05, "Water_spill")
	# Lever 1: the junction sluice. Its painted arrow board swings to point along the branch the water takes.
	var jp: Vector2 = irr["junction"]
	var lj: Vector2 = irr["lever_junction"]
	_junction_arm = _lever(lj, jp, "junction")
	_arrow = Node3D.new()
	_arrow.name = "JunctionArrow"
	_arrow.position = B.ground(area, jp, 0.55)
	add_child(_arrow)
	var am := MeshInstance3D.new()
	am.mesh = Art.arrow_board()
	am.material_override = prop
	_arrow.add_child(am)
	var hub := MeshInstance3D.new()
	hub.mesh = Art.cyl_mesh(0.07, 0.55)
	hub.material_override = Art.tinted(Art.IRON)
	hub.position = Vector3(0, -0.27, 0)
	_arrow.add_child(hub)
	# Lever 2: the garden sluice gate across the garden branch; the paddle rises when opened.
	var gp: Vector2 = irr["gate"]
	var ga: Vector2 = Data.FLUME_SEGMENTS[2][1]
	var gyaw := B.yaw_to(ga, gp)          # local X spans the flume, the paddle blocks it
	B.mesh_at(self, Art.gate_frame(), prop, Transform3D(Basis(Vector3.UP, gyaw), B.ground(area, gp)), "GateFrame")
	_paddle = Node3D.new()
	_paddle.name = "GatePaddle"
	_paddle.transform = Transform3D(Basis(Vector3.UP, gyaw), B.ground(area, gp, 0.02))
	add_child(_paddle)
	var pm := MeshInstance3D.new()
	pm.mesh = Art.gate_paddle()
	pm.material_override = prop
	_paddle.add_child(pm)
	var gb := Basis(Vector3.UP, gyaw)
	for sx in [-1.0, 1.0]:
		B.box(solids, B.ground(area, gp) + gb * Vector3(float(sx) * 0.5, 0.65, 0), Vector3(0.16, 1.3, 0.18), gb)
	_gate_arm = _lever(irr["lever_gate"], gp, "gate")


func _pool(center: Vector2, radius: float, lift: float, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = B.draped_disc(area, center, radius, lift)
	mi.material_override = Art.pool_material()
	mi.position = B.ground(area, center)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A lever post facing the thing it controls; returns the arm pivot. Adds its interactable.
func _lever(p: Vector2, look: Vector2, id: String) -> Node3D:
	var prop := Art.prop_material()
	var yaw := B.yaw_to(p, look)
	var root := Node3D.new()
	root.name = "Lever_" + id
	root.transform = Transform3D(Basis(Vector3.UP, yaw), B.ground(area, p))
	add_child(root)
	var post := MeshInstance3D.new()
	post.mesh = Art.lever_post()
	post.material_override = prop
	root.add_child(post)
	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0, 0.95, 0)
	root.add_child(arm)
	var armm := MeshInstance3D.new()
	armm.mesh = Art.lever_arm()
	armm.material_override = prop
	arm.add_child(armm)
	B.cylinder(solids, B.ground(area, p), 0.2, 1.1)
	var it: Node3D = WestInteractable.new()
	it.setup({"id": "lever_" + id, "size": Vector3(1.3, 1.6, 1.3), "offset": Vector3(0, 0.8, 0),
		"text_func": Callable(self, "_lever_text").bind(id), "handler": Callable(self, "pull_lever").bind(id),
		"marker": true, "marker_radius": 0.8})
	root.add_child(it)
	interactables["lever_" + id] = it
	return arm


func _lever_text(id: String) -> Dictionary:
	if id == "junction":
		if String(irrigation.get("junction", "drain")) == "garden":
			return {"text": "Turn the junction sluice: send the water to the drain pond", "enabled": true}
		return {"text": "Turn the junction sluice: send the water toward the garden", "enabled": true}
	if bool(irrigation.get("gate", false)):
		return {"text": "Lower the garden sluice gate", "enabled": true}
	return {"text": "Raise the garden sluice gate", "enabled": true}


## Pulls a sluice lever ("junction" or "gate"). Returns the new irrigation state. The handler signature
## (player, id) comes from the interactable binding.
func pull_lever(_player: Node = null, id: String = "junction") -> Dictionary:
	if id == "junction":
		irrigation = Irrigation.toggle_junction(irrigation)
	else:
		irrigation = Irrigation.toggle_gate(irrigation)
	var latched := Irrigation.store_state(irrigation)
	_apply_irrigation(true)
	var at: Vector2 = Data.IRRIGATION["lever_" + id]
	if is_inside_tree():
		Audio.play_3d("door_creak", B.ground(area, at, 1.0), -4.0)
		Audio.play_3d("water_drip", B.ground(area, Data.IRRIGATION["junction"], 0.4), -2.0)
	Events.caption.emit("[The sluice creaks. %s]" % Irrigation.describe(irrigation))
	if latched:
		Events.notify.emit("Water reaches the festival garden!", "success")
		Events.hint.emit("hr_garden_watered", "The festival bed is damp now: plant the festival seed, then see to the garden lamp.")
		_apply_festival(false)
	return irrigation


## Puts both levers back to their starting positions (the "repaired" latch stays). Tests / QA.
func reset_irrigation() -> Dictionary:
	irrigation = Irrigation.reset()
	_apply_irrigation(false)
	return irrigation


func _apply_irrigation(animate: bool) -> void:
	var f := Irrigation.flow(irrigation)
	for part in water:
		var mi: MeshInstance3D = water[part]
		var on := bool(f.get(part, false))
		if animate and on and not mi.visible and mi.is_inside_tree():
			Fx.burst(self, _part_point(String(part)) + Vector3.UP * 0.3, "splash", 0.7)
		mi.visible = on
	var to_garden := String(irrigation.get("junction", "drain")) == "garden"
	var jp: Vector2 = Data.IRRIGATION["junction"]
	var target: Vector2 = Data.FLUME_SEGMENTS[2][2] if to_garden else Data.FLUME_SEGMENTS[1][2]
	if _arrow != null:
		_arrow.rotation.y = B.yaw_to(jp, target)
	if _junction_arm != null:
		_junction_arm.rotation.x = -0.6 if to_garden else 0.6
	var gate := bool(irrigation.get("gate", false))
	if _gate_arm != null:
		_gate_arm.rotation.x = -0.6 if gate else 0.6
	if _paddle != null:
		var base := B.ground(area, Data.IRRIGATION["gate"], 0.02)
		_paddle.position = base + Vector3(0, 0.62 if gate else 0.0, 0)
	if _bed_soil != null:
		_bed_soil.material_override = Art.tinted(Art.SOIL, 0.0, 0.25) if Irrigation.is_repaired() else Art.tinted(Art.SOIL_DRY, 0.0, 0.15)


func _part_point(part: String) -> Vector3:
	for seg in Data.FLUME_SEGMENTS:
		if String(seg[0]) == part:
			return B.ground(area, seg[1])
	if part == "drain_pond":
		return B.ground(area, Data.IRRIGATION["drain_pond"])
	return B.ground(area, Data.IRRIGATION["spill"])


# --- The festival garden, seed and lamp -----------------------------------------------------------------------

func _build_garden() -> void:
	var prop := Art.prop_material()
	var g: Dictionary = Data.GARDEN
	var bp: Vector2 = g["bed"]
	var bs: Vector2 = g["bed_size"]
	var bg := B.ground(area, bp)
	B.mesh_at(self, Art.bed_frame(bs), prop, Transform3D(Basis(), bg), "FestivalBed")
	_bed_soil = MeshInstance3D.new()
	_bed_soil.name = "BedSoil"
	_bed_soil.mesh = Art.box_mesh(Vector3(bs.x - 0.1, 0.1, bs.y - 0.1))
	_bed_soil.position = bg + Vector3(0, 0.3, 0)
	add_child(_bed_soil)
	B.box(solids, bg + Vector3(0, 0.2, 0), Vector3(bs.x + 0.12, 0.4, bs.y + 0.12))
	# The festival plant grows here (hidden until planted).
	_festival = Node3D.new()
	_festival.name = "FestivalPlant"
	_festival.position = bg + Vector3(0, 0.35, 0)
	add_child(_festival)
	_festival_sprout = _child_mesh(_festival, Art.pumpkin_stem(false), prop, Vector3.ZERO, 0.6)
	_festival_vine = _child_mesh(_festival, Art.festival_vine(), Art.sway_material(0.03, 0.4), Vector3.ZERO, 1.0)
	_festival_pumpkin = Node3D.new()
	_festival.add_child(_festival_pumpkin)
	_child_mesh(_festival_pumpkin, Art.pumpkin_body(0, Art.PUMPKIN, Color("ffc56a")), Art.tinted(Color("f7a040"), 0.35, 0.4), Vector3.ZERO, 0.55)
	_child_mesh(_festival_pumpkin, Art.pumpkin_stem(false), prop, Vector3(0, 0.55 * Art.pumpkin_top(0), 0), 0.55)
	# Seed box (east of the bed): opening it reads the garden note tucked under its lid (lore_ch2_garden_note,
	# "A Note in the Seed Box") and shows the guaranteed festival seed; the same prompt then plants it.
	var sp: Vector2 = g["seed_box"]
	B.mesh_at(self, Art.seed_box(), prop, Transform3D(Basis(Vector3.UP, B.yaw_to(sp, bp) + PI), B.ground(area, sp)), "SeedBox")
	B.box(solids, B.ground(area, sp, 0.2), Vector3(0.6, 0.4, 0.45), Basis(Vector3.UP, B.yaw_to(sp, bp) + PI))
	var seed_it: Node3D = WestInteractable.new()
	seed_it.setup({"id": "festival_seed", "size": Vector3(1.4, 1.4, 1.4), "offset": Vector3(0, 0.6, 0),
		"text_func": Callable(self, "_seed_text"), "handler": Callable(self, "_on_seed_box"), "marker": true})
	seed_it.position = B.ground(area, sp)
	add_child(seed_it)
	interactables["festival_seed"] = seed_it
	# The festival garden's painted sign (west of the bed; decor).
	var np: Vector2 = g["sign"]
	B.mesh_at(self, Art.garden_sign(), prop, Transform3D(Basis(Vector3.UP, B.yaw_to(np, bp) + PI), B.ground(area, np)), "GardenSign")
	B.cylinder(solids, B.ground(area, np), 0.07, 1.1)
	# The garden lamp.
	var lp: Vector2 = g["lamp"]
	var lyaw := B.yaw_to(lp, bp) + PI * 0.5
	B.mesh_at(self, Art.lamp_post(), prop, Transform3D(Basis(Vector3.UP, lyaw), B.ground(area, lp)), "GardenLampPost")
	B.cylinder(solids, B.ground(area, lp), 0.2, 3.2)
	var hook := Basis(Vector3.UP, lyaw) * Vector3(0.85, 2.72, 0)
	_lamp_glass = MeshInstance3D.new()
	_lamp_glass.name = "LampGlass"
	_lamp_glass.mesh = Art.lamp_glass()
	_lamp_glass.position = B.ground(area, lp) + hook
	_lamp_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamp_glass)
	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "GardenLampLight"
	_lamp_light.light_color = Color("ffc070")
	_lamp_light.light_energy = 1.6
	_lamp_light.omni_range = 11.0
	_lamp_light.shadow_enabled = false
	_lamp_light.distance_fade_enabled = true
	_lamp_light.distance_fade_begin = 60.0
	_lamp_light.distance_fade_length = 15.0
	_lamp_light.position = _lamp_glass.position + Vector3(0, -0.1, 0)
	add_child(_lamp_light)
	var lamp_it: Node3D = WestInteractable.new()
	lamp_it.setup({"id": "garden_lamp", "size": Vector3(1.6, 2.0, 1.6), "offset": Vector3(0, 1.0, 0),
		"text_func": Callable(self, "_lamp_text"), "handler": Callable(self, "_on_light"), "marker": true, "marker_radius": 0.9})
	lamp_it.position = B.ground(area, lp)
	add_child(lamp_it)
	interactables["garden_lamp"] = lamp_it
	# Festival bunting from a post to the lamp.
	var lpp: Vector2 = g["lights_post"]
	B.mesh_at(self, Art.bunting_post(), prop, Transform3D(Basis(), B.ground(area, lpp)), "BuntingPost")
	B.cylinder(solids, B.ground(area, lpp), 0.1, 2.4)
	var mid := (lpp + lp) * 0.5
	var span := lpp.distance_to(lp)
	var gy := (B.height(area, lpp) + B.height(area, lp)) * 0.5 + 2.55
	B.mesh_at(self, Props.garland(span, [Art.RIBBON_GOLD, Art.RIBBON_PLUM, Art.RIBBON_CREAM, Art.RIBBON_RED]),
		Art.prop_material(), Transform3D(Basis(Vector3.UP, -atan2(lp.y - lpp.y, lp.x - lpp.x)), Vector3(mid.x, gy, mid.y)), "Bunting", 80.0, false)


func _child_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = Vector3.ONE * scl
	parent.add_child(mi)
	return mi


func is_seed_planted() -> bool:
	return _flag(Data.FLAG_SEED_PLANTED)


func is_garden_note_read() -> bool:
	return _flag(Data.FLAG_GARDEN_NOTE)


func _seed_text() -> Dictionary:
	if growing or is_seed_planted():
		return {}
	if not is_garden_note_read():
		return {"text": "Open the seed box", "enabled": true}
	if not Irrigation.is_repaired():
		return {"text": "Plant the festival seed", "enabled": false, "reason": "The bed is bone dry. Water has to reach the garden first."}
	return {"text": "Plant the festival seed", "enabled": true}


## The seed box prompt: first press opens it (the note + the seed), the next plants the seed (once watered).
func _on_seed_box(_player: Node = null) -> void:
	if not is_garden_note_read():
		read_garden_note()
		Events.hint.emit("hr_festival_seed", "One plump festival seed waits in the box. Plant it once water reaches the festival bed.")
		return
	plant_festival_seed()


## Plants the guaranteed festival seed (no inventory needed) once the bed is watered. True when it grew now.
func plant_festival_seed() -> bool:
	if growing or is_seed_planted() or not Irrigation.is_repaired():
		return false
	GameState.set_flag(Data.FLAG_SEED_PLANTED, true)      # flag first: quitting mid-beat keeps it
	if instant_growth or not is_inside_tree():
		_apply_festival(false)
		return true
	growing = true
	Events.caption.emit("[Soft rustling as the festival vine unfurls]")
	Audio.play_3d("dig", _festival.global_position, -3.0)
	_festival.visible = true
	_festival_sprout.visible = true
	_festival_sprout.scale = Vector3.ONE * 0.01
	_festival_vine.visible = true
	_festival_vine.scale = Vector3.ONE * 0.01
	_festival_pumpkin.visible = true
	_festival_pumpkin.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_property(_festival_sprout, "scale", Vector3.ONE * 0.6, GROW_SECONDS * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_festival_vine, "scale", Vector3.ONE, GROW_SECONDS * 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: Fx.burst(self, _festival.global_position + Vector3.UP * 0.4, "leaves", 0.8))
	tw.tween_property(_festival_pumpkin, "scale", Vector3.ONE, GROW_SECONDS * 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_on_grown)
	return true


func _on_grown() -> void:
	growing = false
	_apply_festival(false)
	if is_inside_tree():
		Fx.burst(self, _festival.global_position + Vector3.UP * 0.7, "sparkle", 1.4)
		Audio.play_3d("harvest_crop", _festival.global_position, -2.0)
	Events.notify.emit("The festival pumpkin grew in a heartbeat. It glows like a little lantern.", "success")


func _apply_festival(_animate: bool) -> void:
	if _festival == null or growing:
		return
	var planted := is_seed_planted()
	_festival.visible = planted
	_festival_sprout.visible = planted
	_festival_sprout.scale = Vector3.ONE * 0.6
	_festival_vine.scale = Vector3.ONE
	_festival_pumpkin.scale = Vector3.ONE
	var it: Node3D = interactables.get("festival_seed")
	if it != null:
		it.set_active(not planted)


func read_garden_note(_player: Node = null) -> void:
	var l := lore_text(Data.LORE_GARDEN)
	GameState.discover_lore(Data.LORE_GARDEN)
	GameState.set_flag(Data.FLAG_GARDEN_NOTE, true)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l["title"]), String(l["text"]), 9.0)


## Lore text from LoreDB (data/lore_ch2_reach.gd), falling back to Data.LORE_FALLBACK until that file has it.
static func lore_text(id: String) -> Dictionary:
	var l: Dictionary = LoreDB.get_lore(id)
	if String(l.get("text", "")) == "":
		return Data.LORE_FALLBACK.get(id, {"title": "", "text": ""})
	return l


func mimics_cleared() -> bool:
	if mimic_pocket != null:
		return mimic_pocket.is_cleared()
	return _flag(Data.FLAG_MIMICS_CLEARED)


func lamp_conditions() -> Dictionary:
	return {"irrigated": Irrigation.is_repaired(), "mimics_cleared": mimics_cleared(), "lit": is_lamp_lit()}


func can_light_lamp() -> bool:
	return not is_lamp_lit() and Irrigation.is_repaired() and mimics_cleared()


func is_lamp_lit() -> bool:
	return _flag(Data.FLAG_LAMP_LIT)


func _lamp_text() -> Dictionary:
	if is_lamp_lit():
		return {}
	var wet := Irrigation.is_repaired()
	var calm := mimics_cleared()
	if wet and calm:
		return {"text": "Light the garden lamp", "enabled": true}
	var why := ""
	if not wet and not calm:
		why = "Its planter is bone dry, and something in the crooked patch keeps snuffing the wick."
	elif not wet:
		why = "Its planter is bone dry. Water has to reach the festival garden."
	else:
		why = "Something in the crooked patch keeps snuffing the wick. Deal with the twitching pumpkins first."
	return {"text": "Light the garden lamp", "enabled": false, "reason": why}


func _on_light(_player: Node = null) -> void:
	light_lamp()


## Lights the garden lamp (needs irrigation + the cleared mimic pocket). Sets ch2_garden_lamp_lit exactly once;
## the quest layer pays the Garden Seal. True only on the call that lit it.
func light_lamp() -> bool:
	if not can_light_lamp():
		return false
	if not _flag(Data.FLAG_FOUND_LAMP):
		GameState.set_flag(Data.FLAG_FOUND_LAMP, true)
	GameState.set_flag(Data.FLAG_LAMP_LIT, true)
	_apply_lamp(true)
	if Game.has_method("companion_present") and Game.companion_present("lumi"):
		Events.say.emit("", LUMI_LAMP_LINE, 4.0)
	return true


func _apply_lamp(animate: bool) -> void:
	var lit := is_lamp_lit()
	if _lamp_glass != null:
		_lamp_glass.material_override = Art.glow(Color("ffb347"), 2.2) if lit else Art.tinted(Color("8a5a3c"), 0.0, 0.3)
	if _lamp_light != null:
		_lamp_light.visible = lit
	var it: Node3D = interactables.get("garden_lamp")
	if it != null:
		it.set_active(not lit)
	if animate and lit and _lamp_glass != null and _lamp_glass.is_inside_tree():
		Fx.burst(self, _lamp_glass.global_position, "sparkle", 1.6)
		Audio.play_3d("checkpoint_light", _lamp_glass.global_position, -2.0)
		Events.caption.emit("[The garden lamp catches with a warm, soft whump]")


func _check_lamp_found(p: Vector3) -> void:
	if _flag(Data.FLAG_FOUND_LAMP):
		return
	var lp: Vector2 = Data.GARDEN["lamp"]
	var d := Vector2(p.x - lp.x, p.z - lp.y).length()
	if d <= Data.LAMP_FOUND_NEAR or (d <= Data.LAMP_FOUND_SEEN and is_on_screen(B.ground(area, lp, 2.7))):
		GameState.set_flag(Data.FLAG_FOUND_LAMP, true)
		Events.notify.emit("Found: the orchard's garden lamp. Its bed is dry and its wick is cold.", "quest")


# --- Decor ----------------------------------------------------------------------------------------------------

func _build_decor() -> void:
	var prop := Art.prop_material()
	var d: Dictionary = Data.ORCHARD_DECOR
	# Oversized pumpkins (solid) with their stems.
	var bodies: Array = []
	var stems: Array = []
	for gp in d["giant_pumpkins"]:
		var p: Vector2 = gp[0]
		var r := float(gp[1])
		var yaw := float(posmod(hash(str(p)), 628)) * 0.01
		var g := B.ground(area, p, -0.05)
		bodies.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * r), g))
		stems.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * r), g + Vector3(0, r * Art.pumpkin_top(1), 0)))
		B.cylinder(solids, g, r * 0.95, r * 1.35)
	B.multi(self, Art.pumpkin_body(1), prop, bodies, "GiantPumpkins", 140.0)
	B.multi(self, Art.pumpkin_stem(false), prop, stems, "GiantPumpkinStems", 110.0)
	# Little harmless scarecrows (decor only: never enemies, never interactive).
	var sc: Array = []
	for p in d["scarecrows"]:
		var pv: Vector2 = p
		sc.append(Transform3D(Basis(Vector3.UP, float(posmod(hash(str(pv)), 628)) * 0.01), B.ground(area, pv)))
		B.cylinder(solids, B.ground(area, pv), 0.12, 1.6)
	B.multi(self, Art.scarecrow(), prop, sc, "Scarecrows", 110.0)
	# Crooked fences along the roseberry rows (the gaps between runs are wide openings).
	var fx: Array = []
	for run in d["fences"]:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var n := maxi(1, int(round(a.distance_to(b) / 2.0)))
		var dir := (b - a) / float(n)
		var rng := B.rng_for("fence|" + str(a))
		for k in n:
			var c := a + dir * (float(k) + 0.5)
			var yaw := -atan2(dir.y, dir.x) + rng.randf_range(-0.08, 0.08)
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, rng.randf_range(-0.07, 0.07)) * Basis(Vector3.RIGHT, rng.randf_range(-0.06, 0.06))
			var scl := dir.length() / 2.0
			fx.append(Transform3D(basis * Basis.from_scale(Vector3(scl, 1, 1)), B.ground(area, c, -0.03)))
			B.box(solids, B.ground(area, c, 0.45), Vector3(dir.length(), 0.9, 0.14), Basis(Vector3.UP, yaw))
	B.multi(self, Art.fence(0), prop, fx, "CrookedFences", 90.0)
	# Hay bales (solid).
	var bx: Array = []
	for p in d["bales"]:
		var pv: Vector2 = p
		var yaw := float(posmod(hash(str(pv)), 628)) * 0.01
		bx.append(Transform3D(Basis(Vector3.UP, yaw), B.ground(area, pv)))
		B.box(solids, B.ground(area, pv, 0.3), Vector3(1.3, 0.6, 0.85), Basis(Vector3.UP, yaw))
	B.multi(self, Art.hay_bale(), prop, bx, "HayBales", 90.0)
	# Amber puddles (visual only).
	var px: Array = []
	for pd in d["puddles"]:
		var pv: Vector2 = pd[0]
		var r := float(pd[1])
		px.append(Transform3D(Basis().scaled(Vector3(r, 1.0, r * 0.8)), B.ground(area, pv, 0.02)))
	B.multi(self, Art.puddle_disc(), Art.puddle_material(), px, "AmberPuddles", 70.0, false)
	# Leaf piles and small decor pumpkins scattered away from paths, levers, pockets and nodes.
	var rng2 := B.rng_for("orchard_scatter")
	var leaves: Array = []
	var smalls: Array = []
	var tries := 0
	while (leaves.size() < 16 or smalls.size() < 10) and tries < 400:
		tries += 1
		var a := rng2.randf() * TAU
		var r := sqrt(rng2.randf()) * 27.0
		var p := Data.center_of(Data.ORCHARD) + Vector2(cos(a), sin(a)) * r
		if not scatter_ok(p, 1.6):
			continue
		if leaves.size() < 16:
			leaves.append(Transform3D(Basis(Vector3.UP, rng2.randf() * TAU).scaled(Vector3.ONE * rng2.randf_range(0.7, 1.2)), B.ground(area, p)))
		else:
			smalls.append(Transform3D(Basis(Vector3.UP, rng2.randf() * TAU).scaled(Vector3.ONE * rng2.randf_range(0.22, 0.32)), B.ground(area, p)))
	B.multi(self, Art.leaf_pile(0), Art.soft_material(), leaves, "LeafPiles", 60.0, false)
	B.multi(self, Art.pumpkin_body(2), prop, smalls, "LittlePumpkins", 70.0)


## True when a scatter decor point keeps clear of everything interactive / walkable-critical (and the arch).
func scatter_ok(p: Vector2, clearance: float) -> bool:
	if p.distance_to(Data.ORCHARD_ARCH) < Data.ARCH_CLEARANCE + 1.0:
		return false
	var keep: Array = []
	for e in Data.nodes_in(Data.ORCHARD):
		keep.append([e["pos"], 1.2])
	for k in ["cistern", "junction", "gate", "lever_junction", "lever_gate", "drain_pond", "spill", "bed_inlet"]:
		keep.append([Data.IRRIGATION[k], 2.6])
	for k in ["bed", "seed_box", "sign", "lamp", "lights_post"]:
		keep.append([Data.GARDEN[k], 2.6])
	keep.append([Data.MIMIC_POCKET["center"], float(Data.MIMIC_POCKET["radius"]) + 1.0])
	keep.append([Data.PATCH_POCKET["center"], float(Data.PATCH_POCKET["radius"]) + 1.0])
	keep.append([Data.MOMENT["pos"], 2.5])
	keep.append([Data.ORCHARD_ENTRY, 3.0])
	for gp in Data.ORCHARD_DECOR["giant_pumpkins"]:
		keep.append([gp[0], float(gp[1]) + 1.0])
	for s in Data.ORCHARD_DECOR["scarecrows"]:
		keep.append([s, 1.2])
	for bl in Data.ORCHARD_DECOR["bales"]:
		keep.append([bl, 1.5])
	for seg in Data.FLUME_SEGMENTS:
		if _dist_to_segment(p, seg[1], seg[2]) < 1.2:
			return false
	for run in Data.ORCHARD_DECOR["fences"]:
		if _dist_to_segment(p, run[0], run[1]) < 1.0:
			return false
	for k2 in keep:
		if p.distance_to(k2[0]) < float(k2[1]) + clearance * 0.5:
			return false
	return true


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- Pockets and the moment -------------------------------------------------------------------------------------

func _build_pockets() -> void:
	mimic_pocket = PocketScript.new()
	mimic_pocket.setup(area)
	add_child(mimic_pocket)
	spawners["hr_sp_orchard_mimics"] = null      # created only when the pocket wakes (see mimic_pocket.gd)
	# The Patchwalker field: a torn coat on a post with a rake, a trampled straw ring, an optional spawner.
	var prop := Art.prop_material()
	var pc: Vector2 = Data.PATCH_POCKET["center"]
	var mk: Vector2 = Data.PATCH_POCKET["marker"]
	B.mesh_at(self, Art.coat_post(), prop, Transform3D(Basis(Vector3.UP, B.yaw_to(mk, pc) + PI), B.ground(area, mk)), "PatchwalkerMarker")
	B.cylinder(solids, B.ground(area, mk), 0.1, 1.8)
	var tufts: Array = []
	var rng := B.rng_for("patch_straw")
	for i in 18:
		var a := TAU * float(i) / 18.0 + rng.randf_range(-0.1, 0.1)
		var r := float(Data.PATCH_POCKET["radius"]) * rng.randf_range(0.85, 1.05)
		tufts.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.0, 1.6)), B.ground(area, pc + Vector2(cos(a), sin(a)) * r)))
	B.multi(self, Art.straw_tuft(), Art.soft_material(), tufts, "TrampledStraw", 60.0, false)
	spawners["hr_sp_orchard_patchwalkers"] = B.spawner(self, area, "hr_sp_orchard_patchwalkers")


func _build_moment() -> void:
	moment = MomentScript.new()
	var mp: Vector2 = Data.MOMENT["pos"]
	moment.setup({"pos": B.ground(area, mp), "face_yaw": MomentScript.face_yaw_to(mp, Data.MOMENT["face_to"]),
		"turned_yaw": MomentScript.face_yaw_to(mp, Data.MOMENT["turned_to"])})
	add_child(moment)
	B.box(solids, B.ground(area, mp, 0.3), Vector3(1.3, 0.6, 0.85))


func _flag(f: String) -> bool:
	var v: Variant = GameState.get_flag(f)
	return v is bool and v

extends Node3D
## The lamp-linking pedestal in the Ward-Keeper's Conservatory (MP §11 step 9, "A Thread of True Light").
## Three sockets show the three regional lamps: garden (orchard), quarry, manor. A socket glows once its
## lamp flag is set (ch2_garden_lamp_lit / ch2_quarry_lamp_lit / ch2_manor_lamp_lit, set by the district
## modules; the quest layer pays the seals). With all three lit: "Link the lanterns" -> flag
## ch2_lamps_linked is set FIRST (committed before any animation), then a short readable ceremony: the
## sockets flare, a caption + line, and three motes run the roads lighting the road lamps
## (road_lights.gd). Nothing is consumed and nothing is granted here (the seals are keepsakes).
## Works with the ordinary lantern, no companion, and sound muted (glow + text + captions).
## Interaction contract: group "interactable" + a layer-16 sphere.
##   get_interaction(player) / interact(player) / link_lanterns(animate := true) -> bool
##   lamps_lit() -> Array[String], ready_to_link() -> bool, is_linked() -> bool

signal linked

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/reach/reach_props.gd")
const Interactable := preload("res://src/world/reach/reach_interactable.gd")
const Fx := preload("res://src/world/common/fx.gd")

const LINKED_FLAG := "ch2_lamps_linked"
## [id, flag, name, where, colour, socket angle (deg, 0 = +X)]
const LAMPS := [
	["garden", "ch2_garden_lamp_lit", "garden lamp", "Pumpkintide Orchard", Color("d8e07a"), 210.0],
	["quarry", "ch2_quarry_lamp_lit", "quarry lamp", "Ashbell Quarry", Color("ffae5a"), 330.0],
	["manor", "ch2_manor_lamp_lit", "manor lamp", "Moonveil Manor", Color("c9a0ff"), 90.0],
]
const SPEAKER := "Linking Pedestal"

var road_lights: Node = null          # road_lights.gd (optional: the ceremony motes)
var _sockets: Dictionary = {}         # id -> {"glass": MeshInstance3D, "lit_mat", "dark_mat", "light": OmniLight3D}
var _center_glow: MeshInstance3D
var _center_mat: StandardMaterial3D
var _busy := false
var _marker: Node3D
var _t := 0.0


func _ready() -> void:
	name = "LinkPedestal"
	add_to_group("interactable")
	add_to_group("link_pedestal")
	_build()
	refresh()
	if not Events.flag_set.is_connected(_on_flag_set):
		Events.flag_set.connect(_on_flag_set)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	_apply_marker()


func _on_flag_set(flag: String, _value: Variant) -> void:
	if flag == LINKED_FLAG:
		refresh()
		return
	for l in LAMPS:
		if flag == String(l[1]):
			refresh()
			_apply_marker()
			return


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_apply_marker()


# --- State ---------------------------------------------------------------------------------------------

func lamps_lit() -> Array:
	var out: Array = []
	for l in LAMPS:
		if bool(GameState.get_flag(String(l[1]))):
			out.append(String(l[0]))
	return out


func ready_to_link() -> bool:
	return lamps_lit().size() == LAMPS.size() and not is_linked()


func is_linked() -> bool:
	return bool(GameState.get_flag(LINKED_FLAG))


# --- Interaction ------------------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if is_linked():
		return {"text": "Look at the linked lanterns", "enabled": true}
	if ready_to_link():
		return {"text": "Link the lanterns", "enabled": true}
	return {"text": "Inspect the linking pedestal (%d/3 lamps)" % lamps_lit().size(), "enabled": true}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	if is_linked():
		Events.say.emit(SPEAKER, "Three roads, one light. The stair at the Sunken Bellhouse stands open.", 5.0)
		return
	if ready_to_link():
		link_lanterns(true)
		return
	var missing: Array = []
	for l in LAMPS:
		if not bool(GameState.get_flag(String(l[1]))):
			missing.append("the %s (%s)" % [l[2], l[3]])
	var text := "Three sockets wait for three festival lamps. Still asleep: %s." % ", ".join(missing)
	Events.say.emit(SPEAKER, text, 6.5)
	Audio.play_3d("ward_hum", global_position + Vector3.UP, -10.0)


## Links the three lamps. Returns false (and does nothing) unless all three are lit and not yet linked.
func link_lanterns(animate: bool = true) -> bool:
	if not ready_to_link() or _busy:
		return false
	GameState.set_flag(LINKED_FLAG, true)      # committed first: quitting mid-ceremony keeps the progress
	refresh()
	linked.emit()
	if not animate or not is_inside_tree():
		if road_lights != null and is_instance_valid(road_lights):
			road_lights.set_lit_instant(true)
		return true
	_busy = true
	Audio.play_3d("checkpoint_light", global_position + Vector3.UP * 1.2, -2.0)
	Audio.play_3d("ward_hum", global_position + Vector3.UP, -6.0)
	Events.caption.emit("[The pedestal hums; three threads of light run out along the roads]")
	Events.say.emit(SPEAKER, "The three lamps answer one another. Along every road, a light wakes.", 6.0)
	Fx.burst(get_parent(), global_position + Vector3(0, 1.6, 0), "sparkle", 2.0)
	var dur := 0.0
	if road_lights != null and is_instance_valid(road_lights):
		dur = float(road_lights.play_link(global_position + Vector3(0, 1.2, 0)))
	var tw := create_tween()
	tw.tween_method(_flare, 1.0, 0.0, maxf(dur, 2.0)).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		_busy = false
		Events.notify.emit("The lanterns are linked. A stair has opened at the Sunken Bellhouse.", "quest"))
	return true


func _flare(v: float) -> void:
	if _center_mat != null:
		var calm := bool(Settings.get_value("reduce_flashing"))
		var k := 1.0 + (v * (0.6 if calm else 1.4))
		_center_mat.emission_energy_multiplier = 1.4 * k


# --- Visuals -----------------------------------------------------------------------------------------------

func _build() -> void:
	var stone := NodeVisuals.rock_material(0.02)
	var m := NodeVisuals.Merger.new()
	var st := Color("c9bba6")
	m.add(NodeVisuals._cyl(0.8, 0.95, 0.3, 12), Transform3D(Basis(), Vector3(0, 0.15, 0)), st.darkened(0.15))
	m.add(NodeVisuals._cyl(0.42, 0.55, 0.8, 10), Transform3D(Basis(), Vector3(0, 0.7, 0)), st)
	m.add(NodeVisuals._cyl(0.85, 0.6, 0.18, 12), Transform3D(Basis(), Vector3(0, 1.18, 0)), st.lightened(0.05))
	for l in LAMPS:
		var a := deg_to_rad(float(l[5]))
		var p := Vector3(cos(a) * 0.55, 1.27, sin(a) * 0.55)
		m.add(NodeVisuals._cyl(0.15, 0.17, 0.08, 10), Transform3D(Basis(), p), Palette.STONE_DARK)
		for k in 4:
			var ka := TAU * float(k) / 4.0 + 0.4
			m.add(NodeVisuals._cyl(0.012, 0.012, 0.34, 4), Transform3D(Basis(), p + Vector3(cos(ka) * 0.11, 0.2, sin(ka) * 0.11)), Color("6a5a4a"))
		m.add(NodeVisuals._cyl(0.02, 0.15, 0.08, 8), Transform3D(Basis(), p + Vector3(0, 0.4, 0)), Color("6a5a4a"))
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = m.commit()
	body_mi.material_override = stone
	add_child(body_mi)
	for l in LAMPS:
		var a := deg_to_rad(float(l[5]))
		var p := Vector3(cos(a) * 0.55, 1.47, sin(a) * 0.55)
		var glass := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.085
		cm.bottom_radius = 0.1
		cm.height = 0.24
		cm.radial_segments = 8
		glass.mesh = cm
		glass.position = p
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glass)
		var light := OmniLight3D.new()
		light.light_color = l[4]
		light.light_energy = 0.0
		light.omni_range = 2.6
		light.shadow_enabled = false
		light.position = p + Vector3(0, 0.1, 0)
		add_child(light)
		_sockets[String(l[0])] = {"glass": glass, "lit_mat": Mat.glow(l[4], 2.4), "dark_mat": Mat.toon(Color("4d443e"), {"rim": 0.3}), "light": light}
	# the heart of the pedestal: a pale flame that brightens when the lamps are linked
	_center_mat = StandardMaterial3D.new()
	_center_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_center_mat.albedo_color = Color("ffe2a0")
	_center_mat.emission_enabled = true
	_center_mat.emission = Color("ffd08a")
	_center_mat.emission_energy_multiplier = 0.4
	_center_glow = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_center_glow.mesh = sm
	_center_glow.material_override = _center_mat
	_center_glow.position = Vector3(0, 1.45, 0)
	_center_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_center_glow)
	var body := StaticBody3D.new()
	body.name = "PedestalBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	add_child(body)
	Props.cyl_col(body, Vector3.ZERO, 0.9, 1.3)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.6
	cs.shape = sph
	cs.position = Vector3(0, 1.1, 0)
	ib.add_child(cs)
	add_child(ib)


func refresh() -> void:
	var all_linked := is_linked()
	for l in LAMPS:
		var s: Dictionary = _sockets.get(String(l[0]), {})
		if s.is_empty():
			continue
		var on := bool(GameState.get_flag(String(l[1]))) or all_linked
		(s["glass"] as MeshInstance3D).material_override = s["lit_mat"] if on else s["dark_mat"]
		(s["light"] as OmniLight3D).light_energy = 0.8 if on else 0.0
		(s["light"] as OmniLight3D).visible = on
	if _center_mat != null:
		_center_mat.emission_energy_multiplier = 1.4 if all_linked else 0.4 + 0.25 * float(lamps_lit().size())


func _apply_marker() -> void:
	var want := Interactable.hi_vis_on() and not is_linked()
	if want and _marker == null:
		_marker = Interactable.make_marker()
		add_child(_marker)
		_marker.position = Vector3(0, 2.6, 0)
	if _marker != null:
		_marker.visible = want
	set_process(want)


func _process(delta: float) -> void:
	_t += delta
	if _marker != null and _marker.visible:
		_marker.position.y = 2.6 + sin(_t * 2.0) * 0.08
		_marker.rotation.y = _t * 0.9

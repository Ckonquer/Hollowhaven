extends Node3D
## The Ashbell quarry lamp (MP §11 step 6 "The Quarry's Pulse"): a festival bell-lantern on the upper shelf,
## visible from the Warden's arena below. States (flags, data/reach_east.gd):
##   dormant  cold glass, a faint ember; found (ch2_found_quarry_lamp) as soon as Krystal comes within
##            LAMP_FIND_RADIUS (or looks at it); lighting is refused with the reason while the Warden is not
##            calmed (hr_warden_defeated) or the winch is broken (ch2_winch_repaired)
##   ready    both done: "Light the quarry lamp"
##   lit      ch2_quarry_lamp_lit - the ONLY thing this lamp sets besides the found flag; the Chapter Two quest
##            layer then pays rw_ch2_quarry (Quarry Seal + Ironwood knowledge). Lumi, if with Krystal, answers
##            with her MP §17 line. Warm light, no audio-only cue (captions + visual change).
## Interaction contract: group "interactable" + a layer-16 sphere; the pedestal is solid (layer 1).
##   state() -> "dormant"|"ready"|"lit", blocked_reason(), light() -> bool, check_approach(pos) -> bool,
##   player_override (tests)

signal lit

const Q := preload("res://data/reach_east.gd")
const QV := preload("res://src/world/reach/east/quarry_visuals.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Fx := preload("res://src/world/common/fx.gd")

const POLL := 0.5
const HOOD_Y := 2.55

var find_radius: float = Q.LAMP_FIND_RADIUS
var player_override: Node3D = null

var _glass: MeshInstance3D
var _flame: MeshInstance3D
var _ember: MeshInstance3D
var _light: OmniLight3D
var _cue: MeshInstance3D
var _poll_t := 0.0
var _t := 0.0


func setup(p: Dictionary) -> void:
	find_radius = float(p.get("find_radius", find_radius))


func _ready() -> void:
	name = "QuarryLamp"
	add_to_group("interactable")
	add_to_group("quarry_lamp")
	if _glass == null:
		_build()
	_apply(false)
	if not Events.flag_set.is_connected(_on_flag_set):
		Events.flag_set.connect(_on_flag_set)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func state() -> String:
	if bool(GameState.get_flag(Q.FLAG_LAMP_LIT)):
		return "lit"
	if bool(GameState.get_flag(Q.FLAG_WARDEN)) and bool(GameState.get_flag(Q.FLAG_WINCH)):
		return "ready"
	return "dormant"


## Why it can't be lit yet ("" when it can or already is).
func blocked_reason() -> String:
	if state() != "dormant":
		return ""
	if not bool(GameState.get_flag(Q.FLAG_WARDEN)):
		return Q.TEXT["lamp_need_warden"]
	return Q.TEXT["lamp_need_winch"]


func get_interaction(_player: Node = null) -> Dictionary:
	match state():
		"lit":
			return {"text": Q.TEXT["lamp_lit_prompt"], "enabled": false, "reason": ""}
		"ready":
			return {"text": Q.TEXT["lamp_name"], "enabled": true}
	return {"text": Q.TEXT["lamp_name"], "enabled": false, "reason": blocked_reason()}


func interact(_player: Node = null) -> void:
	_mark_found(false)
	if state() == "ready":
		light()


func set_focused(on: bool) -> void:
	if on:
		_mark_found(true)


## Lights the lamp for good. Returns true when this call lit it.
func light() -> bool:
	if state() != "ready":
		return false
	_mark_found(false)
	GameState.set_flag(Q.FLAG_LAMP_LIT, true)
	_apply(is_inside_tree())
	Events.say.emit("", Q.TEXT["lamp_lit"], 5.0)
	Events.caption.emit(Q.TEXT["lamp_caption"])
	if Game.has_method("companion_present") and bool(Game.companion_present("lumi")):
		var lumi: Variant = Game.companion_nodes.get("lumi") if Game.get("companion_nodes") is Dictionary else null
		if lumi is Node and is_instance_valid(lumi) and (lumi as Node).has_method("react"):
			(lumi as Node).react("celebrate")
		if is_inside_tree():
			get_tree().create_timer(5.2).timeout.connect(func() -> void:
				Events.say.emit("", Q.TEXT["lamp_lumi"], 4.5))
		else:
			Events.say.emit("", Q.TEXT["lamp_lumi"], 4.5)
	if GameState.has_method("request_quest_eval"):
		GameState.request_quest_eval()
	lit.emit()
	return true


## Sets ch2_found_quarry_lamp when `pos` is within the find radius (XZ). True when newly found.
func check_approach(pos: Vector3) -> bool:
	if bool(GameState.get_flag(Q.FLAG_LAMP_FOUND)):
		return false
	var g := global_position if is_inside_tree() else position
	if Vector2(pos.x - g.x, pos.z - g.z).length() > find_radius:
		return false
	return _mark_found(true)


func _mark_found(tell: bool) -> bool:
	if bool(GameState.get_flag(Q.FLAG_LAMP_FOUND)):
		return false
	GameState.set_flag(Q.FLAG_LAMP_FOUND, true)
	if tell:
		Events.say.emit("", Q.TEXT["lamp_found"], 5.0)
	if GameState.has_method("request_quest_eval"):
		GameState.request_quest_eval()
	return true


func _process(delta: float) -> void:
	_t += delta
	if state() == "lit":
		if _flame != null:
			var s := 1.0 + 0.06 * sin(_t * 5.3) + 0.03 * sin(_t * 11.0)
			_flame.scale = Vector3(s, s * 1.1, s)
	elif _cue != null and _cue.visible:
		_cue.position.y = HOOD_Y + 1.2 + 0.12 * sin(_t * 2.2)
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = POLL
	if bool(GameState.get_flag(Q.FLAG_LAMP_FOUND)):
		return
	var p := _player()
	if p != null:
		check_approach(p.global_position)


func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


func _on_flag_set(flag: String, _v: Variant) -> void:
	if flag == Q.FLAG_LAMP_LIT or flag == Q.FLAG_WARDEN or flag == Q.FLAG_WINCH or flag == Q.FLAG_LAMP_FOUND:
		_apply(false)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_apply(false)


# --- Visuals ---------------------------------------------------------------------------------------------

func _build() -> void:
	var stone := NV.Merger.new()
	var wood := NV.Merger.new()
	var metal := NV.Merger.new()
	# pedestal: two soft stone drums
	stone.add(Kit.blob_mesh(0.5, 9601, 0.12, 1.0, 2), Transform3D(Basis.from_scale(Vector3(1.5, 0.7, 1.5)), Vector3(0, 0.2, 0)), Q.COL_SHELF.darkened(0.2))
	stone.add(Kit.blob_mesh(0.5, 9602, 0.12, 1.0, 2), Transform3D(Basis.from_scale(Vector3(1.05, 0.55, 1.05)), Vector3(0, 0.62, 0)), Q.COL_SHELF)
	# a copper post with a curled arm and the bell-lantern hanging from it
	QV.add_rod(wood, Vector3(0, 0.6, 0), Vector3(0, 3.3, 0), 0.09, Palette.WOOD_DARK)
	QV.add_rod(metal, Vector3(0, 3.2, 0), Vector3(0.0, 3.2, 0.55), 0.05, Palette.COPPER)
	QV.add_rod(metal, Vector3(0.0, 3.2, 0.55), Vector3(0.0, HOOD_Y + 0.35, 0.55), 0.025, Q.COL_IRON)
	var hood := Vector3(0, HOOD_Y + 0.35, 0.55)
	QV.add_bell(metal, Transform3D(Basis(), hood), 0.95)
	metal.add(NV._cyl(0.2, 0.2, 0.05, 10), Transform3D(Basis(), hood + Vector3(0, -0.95, 0)), Q.COL_IRON)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		QV.add_rod(metal, hood + Vector3(cos(a) * 0.2, -0.6, sin(a) * 0.2), hood + Vector3(cos(a) * 0.2, -0.95, sin(a) * 0.2), 0.015, Q.COL_IRON)
	for k in 3:
		QV.add_ribbon(wood, Vector3(0.07 * float(k - 1), 3.0, 0.08), 0.3 * float(k), 0.7, Q.COL_RIBBON_A if k != 1 else Q.COL_RIBBON_B)
	add_child(NV._mi(stone.commit(), QV.stone_material(), "Pedestal"))
	add_child(NV._mi(wood.commit(), QV.wood_material(), "Post"))
	add_child(NV._mi(metal.commit(), QV.metal_material(), "Lantern"))
	var glass_c := hood + Vector3(0, -0.77, 0)
	_glass = MeshInstance3D.new()
	_glass.name = "Glass"
	_glass.mesh = NV._cyl(0.19, 0.19, 0.34, 10)
	_glass.position = glass_c
	add_child(_glass)
	_flame = Kit.sphere(0.09, Mat.glow(Q.LAMP_GLOW, 3.2), 8, 10)
	_flame.name = "Flame"
	_flame.position = glass_c
	add_child(_flame)
	_ember = Kit.sphere(0.04, Mat.glow(Color("ff8a4a"), 1.2), 6, 8)
	_ember.name = "Ember"
	_ember.position = glass_c + Vector3(0, -0.1, 0)
	add_child(_ember)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Q.LAMP_GLOW
	_light.light_energy = 1.9
	_light.omni_range = 11.0
	_light.shadow_enabled = false
	_light.position = glass_c
	add_child(_light)
	# high-visibility cue: a bold floating ring above the lamp while it can be lit
	_cue = MeshInstance3D.new()
	_cue.name = "Cue"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.46
	_cue.mesh = tm
	_cue.rotation_degrees = Vector3(90, 0, 0)
	_cue.material_override = Mat.glow(Color("fff2c8"), 1.8)
	_cue.position = Vector3(0, HOOD_Y + 1.2, 0.55)
	_cue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cue)
	# solid pedestal + interaction sphere
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.75
	cyl.height = 1.1
	cs.shape = cyl
	cs.position = Vector3(0, 0.55, 0)
	body.add_child(cs)
	add_child(body)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.1
	ics.shape = sph
	ics.position = Vector3(0, 1.3, 0.2)
	ib.add_child(ics)
	add_child(ib)


func _apply(animate: bool) -> void:
	if _glass == null:
		return
	var st := state()
	var on := st == "lit"
	_glass.material_override = Mat.transparent(Color(1.0, 0.86, 0.55, 0.75) if on else Color(0.55, 0.6, 0.7, 0.45))
	_flame.visible = on
	_ember.visible = not on
	_light.visible = on
	_cue.visible = st == "ready" and bool(Settings.get_value("high_visibility_cues"))
	# per-frame work only while there is something to do: the flame flickers, the cue bobs, the approach poll
	set_process(on or _cue.visible or not bool(GameState.get_flag(Q.FLAG_LAMP_FOUND)))
	if on and animate and is_inside_tree():
		Fx.burst(get_parent(), _flame.global_position, "sparkle", 2.0)
		if Audio.has_sound("checkpoint_light"):
			Audio.play_3d("checkpoint_light", _flame.global_position, 0.0)

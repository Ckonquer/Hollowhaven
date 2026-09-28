extends Node3D
## Moonveil Manor grounds behaviour in Hallowmere Reach (built by src/world/reach/districts/manor_grounds.gd):
##   * ch2_found_manor_lamp is set the first time Krystal approaches the manor (within GROUNDS.found_r of
##     GROUNDS.found_point) - she can see the lamp cage on the tower from there;
##   * the tower's lamp cage shows cold or lit from ch2_manor_lamp_lit (rebuilt on every Reach load);
##   * the invitation on its easel beside the door (MP §17, verbatim): reading it discovers
##     lore_ch2_manor_invitation (the note itself lives in the Reach districts' lore file).
## Tests: player_override, check(), read_invitation().

signal lamp_found

const Layout := preload("res://data/manor_layout.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const Interactable := preload("res://src/world/manor/manor_interactable.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const COLD := Color("8f86a8")
const WARM := Color("ffc463")
const IRON := Color("35283a")
const GOLD := Color("d9b25a")

var player_override: Node3D = null
var lamp_pos := Vector3.ZERO
var invitation_pos := Vector3.ZERO
var invitation: Node3D = null
var reads: int = 0
var _lamp_cold: MeshInstance3D
var _lamp_warm: MeshInstance3D
var _lamp_light: OmniLight3D
var _t := 0.0


func setup(params: Dictionary) -> void:
	lamp_pos = params.get("lamp_pos", lamp_pos)
	invitation_pos = params.get("invitation_pos", invitation_pos)


func _ready() -> void:
	name = "ManorGroundsController"
	add_to_group("mm_grounds")
	_build_lamp()
	refresh_lamp()
	_build_invitation(invitation_pos)



func refresh_lamp() -> void:
	var lit := bool(GameState.get_flag(Layout.FLAG_LAMP_LIT))
	_lamp_cold.visible = not lit
	_lamp_warm.visible = lit
	_lamp_light.visible = lit


func lamp_is_lit() -> bool:
	return _lamp_warm != null and _lamp_warm.visible


func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	check()


## Sets ch2_found_manor_lamp when Krystal is close enough to see the lamp. Returns true when newly set.
func check() -> bool:
	if bool(GameState.get_flag(Layout.FLAG_FOUND_LAMP)):
		set_process(false)
		return false
	var p := _player()
	if p == null:
		return false
	var fp: Vector2 = Layout.GROUNDS["found_point"]
	if Vector2(p.global_position.x - fp.x, p.global_position.z - fp.y).length() > float(Layout.GROUNDS["found_r"]):
		return false
	GameState.set_flag(Layout.FLAG_FOUND_LAMP, true)
	Events.notify.emit("Moonveil Manor: a cold lamp waits high on its tower.", "quest")
	Events.caption.emit("[candles flicker in every window of the manor]")
	GameState.request_quest_eval()
	lamp_found.emit()
	set_process(false)
	return true


func read_invitation() -> void:
	reads += 1
	var title := Layout.INVITATION_TITLE
	var text := Layout.INVITATION_TEXT
	if LoreDB.has_lore(Layout.LORE_INVITATION):
		var l := LoreDB.get_lore(Layout.LORE_INVITATION)
		if String(l.get("text", "")) != "":
			title = String(l.get("title", title))
			text = String(l.get("text", text))
		GameState.discover_lore(Layout.LORE_INVITATION)
	if not bool(GameState.get_flag(Layout.FLAG_FOUND_LAMP)):
		GameState.set_flag(Layout.FLAG_FOUND_LAMP, true)
		GameState.request_quest_eval()
	Events.say.emit(title, text, 9.0)


func _build_lamp() -> void:
	var holder := Node3D.new()
	holder.name = "TowerLamp"
	add_child(holder)
	holder.position = lamp_pos
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.35}), 0.02)
	var gold := Mat.toon(GOLD, {"rim": 0.5})
	Kit.add(holder, Kit.cylinder(0.7, 0.8, 0.2, gold, 12), Vector3(0, 0.1, 0))
	for k in 6:
		var a := TAU * float(k) / 6.0
		Kit.add(holder, Kit.cylinder(0.05, 0.05, 1.6, iron, 6), Vector3(cos(a) * 0.62, 1.0, sin(a) * 0.62))
	_lamp_cold = Kit.cylinder(0.56, 0.56, 1.4, Mat.transparent(Color(COLD, 0.6), false), 12)
	Kit.add(holder, _lamp_cold, Vector3(0, 1.0, 0))
	_lamp_warm = Kit.cylinder(0.56, 0.56, 1.4, Mat.glow(WARM, 1.8), 12)
	Kit.add(holder, _lamp_warm, Vector3(0, 1.0, 0))
	_lamp_warm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(holder, Kit.cone(0.85, 0.8, iron, 12), Vector3(0, 2.2, 0))
	Kit.add(holder, Kit.cylinder(0.32, 0.32, 0.06, gold, 20), Vector3(0, 2.95, 0), Vector3(90, 0, 0))
	Kit.add(holder, Kit.cylinder(0.27, 0.27, 0.07, iron, 20), Vector3(0.12, 3.0, 0), Vector3(90, 0, 0))
	_lamp_light = OmniLight3D.new()
	_lamp_light.name = "TowerLampLight"
	_lamp_light.light_color = WARM
	_lamp_light.light_energy = 2.2
	_lamp_light.omni_range = 16.0
	_lamp_light.shadow_enabled = false
	_lamp_light.distance_fade_enabled = true
	_lamp_light.distance_fade_begin = 90.0
	_lamp_light.distance_fade_length = 20.0
	_lamp_light.position = Vector3(0, 1.0, 0)
	holder.add_child(_lamp_light)


func _build_invitation(pos: Vector3) -> void:
	invitation = Interactable.new()
	invitation.setup({"id": "manor_invitation", "text": "Read the invitation", "radius": 0.8, "offset": Vector3(0, 1.1, 0),
		"handler": Callable(self, "read_invitation")})
	invitation.name = "Invitation"
	add_child(invitation)
	invitation.position = pos
	var wood := Mat.outlined(Mat.toon(Color("4e2f24")), 0.012)
	var card := Mat.toon(Color("f7ecd6"), {"rim": 0.3})
	var gold := Mat.toon(GOLD, {"rim": 0.5})
	for s in [-1.0, 1.0]:
		Kit.add(invitation, Kit.box(Vector3(0.05, 1.4, 0.05), wood), Vector3(float(s) * 0.25, 0.7, 0.05), Vector3(-8, 0, float(s) * -6.0))
	Kit.add(invitation, Kit.box(Vector3(0.05, 1.4, 0.05), wood), Vector3(0, 0.7, -0.2), Vector3(12, 0, 0))
	Kit.add(invitation, Kit.box(Vector3(0.62, 0.8, 0.04), card), Vector3(0, 1.15, 0.1), Vector3(-10, 0, 0))
	Kit.add(invitation, Kit.box(Vector3(0.64, 0.06, 0.06), gold), Vector3(0, 0.74, 0.14), Vector3(-10, 0, 0))
	Kit.add(invitation, Kit.sphere(0.07, Mat.toon(Color("9b3b5a"), {"rim": 0.5}), 8, 10), Vector3(0, 0.95, 0.14), Vector3.ZERO, Vector3(1.0, 1.0, 0.4))
	var sh := CylinderShape3D.new()
	sh.radius = 0.3
	sh.height = 1.4
	Kit.static_collider(invitation, sh, Vector3(0, 0.7, 0), 1).name = "SolidBody"

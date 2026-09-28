extends Node3D
## The Bell Throat practice reveal (MP §13.3: "prepare an accessible practice reveal just before the arena").
## Three identical harvest-ribbon forms (cracked bell body, wooden mask) stand on floor plates beyond a
## lantern anchor. Raising the lantern at the anchor shows the Choir's exposure rule with TWO cues:
##   * the genuine form's plate lights up - a real light pool on the ground (the false ones stay dark);
##   * the genuine form sways with a slow, living motion (the false ones stand stiff);
##   * high_visibility_cues adds a bold ring around the genuine plate. Captions name what happens.
## Then Krystal points one out: right -> flag hw_choir_practice_done and a short confirmation; wrong ->
## a gentle explanation (never damage). Works with sound muted and without timing (timing_assist: longer).
##   station.setup({"anchor": Vector3, "forms": [Vector3 x3], "genuine": 1}); pick(i) -> String

signal solved

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const AnchorScript := preload("res://src/world/works/deep/lantern_anchor.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")

const FLAG := "hw_choir_practice_done"

var anchor_pos: Vector3 = Vector3.ZERO
var form_pos: Array = []
var genuine: int = 1
var anchor: Node3D = null
var forms: Array = []            # Node3D per form (the swaying part)
var plate_lights: Array = []     # OmniLight3D per form (only the genuine one ever turns on)
var plate_glows: Array = []
var revealed: bool = false
var last_result: String = ""
var _hv: MeshInstance3D = null
var _t: float = 0.0


func setup(p: Dictionary) -> void:
	anchor_pos = p.get("anchor", anchor_pos)
	form_pos = (p.get("forms", []) as Array).duplicate()
	genuine = int(p.get("genuine", genuine))


func _ready() -> void:
	add_to_group("hw_practice")
	anchor = AnchorScript.new()
	anchor.setup({"id": "hw_throat_practice_anchor", "reveal_radius": 7.5, "reveal_seconds": 10.0})
	anchor.name = "PracticeAnchor"
	add_child(anchor)
	anchor.position = anchor_pos
	if not form_pos.is_empty():
		var mid := Vector3.ZERO
		for f in form_pos:
			mid += f
		mid /= float(form_pos.size())
		var d := Vector3(mid.x - anchor_pos.x, 0.0, mid.z - anchor_pos.z)
		anchor.rotation.y = atan2(d.x, d.z)
	anchor.connect("raised", _on_raised)
	anchor.connect("lowered", _on_lowered)
	for i in form_pos.size():
		_build_form(i, form_pos[i])
	_hv = Art.bold_ring(self, 0.95)
	_hv.visible = false
	if genuine >= 0 and genuine < form_pos.size():
		var gp: Vector3 = form_pos[genuine]
		var to_a := Vector3(anchor_pos.x - gp.x, 0.0, anchor_pos.z - gp.z).normalized()
		_hv.position = gp + to_a + Vector3(0, 0.05, 0)
	Events.settings_changed.connect(_on_settings_changed)
	set_process(false)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_apply()


func _build_form(i: int, pos: Vector3) -> void:
	var wood := Mat.outlined(Mat.toon(Color("7a5236")), 0.016)
	var bell := Mat.outlined(Mat.toon(Palette.COPPER.darkened(0.3), {"rim": 0.45}), 0.018)
	var mask := Mat.outlined(Mat.toon(Color("d8c3a0"), {"rim": 0.3}), 0.016)
	var dark := Mat.toon(Color(0.1, 0.07, 0.09))
	var root := Node3D.new()
	root.name = "Form_%d" % i
	add_child(root)
	root.position = pos
	root.rotation.y = atan2(anchor_pos.x - pos.x, anchor_pos.z - pos.z)
	# floor plate (the "marked nearby surface"), a step toward the anchor
	var plate_at := Vector3(0, 0.02, 1.0)
	Kit.add(root, Kit.cylinder(0.7, 0.7, 0.04, Mat.toon(Color("5a4a3a")), 18), plate_at)
	var glow := Kit.cylinder(0.66, 0.66, 0.02, Mat.glow(Palette.LANTERN_GLOW, 1.2), 18)
	Kit.add(root, glow, plate_at + Vector3(0, 0.03, 0))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visible = false
	plate_glows.append(glow)
	var light := OmniLight3D.new()
	light.name = "PlateLight"
	light.light_color = Palette.LANTERN_GLOW
	light.light_energy = 1.7
	light.omni_range = 2.4
	light.shadow_enabled = false
	light.visible = false
	root.add_child(light)
	light.position = plate_at + Vector3(0, 0.8, 0)
	plate_lights.append(light)
	# the form itself (sways as one piece)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	Kit.add(body, Kit.cylinder(0.06, 0.08, 1.6, wood, 8), Vector3(0, 0.8, 0))
	Kit.add(body, Kit.cylinder(0.3, 0.55, 0.9, bell, 14), Vector3(0, 1.25, 0))
	Kit.add(body, Kit.box(Vector3(0.04, 0.5, 0.03), dark), Vector3(0.18, 1.2, 0.46), Vector3(0, 0, 18))
	Kit.add(body, Kit.sphere(0.26, mask, 10, 12), Vector3(0, 1.95, 0.05), Vector3.ZERO, Vector3(1.0, 1.2, 0.5))
	for sx in [-1.0, 1.0]:
		Kit.add(body, Kit.sphere(0.05, dark, 6, 8), Vector3(sx * 0.09, 2.0, 0.17))
	for k in 3:
		var c: Color = Art.RIBBONS[(i + k) % Art.RIBBONS.size()]
		Kit.add(body, Kit.box(Vector3(0.06, 0.6, 0.02), Mat.toon(c)), Vector3(-0.25 + float(k) * 0.25, 0.95, 0.5), Vector3(0, 0, -10.0 + float(k) * 10.0))
	forms.append(body)
	var col := StaticBody3D.new()
	col.collision_layer = 1
	col.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.5
	sh.height = 2.2
	cs.shape = sh
	cs.position = Vector3(0, 1.1, 0)
	col.add_child(cs)
	root.add_child(col)
	var it: Node3D = Interactable.new()
	it.setup({"size": Vector3(1.4, 2.2, 1.6), "offset": Vector3(0, 1.1, 0.6), "handler": Callable(self, "_on_pick").bind(i),
		"text_func": Callable(self, "_pick_text"), "id": "hw_practice_form_%d" % i})
	it.name = "Pick_%d" % i
	root.add_child(it)


func _pick_text() -> Dictionary:
	if revealed:
		return {"text": "Point out this form", "enabled": true}
	return {"text": "Raise your lantern at the anchor first, then watch the floor", "enabled": false}


func _on_pick(_player: Node, i: int) -> void:
	pick(i)


func _on_raised(_id: String) -> void:
	revealed = true
	_apply()
	Art.caption("[the anchor's light falls across the three forms - one of them lights the floor at its feet]")


func _on_lowered(_id: String) -> void:
	revealed = false
	_apply()


func _apply() -> void:
	for i in plate_lights.size():
		var on := revealed and i == genuine
		(plate_lights[i] as OmniLight3D).visible = on
		(plate_glows[i] as MeshInstance3D).visible = on
	if _hv != null:
		_hv.visible = revealed and Art.high_visibility()
	set_process(revealed)
	if not revealed and genuine >= 0 and genuine < forms.size():
		(forms[genuine] as Node3D).rotation = Vector3.ZERO


func _process(delta: float) -> void:
	_t += delta
	if genuine >= 0 and genuine < forms.size():
		var f: Node3D = forms[genuine]
		f.rotation.z = sin(_t * 1.6) * 0.07
		f.rotation.y = sin(_t * 0.9) * 0.12


## Reveal from code (tests; also what the anchor does).
func reveal() -> bool:
	return bool(anchor.call("raise", null)) if anchor != null else false


## Points out form i: "not_revealed" | "correct" | "wrong".
func pick(i: int) -> String:
	if not revealed:
		last_result = "not_revealed"
		Art.say("Raise your lantern at the anchor, then look at the floor around each form.", 4.5)
		return last_result
	if i == genuine:
		last_result = "correct"
		var first := not bool(GameState.get_flag(FLAG))
		GameState.set_flag(FLAG, true)
		Art.caption("[the genuine form shivers and goes still]")
		Art.say("That one. Its light falls on the ground, and it moves like something alive. The Choir's true form will do the same.", 7.0)
		if first:
			solved.emit()
		return last_result
	last_result = "wrong"
	Art.say("No light on the floor there - that one only looks the part. Watch which plate the anchor's light wakes.", 6.0)
	return last_result

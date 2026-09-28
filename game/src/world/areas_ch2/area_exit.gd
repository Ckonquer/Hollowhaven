extends Node3D
## A door / stair / hatch that takes Krystal to another area through Game.change_area (which autosaves
## on arrival and applies the respawn rules). Used by the Chapter Two placeholder areas; wave C may keep
## using it. Interaction contract: group "interactable" + a layer-16 sphere; the frame posts are solid.
##   setup({"text": "Back to the mine mouth", "target_area": "surface", "target_spawn": "annex_door",
##          "requires_flag": "", "locked_text": "", "use_respawn": false, "style": "door"|"stair"|"hatch"})
## use_respawn: go back to where the respawn point is (the echo trial returns to its origin that way;
## change_area never overwrites the respawn for a trial).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")

var text: String = "Leave"
var target_area: String = ""
var target_spawn: String = ""
var requires_flag: String = ""
var locked_text: String = "It won't open yet."
var use_respawn: bool = false
var style: String = "door"
var _busy := false


func setup(params: Dictionary) -> void:
	text = String(params.get("text", text))
	target_area = String(params.get("target_area", target_area))
	target_spawn = String(params.get("target_spawn", target_spawn))
	requires_flag = String(params.get("requires_flag", requires_flag))
	locked_text = String(params.get("locked_text", locked_text))
	use_respawn = bool(params.get("use_respawn", use_respawn))
	style = String(params.get("style", style))


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("area_exit")
	_build()


func is_unlocked() -> bool:
	return requires_flag == "" or bool(GameState.get_flag(requires_flag))


## {"area", "spawn"} this exit leads to.
func destination() -> Dictionary:
	if use_respawn:
		var ra := String(GameState.player.get("respawn_area", "surface"))
		var rs := String(GameState.player.get("respawn_spawn", "haven_respawn"))
		if ra == "" or ra == Game.area_id:
			return {"area": "surface", "spawn": "haven_respawn"}
		return {"area": ra, "spawn": rs}
	return {"area": target_area, "spawn": target_spawn}


func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if not is_unlocked():
		return {"text": text, "enabled": false, "reason": locked_text}
	return {"text": text, "enabled": true}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	if not is_unlocked():
		Events.notify.emit(locked_text, "info")
		return
	var d := destination()
	if String(d["area"]) == "" or Game.mode != "playing":
		return
	_busy = true
	Audio.play_3d("door_creak", global_position + Vector3.UP, -6.0)
	await Game.change_area(String(d["area"]), String(d["spawn"]))
	if is_instance_valid(self):
		_busy = false


func _build() -> void:
	var col := Palette.WOOD_DARK if style != "hatch" else Palette.STONE_DARK
	var mat := Mat.outlined(Mat.toon(col, {"noise": 0.1}), 0.018)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.3, 1.0, 0.6) if style != "stair" else Color(0.7, 0.8, 1.2)
	var h := 2.6 if style != "hatch" else 0.4
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, h, 0.25)
		post.mesh = bm
		post.material_override = mat
		post.position = Vector3(float(sx) * 0.85, h * 0.5, 0)
		add_child(post)
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.45, maxf(h - 0.2, 0.1), 0.06)
	panel.mesh = pm
	panel.material_override = glow
	panel.position = Vector3(0, (h - 0.2) * 0.5, 0)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.25, h, 0.25)
		cs.shape = box
		cs.position = Vector3(float(sx) * 0.85, h * 0.5, 0)
		body.add_child(cs)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.3
	ics.shape = sph
	ics.position = Vector3(0, 1.0, 0.3)
	ib.add_child(ics)
	add_child(ib)

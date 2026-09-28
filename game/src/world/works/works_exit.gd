extends Node3D
## A way out of the Hushed Works (Bellhouse stair, drainage stair; the deep module's vault exit may use it
## too). Same public shape as src/world/areas_ch2/area_exit.gd (group "area_exit", target_area / target_spawn /
## requires_flag / use_respawn) so flow tools and tests treat both alike; the room builds the stair / hatch
## around it. Interact -> Game.change_area(target_area, target_spawn) (autosaves on arrival).
##   setup({"text": "Climb the Bellhouse stair", "target_area": "hallowmere_reach", "target_spawn": "bellhouse_stair",
##          "requires_flag": "", "locked_text": "", "style": "stair" | "hatch"})

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

var text: String = "Leave"
var target_area: String = ""
var target_spawn: String = ""
var requires_flag: String = ""
var locked_text: String = "It won't open yet."
var use_respawn: bool = false
var style: String = "stair"

var _busy := false
var _glow: Node3D
var _t := 0.0


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
	var a := Area3D.new()
	a.name = "InteractArea"
	a.collision_layer = 16
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.3
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	a.add_child(cs)
	add_child(a)
	# A small warm beacon: the way out is always easy to find.
	_glow = Kit.add(self, Kit.sphere(0.07, Mat.glow(Color("ffe2a8"), 2.6), 6, 8), Vector3(0, 1.9, 0))
	Events.flag_set.connect(_on_flag)
	_refresh()


func is_unlocked() -> bool:
	return requires_flag == "" or bool(GameState.get_flag(requires_flag))


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
	Audio.play_3d("step_stone" if style == "stair" else "door_creak", global_position + Vector3.UP, -4.0)
	await Game.change_area(String(d["area"]), String(d["spawn"]))
	if is_instance_valid(self):
		_busy = false


func _on_flag(flag: String, _v: Variant) -> void:
	if flag == requires_flag:
		_refresh()


func _refresh() -> void:
	if _glow != null:
		_glow.visible = is_unlocked()
	set_process(_glow != null and _glow.visible)


func _process(delta: float) -> void:
	_t += delta
	_glow.scale = Vector3.ONE * (0.85 + 0.2 * sin(_t * 2.2))

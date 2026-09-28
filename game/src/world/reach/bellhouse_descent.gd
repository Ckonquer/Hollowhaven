extends Node3D
## The way down at the bottom of the Sunken Bellhouse stair, past the service gate (MP §11 steps 9-10):
## Game.change_area("hushed_works", "service_landing"). Registered as the Reach's exits["bellhouse_stair"]
## (group "area_exit", target_area / target_spawn like area_exit.gd).
##   * before ch2_lamps_linked: sealed (prompt greyed, "the stair is sealed...")
##   * the service gate (lower_gate.gd, flag ch2_service_gate_open, key foreman_key) is closed: with the
##     Foreman's Key the gate is unlocked (never consumed) and she goes down; without it a gentle message
##     (the key is never granted here)
##   * gate open: "Go down to the service landing"
## In play the gate stands in front of this node, so its own interaction collider is only switched on once
## the gate is open; direct calls (tests, other scripts) follow the rules above.

const Reach := preload("res://data/hallowmere_layout.gd")

const REVEAL_FLAG := "ch2_lamps_linked"
const GATE_FLAG := "ch2_service_gate_open"
const KEY := "foreman_key"
const SEALED_TEXT := "The stair is sealed under heavy stones marked with three lanterns. Perhaps linking the lanterns at the Conservatory will open it."

var text: String = "Go down to the service landing"
var target_area: String = "hushed_works"
var target_spawn: String = "service_landing"
var requires_flag: String = REVEAL_FLAG
var use_respawn: bool = false
var gate: Node3D = null                    # lower_gate.gd instance (may be null)
var locked_text: String = "The service gate is locked."
var _ib: StaticBody3D
var _busy := false


func setup(params: Dictionary) -> void:
	gate = params.get("gate", gate)
	target_area = String(params.get("target_area", target_area))
	target_spawn = String(params.get("target_spawn", target_spawn))
	locked_text = String(params.get("locked_text", locked_text))


func _ready() -> void:
	name = "BellhouseDescent"
	add_to_group("interactable")
	add_to_group("area_exit")
	_ib = StaticBody3D.new()
	_ib.name = "Interact"
	_ib.collision_layer = 0
	_ib.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.4
	cs.shape = sph
	cs.position = Vector3(0, 1.1, 0)
	_ib.add_child(cs)
	add_child(_ib)
	refresh()
	if not Events.flag_set.is_connected(_on_flag_set):
		Events.flag_set.connect(_on_flag_set)


func _on_flag_set(flag: String, _value: Variant) -> void:
	if flag == REVEAL_FLAG or flag == GATE_FLAG:
		refresh()


func refresh() -> void:
	if _ib != null:
		_ib.collision_layer = 16 if (is_revealed() and gate_open()) else 0


func is_revealed() -> bool:
	return bool(GameState.get_flag(REVEAL_FLAG))


func gate_open() -> bool:
	if bool(GameState.get_flag(GATE_FLAG)):
		return true
	return gate != null and is_instance_valid(gate) and bool(gate.get("is_open"))


## Same meaning as area_exit.gd: may she use it now (without unlocking anything)?
func is_unlocked() -> bool:
	return is_revealed() and gate_open()


func destination() -> Dictionary:
	return {"area": target_area, "spawn": target_spawn}


func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if not is_revealed():
		return {"text": "Take the Bellhouse stair down", "enabled": false, "reason": SEALED_TEXT}
	if gate_open():
		return {"text": text, "enabled": true}
	if GameState.has_item(KEY):
		return {"text": "Unlock the service gate and go down", "enabled": true}
	return {"text": text, "enabled": false, "reason": locked_text}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	if not is_revealed():
		Events.notify.emit(SEALED_TEXT, "info")
		return
	if not gate_open():
		if not GameState.has_item(KEY):
			Events.say.emit("", locked_text, 5.0)
			return
		if gate != null and is_instance_valid(gate) and gate.has_method("unlock"):
			gate.unlock(false)
		else:
			GameState.set_flag(GATE_FLAG, true)
	if Game.mode != "playing":
		return
	_busy = true
	Audio.play_3d("door_creak", global_position + Vector3.UP, -6.0)
	await Game.change_area(target_area, target_spawn)
	if is_instance_valid(self):
		_busy = false

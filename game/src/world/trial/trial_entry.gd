extends Node3D
## The ECHO STONE: the entry of one Echo Trial (MP §8, §15; spec §1), placed by the trial's ORIGIN area beside the
## checkpoint the trial returns to (Moonveil Manor: the ballroom rest candles, Layout.ECHO_ENTRY, after
## ch2_velour_defeated; Hushed Works: the Bell Throat, data/trials.gd TRIALS.choir.entry, after ch2_choir_defeated).
##   var e = load("res://src/world/trial/trial_entry.gd").new()
##   e.setup({"trial": "velour", "origin_area": "moonveil_manor", "origin_spawn": "manor_ballroom", "solid": true})
##   area.add_child(e); e.position = ...
## Interaction contract: group "interactable", a layer-16 sphere; get_interaction(player) / interact(player).
## The prompt is the trial's title ("Echo Trial: The Last Waltz (a remembered challenge)"). Interacting opens the
## TRIAL MENU (Game.ui.confirm): what the echo is (a memory, not undone history), the trial's own record (clears
## and best time) and what a clear leaves (the first-clear pattern, or the modest renewable resources of a repeat);
## "Enter the echo" travels (echo_trial.gd begin(): the origin checkpoint becomes the respawn point first).
## Never while a boss fight is on or outside ordinary play. `solid` adds a small collider (world layer); off by
## default so it blocks nobody. No per-frame work. Text follows arachnophobia through echo_trial.gd entry_text().

signal entered(trial_id: String)

const EchoTrial := "res://src/world/areas_ch2/echo_trial.gd"
const Fx := preload("res://src/world/trial/trial_fx.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

var trial_id: String = ""
var origin_area: String = ""
var origin_spawn: String = ""
var solid: bool = false
var menu_open: bool = false

var _script: Script = null


func setup(p: Dictionary) -> void:
	trial_id = String(p.get("trial", trial_id))
	origin_area = String(p.get("origin_area", origin_area))
	origin_spawn = String(p.get("origin_spawn", origin_spawn))
	solid = bool(p.get("solid", solid))


func _ready() -> void:
	if name.begins_with("@") or name == "":
		name = "EchoTrialEntry"
	add_to_group("interactable")
	add_to_group("echo_trial_entry")
	Fx.stone(self, 0.4)
	var a := Area3D.new()
	a.name = "InteractArea"
	a.collision_layer = 16
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.8
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	a.add_child(cs)
	add_child(a)
	if solid:
		var col := CylinderShape3D.new()
		col.radius = 0.4
		col.height = 1.3
		Kit.static_collider(self, col, Vector3(0, 0.65, 0), 1).name = "SolidBody"


## The trial area script (lazily loaded: an origin area never pulls it in until the stone exists).
func trial_script() -> Script:
	if _script == null and ResourceLoader.exists(EchoTrial):
		var s: Variant = load(EchoTrial)
		if s is Script and (s as Script).can_instantiate():
			_script = s
	return _script


## True when this trial exists and its story fight is won.
func available() -> bool:
	var s := trial_script()
	return s != null and bool(s.call("is_available", trial_id))


func get_interaction(_player: Node = null) -> Dictionary:
	if menu_open or not available():
		return {}
	return {"text": String(trial_script().call("entry_text", trial_id)), "enabled": true}


func interact(_player: Node = null) -> void:
	if menu_open or not available():
		return
	if Game.mode != "playing" or Game.boss_active():
		Events.notify.emit(refusal_text(), "info")
		return
	var choice := await open_menu()
	if choice == "enter":
		enter()


## Why the stone will not open right now: a boss fight on (Game.boss_active()) says so; anything else outside
## ordinary play (a cutscene, a menu, a load) gets the plain line.
static func refusal_text() -> String:
	if Game.boss_active():
		return "The echo stays quiet while a fight is on."
	return "The echo stays quiet for now."


## The trial menu (awaitable). Returns "enter" or "cancel". Without a UI (tests, tools) it returns "enter".
func open_menu() -> String:
	var s := trial_script()
	if s == null:
		return "cancel"
	var m: Dictionary = s.call("menu_text", trial_id)
	if Game.ui == null or not is_instance_valid(Game.ui) or not Game.ui.has_method("confirm"):
		return "enter"
	menu_open = true
	var c: String = await Game.ui.confirm(String(m.get("title", "")), String(m.get("body", "")),
		[["enter", "Enter the echo", "AccentButton"], ["cancel", "Not now", ""]])
	menu_open = false
	if not is_instance_valid(self) or not is_inside_tree() or Game.mode != "playing":
		return "cancel"
	return c


## Travels into the echo (the origin checkpoint becomes the respawn point first). True when it started.
func enter() -> bool:
	if not available():
		return false
	trial_script().call("begin", trial_id, origin_area, origin_spawn)
	entered.emit(trial_id)
	return true

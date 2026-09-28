extends Node3D
## The taught Pumpkin Mimic pocket of Pumpkintide Orchard (MP §9 / §12): a clearly marked crooked patch - a
## ring of red-ribboned stakes and a painted "twitching pumpkin" sign - with two dormant mimics among two
## ordinary pumpkins. Dormant mimics look crooked and darker, keep their eyes and jagged mouth shut, and now and
## then their stem twitches twice (the tell); the ordinary ones never move. Inspecting a twitching pumpkin
## ("Inspect twitching pumpkin"), or standing right beside one, makes every dormant mimic twitch twice, then
## wake: they become real enemies through the EnemySpawner "hr_sp_orchard_mimics" (enemy "pumpkin_mimic",
## never respawns, quest_flag_on_clear = Data.FLAG_MIMICS_CLEARED). Only this pocket's own dormant props ever
## carry that interaction: nothing here looks at structures, crop plots or saved crops.
## Guards (the Chapter Two enemy scripts arrive in a later wave):
##   * enemy script missing -> the waking pumpkins bounce away into the hedges and the patch counts as cleared
##     (the lamp can still be lit; nothing crashes; no per-tick warnings).
##   * debug_clear() (Debug.is_cheat_allowed() only) marks the encounter cleared for tests / QA.
## Leaving the area mid-fight (or reloading) puts the pocket back to dormant until it is cleared.

signal woke
signal cleared

const Data := preload("res://data/reach_west.gd")
const Art := preload("res://src/world/reach/west/west_art.gd")
const B := preload("res://src/world/reach/west/west_build.gd")
const WestInteractable := preload("res://src/world/reach/west/west_interactable.gd")
const Moment := preload("res://src/world/reach/west/pumpkin_moment.gd")
const Fx := preload("res://src/world/common/fx.gd")

const SPAWNER_ID := "hr_sp_orchard_mimics"
const MIMIC_RADIUS := 0.46
const WAKE_DELAY := 0.9
const WAKE_DELAY_ASSIST := 1.8     # timing_assist: a longer, calmer tell before they move

var area: Node = null
var enemy_override: String = ""    # tests: drive the real spawner flow with an existing enemy id
var state: String = "dormant"      # dormant | waking | awake | cleared
var spawner: Node3D = null
var dormant: Array = []            # [{"root": Node3D, "stem": Node3D, "interact": Node3D}]
var fallback_used: bool = false
var instant: bool = false          # tests: wake without the tween delay

var _center: Vector2 = Vector2.ZERO
var _near_t: float = 0.0
var _twitch_t: float = 2.5
var _rng := RandomNumberGenerator.new()
var _stubs: Node3D


func setup(p_area: Node) -> void:
	area = p_area
	_center = Data.MIMIC_POCKET["center"]
	_rng.seed = hash("hr_mimic_pocket")


func _ready() -> void:
	name = "MimicPocket"
	_build()
	if is_cleared():
		_apply_cleared()
	else:
		# Load (compile) the mimic's script now, behind the area's load fade, instead of mid-encounter on waking.
		B.enemy_available(String(Data.SPAWNERS[SPAWNER_ID]["enemy"]))


func _build() -> void:
	var prop := Art.prop_material()
	var solids := B.solid_body(self, "PocketSolids", "wood")
	var r := float(Data.MIMIC_POCKET["radius"])
	var n := int(Data.MIMIC_POCKET["stakes"])
	var stake_x: Array = []
	var ribbon_x: Array = []
	for i in n:
		var a := TAU * float(i) / float(n) + 0.15
		var p := _center + Vector2(cos(a), sin(a)) * r
		var g := B.ground(area, p)
		stake_x.append(Transform3D(Basis(Vector3.UP, a).rotated(Vector3.RIGHT, 0.06 * sin(a * 3.0)), g))
		# the ribbons hang from the stake tops and flutter (the strip is flipped)
		ribbon_x.append(Transform3D(Basis(Vector3.UP, a + 1.2) * Basis(Vector3.BACK, PI - 0.4), g + Vector3(0, 1.1, 0)))
		B.cylinder(solids, g, 0.06, 1.1)
	B.multi(self, Art.stake(), prop, stake_x, "Stakes")
	B.multi(self, Art.ribbon_strip(0.55), Art.ribbon_material(Art.RIBBON_RED), ribbon_x, "StakeRibbons", 70.0, false)
	var sp: Vector2 = Data.MIMIC_POCKET["sign"]
	B.mesh_at(self, Art.warning_sign(), prop, Transform3D(Basis(Vector3.UP, B.yaw_to(sp, Data.IRRIGATION["junction"]) + PI), B.ground(area, sp)), "WarningSign")
	B.cylinder(solids, B.ground(area, sp), 0.08, 1.4)
	# Ordinary pumpkins: round, bright, still. Carve the crooked ones for company, eat the round ones...
	var plain_x: Array = []
	for off in Data.MIMIC_POCKET["plain"]:
		var pp: Vector2 = _center + (off as Vector2)
		plain_x.append(Transform3D(Basis(Vector3.UP, float(hash(str(off)) % 628) * 0.01).scaled(Vector3.ONE * 0.4), B.ground(area, pp)))
	B.multi(self, Art.pumpkin_body(0, Art.PUMPKIN_DEEP, Art.PUMPKIN_PALE), prop, plain_x, "PlainPumpkins")
	var i := 0
	for off in Data.MIMIC_POCKET["dormant"]:
		var mp: Vector2 = _center + (off as Vector2)
		dormant.append(_dormant_mimic(mp, i))
		i += 1
	_stubs = Node3D.new()
	_stubs.name = "VineStubs"
	_stubs.visible = false
	add_child(_stubs)
	for off in Data.MIMIC_POCKET["dormant"]:
		var st := MeshInstance3D.new()
		st.mesh = Art.vine_patch(2)
		st.material_override = Art.soft_material()
		st.position = B.ground(area, _center + (off as Vector2))
		st.scale = Vector3.ONE * 0.7
		_stubs.add_child(st)


func _dormant_mimic(p: Vector2, index: int) -> Dictionary:
	var prop := Art.prop_material()
	var root := Node3D.new()
	root.name = "DormantMimic_%d" % index
	root.position = B.ground(area, p)
	root.rotation.y = B.yaw_to(p, Data.IRRIGATION["junction"]) + PI + (0.4 if index == 0 else -0.5)
	add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = Art.pumpkin_body(2, Art.MIMIC_DEEP.lightened(0.15), Art.MIMIC)
	body.material_override = prop
	body.scale = Vector3(MIMIC_RADIUS * 1.08, MIMIC_RADIUS * 0.92, MIMIC_RADIUS)
	body.rotation.z = 0.12
	root.add_child(body)
	# the tells sit on the rind of the same body variant, under the body's own (squashed, tilted) transform
	var det := MeshInstance3D.new()
	det.mesh = Art.mimic_details(2)
	det.material_override = prop
	det.scale = body.scale
	det.rotation = body.rotation
	root.add_child(det)
	var stem := Node3D.new()
	stem.name = "Stem"
	stem.position = Vector3(0.03, MIMIC_RADIUS * 0.92 * Art.pumpkin_top(2), 0)
	root.add_child(stem)
	var sm := MeshInstance3D.new()
	sm.mesh = Art.pumpkin_stem(true)
	sm.material_override = prop
	sm.scale = Vector3.ONE * MIMIC_RADIUS
	stem.add_child(sm)
	var it: Node3D = WestInteractable.new()
	it.setup({"id": "mimic_%d" % index, "size": Vector3(1.3, 1.2, 1.3), "offset": Vector3(0, 0.5, 0),
		"text_func": Callable(self, "_inspect_text"), "handler": Callable(self, "inspect"),
		"marker": true, "marker_radius": 0.75})
	root.add_child(it)
	it.set_meta("mimic_pocket", true)
	return {"root": root, "stem": stem, "interact": it}


# --- State -------------------------------------------------------------------------------------------------

func is_cleared() -> bool:
	return _flag(Data.FLAG_MIMICS_CLEARED) or _flag("spawner_cleared_" + SPAWNER_ID)


func _inspect_text() -> Dictionary:
	if state != "dormant":
		return {}
	return {"text": "Inspect twitching pumpkin", "enabled": true}


func inspect(_player: Node = null) -> void:
	wake()


## Every dormant mimic twitches twice, then they wake (see header). Returns false if already awake/cleared.
func wake() -> bool:
	if state != "dormant":
		return false
	state = "waking"
	for d in dormant:
		(d["interact"] as Node3D).set_active(false)
		Moment.twitch_stem(d["stem"], self)
	Events.caption.emit("[Both crooked pumpkins' stems twitch twice - they're waking up!]")
	Events.hint.emit("hr_mimic_fight", "Pumpkin Mimics wind up before they bite. Step aside, then strike.")
	var delay := WAKE_DELAY_ASSIST if bool(Settings.get_value("timing_assist")) else WAKE_DELAY
	if instant or not is_inside_tree():
		_finish_wake()
	else:
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(_finish_wake)
	return true


func _finish_wake() -> void:
	if state != "waking":
		return
	var enemy := enemy_override if enemy_override != "" else String(Data.SPAWNERS[SPAWNER_ID]["enemy"])
	if not B.enemy_available(enemy):
		_fallback_bounce_away()
		return
	for d in dormant:
		var root: Node3D = d["root"]
		if is_inside_tree():
			Fx.burst(self, root.global_position + Vector3.UP * 0.4, "leaves", 0.8)
		root.visible = false
	spawner = B.spawner(self, area, SPAWNER_ID, enemy_override)
	if spawner == null:
		_fallback_bounce_away()
		return
	spawner.set("min_player_distance", float(Data.SPAWNERS[SPAWNER_ID].get("min_player_distance", 2.5)))
	if spawner.has_signal("cleared"):
		spawner.cleared.connect(_on_spawner_cleared)
	state = "awake"
	if spawner.is_inside_tree() and spawner.has_method("update_spawner"):
		spawner.update_spawner()
	woke.emit()


## Enemy script missing: the pumpkins bounce off into the hedges - the patch is quiet and the story goes on.
func _fallback_bounce_away() -> void:
	fallback_used = true
	for d in dormant:
		var root: Node3D = d["root"]
		if is_inside_tree() and not instant:
			var dir := Vector3(root.global_position.x - _center.x, 0, root.global_position.z - _center.y).normalized()
			var tw := create_tween()
			tw.tween_property(root, "position", root.position + dir * 3.5 + Vector3.UP * 0.6, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(root, "scale", Vector3.ONE * 0.05, 0.3)
			tw.tween_callback(root.hide)
		else:
			root.visible = false
	Events.caption.emit("[The twitching pumpkins bounce off into the hedges and don't come back.]")
	mark_cleared(true)


func _on_spawner_cleared(_id: String) -> void:
	mark_cleared(false)


## Marks the encounter cleared (flags persisted). toast: show the clear message ourselves (the spawner shows
## its own clear_message when it clears normally).
func mark_cleared(toast: bool) -> void:
	var first := not is_cleared()
	GameState.set_flag(Data.FLAG_MIMICS_CLEARED, true)
	GameState.set_flag("spawner_cleared_" + SPAWNER_ID, true)
	GameState.deplete("spawner_" + SPAWNER_ID, -1.0)
	state = "cleared"
	_apply_cleared()
	if first and toast:
		Events.notify.emit(String(Data.SPAWNERS[SPAWNER_ID].get("clear_message", "The crooked patch is quiet now.")), "success")
	cleared.emit()


func _apply_cleared() -> void:
	state = "cleared"
	for d in dormant:
		(d["root"] as Node3D).visible = false
		(d["interact"] as Node3D).set_active(false)
	if _stubs != null:
		_stubs.visible = true


## Debug / tests only: clear the encounter without fighting (the enemy wave may not exist yet).
func debug_clear() -> bool:
	if not Debug.is_cheat_allowed():
		return false
	if spawner != null and is_instance_valid(spawner) and spawner.has_method("despawn_all"):
		spawner.despawn_all()
	mark_cleared(false)
	return true


## Throttled by the orchard controller: idle stem twitches (the tell) and waking when she stands right beside one.
func tick(player_pos: Vector3, dt: float) -> void:
	if state != "dormant":
		return
	_twitch_t -= dt
	if _twitch_t <= 0.0 and not dormant.is_empty():
		_twitch_t = _rng.randf_range(3.5, 6.0)
		var d: Dictionary = dormant[_rng.randi() % dormant.size()]
		Moment.twitch_stem(d["stem"], self)
	var near := false
	for d2 in dormant:
		var rp: Vector3 = (d2["root"] as Node3D).position
		if Vector2(player_pos.x - rp.x, player_pos.z - rp.z).length() <= Data.MIMIC_WAKE_NEAR:
			near = true
	_near_t = _near_t + dt if near else 0.0
	if _near_t >= 0.5:
		wake()


func _flag(f: String) -> bool:
	var v: Variant = GameState.get_flag(f)
	return v is bool and v

extends "res://tests/test_case.gd"
## Module B7: the Lantern Moth dusk pocket wakes only at dusk / night (data/c1x_layout.gd MOTH_HOURS): by day its
## spawner never runs and moths already out leave once none is fighting; the moonbells glow only while it is awake.
## The spawner is placed only when the lantern_moth enemy is available (a missing script never crashes). A legacy
## Brambling spawner stands in for the moth spawner so the gate is tested whatever the enemy module's state.

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")
const Moths := preload("res://src/world/surface/c1x/moth_pocket.gd")
const AreaBase := preload("res://src/world/area_base.gd")

var _area: Node3D = null


func before_each() -> void:
	fresh_state()
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1, 400)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	_area.add_child(body)


func after_each() -> void:
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
	_area = null
	await wait_frames(2)


func _pocket_with_stand_in() -> Array:
	var pocket: Node3D = Moths.Pocket.new()
	_area.add_child(pocket)
	var p: Vector2 = L.MOTH_SPAWNER["pos"]
	pocket.global_position = Vector3(p.x, 0, p.y)
	pocket.build_blooms([Transform3D(), Transform3D(Basis(), Vector3(1, 0, 0))])
	var def: Dictionary = L.MOTH_SPAWNER.duplicate()
	def["enemy"] = "brambling"          # stand-in (legacy, always present)
	def["id"] = "c1x_sp_moths_test"
	var sp: Node3D = Common.make_spawner(_area, _area, def, true)
	var player := Node3D.new()
	player.add_to_group("c1x_test_player")
	_area.add_child(player)
	player.global_position = Vector3(p.x + 12.0, 0, p.y)
	sp.set("player_override", player)
	sp.set("ignore_safe_zones", true)
	pocket.attach_spawner(sp)
	return [pocket, sp, player]


func test_spawner_sleeps_by_day_and_wakes_at_dusk() -> void:
	var r := _pocket_with_stand_in()
	var pocket: Node3D = r[0]
	var sp: Node3D = r[1]
	pocket.hour_override = 12.0
	pocket.update()
	assert_false(bool(pocket.is_awake()), "asleep at noon")
	assert_false(sp.is_processing(), "the spawner does not run by day")
	assert_eq((sp.get("alive") as Array).size(), 0, "no moths by day")
	pocket.hour_override = 19.0
	pocket.update()
	assert_true(bool(pocket.is_awake()), "awake at dusk")
	assert_true(sp.is_processing(), "the spawner runs at dusk")
	sp.update_spawner()
	await wait_frames(1)
	assert_eq((sp.get("alive") as Array).size(), int(L.MOTH_SPAWNER["count"]), "a small group appears at dusk (stand-in enemy)")
	pocket.hour_override = 2.0
	pocket.update()
	assert_true(sp.is_processing(), "still awake after midnight")
	# Dawn: they leave (none is fighting), the spawner stops.
	pocket.hour_override = 7.0
	pocket.update()
	await wait_frames(2)
	assert_false(sp.is_processing(), "asleep again in the morning")
	var alive := 0
	for e in sp.get("alive"):
		if is_instance_valid(e) and not (e as Node).is_queued_for_deletion():
			alive += 1
	assert_eq(alive, 0, "the night's moths are gone by day")


## At dawn a moth still fighting stays (no vanishing mid-fight), but the spawner is already off: nothing new
## appears by day, not even to replace one lost in that fight. Once none fights, they leave.
func test_dawn_keeps_a_fighting_moth_but_never_spawns_by_day() -> void:
	var r := _pocket_with_stand_in()
	var pocket: Node3D = r[0]
	var sp: Node3D = r[1]
	pocket.hour_override = 22.0
	pocket.update()
	sp.update_spawner()
	await wait_frames(1)
	var alive: Array = sp.get("alive")
	assert_eq(alive.size(), int(L.MOTH_SPAWNER["count"]), "the night's group")
	if alive.size() < 2:
		return
	var fighter: Node = alive[0]
	var other: Node = alive[1]
	pocket.hour_override = 6.0
	fighter.set("state", "chase")
	pocket.update()
	assert_true(bool(fighter.is_threatening()), "one is fighting")
	assert_false(sp.is_processing(), "the spawner stops at dawn even mid-fight")
	assert_eq((sp.get("alive") as Array).size(), 2, "a fight is never cut short: they stay")
	# One of them is lost mid-fight (freed elsewhere): the spawner stays off, nothing replaces it by day.
	other.queue_free()
	await wait_frames(1)
	fighter.set("state", "chase")
	pocket.update()
	sp.call("_prune")
	assert_eq((sp.get("alive") as Array).size(), 1, "no replacement by day")
	assert_false(sp.is_processing(), "still off")
	# The fight ends: the last one flutters off.
	fighter.set("state", "idle")
	pocket.update()
	await wait_frames(2)
	var left := 0
	for e in sp.get("alive"):
		if is_instance_valid(e) and not (e as Node).is_queued_for_deletion():
			left += 1
	assert_eq(left, 0, "gone once none is fighting")


func test_moonbells_glow_only_while_awake() -> void:
	var r := _pocket_with_stand_in()
	var pocket: Node3D = r[0]
	pocket.hour_override = 12.0
	pocket.update()
	var mm: MultiMeshInstance3D = pocket.get("blooms")
	assert_eq(mm.material_override, Common.moonbell_material(false), "plain by day")
	pocket.hour_override = 21.0
	pocket.update()
	assert_eq(mm.material_override, Common.moonbell_material(true), "soft glow at night")


func test_game_clock_drives_the_gate() -> void:
	var r := _pocket_with_stand_in()
	var pocket: Node3D = r[0]
	var sp: Node3D = r[1]
	GameState.total_minutes = 12.0 * 60.0
	pocket.update()
	assert_false(sp.is_processing(), "noon by the game clock")
	GameState.total_minutes = 1440.0 + 22.0 * 60.0
	pocket.update()
	assert_true(sp.is_processing(), "night by the game clock")


func test_real_pocket_build_is_guarded() -> void:
	Moths.build(_area)
	await wait_frames(1)
	var pocket: Node = get_tree().get_first_node_in_group("c1x_moth_pocket")
	assert_not_null(pocket, "pocket built")
	var sp: Variant = pocket.get("spawner")
	if Common.enemy_available("lantern_moth"):
		assert_true(sp is Node3D, "moth spawner placed")
		if sp is Node3D:
			assert_eq(String((sp as Node3D).get("spawner_id")), String(L.MOTH_SPAWNER["id"]), "c1x_sp_moths")
			assert_eq(String((sp as Node3D).get("enemy_id")), "lantern_moth")
	else:
		assert_null(sp, "no spawner while lantern_moth is unavailable (and no crash)")
	assert_eq((pocket.get("blooms") as MultiMeshInstance3D).multimesh.instance_count, L.MOTH_BLOOMS.size(), "moonbells")


## Integration with the enemy module (skipped while lantern_moth is not available): real moths at night only.
func test_real_moths_only_at_night_when_available() -> void:
	if not Common.enemy_available("lantern_moth"):
		print("    (skipped: lantern_moth not available yet)")
		return
	Moths.build(_area)
	await wait_frames(1)
	var pocket: Node3D = get_tree().get_first_node_in_group("c1x_moth_pocket")
	var sp: Node3D = pocket.get("spawner")
	var player := Node3D.new()
	_area.add_child(player)
	var p: Vector2 = L.MOTH_SPAWNER["pos"]
	player.global_position = Vector3(p.x + 14.0, 0, p.y)
	sp.set("player_override", player)
	sp.set("ignore_safe_zones", true)
	pocket.hour_override = 13.0
	pocket.update()
	for i in 4:
		if sp.is_processing():
			sp.update_spawner()
	assert_eq((sp.get("alive") as Array).size(), 0, "no Lantern Moths by day")
	pocket.hour_override = 20.5
	pocket.update()
	sp.update_spawner()
	await wait_frames(2)
	var alive: Array = sp.get("alive")
	assert_eq(alive.size(), int(L.MOTH_SPAWNER["count"]), "Lantern Moths gather at dusk")
	for e in alive:
		assert_eq(String((e as Node).get("enemy_id")), "lantern_moth", "they are Lantern Moths")
		assert_true((e as Node3D).global_position.distance_to(sp.global_position) < float(L.MOTH_SPAWNER["radius"]) + 3.0, "near the moonbells")

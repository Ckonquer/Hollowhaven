extends "res://tests/test_case.gd"
## AUDIT VERIFIER probes (combat). Headless, manual ticks, no saves. Measures how the auditor's
## findings play out in the real Below arena; assertions describe the intended behaviour.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Boss := preload("res://src/enemies/weaver_boss.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")
const Combat := preload("res://src/combat/combat.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const WORLD := "res://src/world/below/below_world.gd"

const DT := 0.05

var _nodes: Array = []
var area: Node3D = null
var _saved_area: Node = null
var _saved_player: Node3D = null
var _saved_mode: String = ""
var _saved_area_id: String = ""
var _saved_companions: Dictionary = {}


class Dummy extends CharacterBody3D:
	var health: Node

	func _init() -> void:
		health = preload("res://src/combat/health.gd").new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("arachnophobia", false)
	_saved_area = Game.area
	_saved_player = Game.player
	_saved_mode = Game.mode
	_saved_area_id = Game.area_id
	_saved_companions = Game.companion_nodes
	Game.area = null
	Game.player = null
	Game.companion_nodes = {}


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	for n in get_tree().get_nodes_in_group("heartseed_pickup"):
		n.queue_free()
	for c in get_children():
		if c.name.begins_with("BurnedAnchor"):
			c.queue_free()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Game.area = _saved_area
	Game.player = _saved_player
	Game.mode = _saved_mode
	Game.area_id = _saved_area_id
	Game.companion_nodes = _saved_companions
	Combat.invalidate_light_cache()
	await wait_frames(2)


func _dummy(pos: Vector3, parent: Node = null) -> Node3D:
	var d := Dummy.new()
	(parent if parent != null else self).add_child(d)
	d.global_position = pos
	_nodes.append(d)
	return d


## Real Below: the boss clings at the centre anchor (A3) while Krystal kindles the SE brazier; it is
## scorched and lands. Which of the natural approach spots can land a sword swing (LOS only)?
func test_probe_scorched_at_centre_anchor_reachability() -> void:
	area = load(WORLD).new()
	add_child(area)
	await wait_physics(3)
	var boss: Node = area.get("boss")
	assert_not_null(boss)
	if boss == null:
		return
	boss.set_process(false)
	boss.intensity_override = 1
	var c := Layout.ARENA_CENTER
	var brs: Array = area.get("braziers")
	var bz: Vector3 = (brs[0] as Node3D).global_position
	var target := _dummy(Vector3(105.0, -12.0, -135.5), area)
	boss.target_override = target
	boss.call("_enter_cling", 0.1)
	boss.call("_begin_reposition")
	var t := 0.0
	while String(boss.state) != "cling" and t < 6.0:
		boss.tick(DT)
		t += DT
	var a3: Vector3 = Layout.ARENA_ANCHORS[3]
	assert_true((boss.get("_anchor") as Vector3).distance_to(a3) < 0.1, "at A3")
	# Krystal is now at the SE brazier kindling; the boss telegraphs a drop onto her from A3.
	target.global_position = bz + (Vector3(c.x, bz.y, c.z) - bz).normalized() * 1.2
	boss.call("_begin_telegraph")
	assert_eq(String(boss.state), "telegraph")
	(brs[0] as Node).call("light")
	assert_eq(String(boss.state), "scorch_fall", "kindle completes mid-telegraph -> scorch fall from A3")
	t = 0.0
	while String(boss.state) != "scorched" and t < 2.0:
		boss.tick(DT)
		t += DT
	var bp: Vector3 = (boss as Node3D).global_position
	var aim: Vector3 = boss.get_aim_point()
	var space := (boss as Node3D).get_world_3d().direct_space_state
	# 1) Walking straight from the lit brazier toward the boss.
	var dir := Vector3(aim.x - bz.x, 0.0, aim.z - bz.z).normalized()
	var line_blocked := 0
	var line_total := 0
	var line_log: Array = []
	for i in 6:
		var dist := 1.5 + 0.5 * float(i)      # 1.5 .. 4.0 m from the boss (reach 2.5 + hit_radius 1.8)
		var pos := Vector3(aim.x, -12.0, aim.z) - dir * dist
		var o := pos + Vector3.UP * 0.9
		var ok := Combat.has_line_of_sight(space, o, aim, [])
		line_total += 1
		if not ok:
			line_blocked += 1
		line_log.append("%.1fm:%s" % [dist, "hit" if ok else "BLOCKED"])
	# 2) A ring of spots 2.5 m around it.
	var ring_blocked: Array = []
	for k in 16:
		var ang := TAU * float(k) / 16.0
		var pos2 := Vector3(aim.x + cos(ang) * 2.5, -12.0, aim.z + sin(ang) * 2.5)
		if Vector2(pos2.x - c.x, pos2.z - c.z).length() < 1.3:
			continue                          # Krystal cannot stand inside the cocoon
		if not Combat.has_line_of_sight(space, pos2 + Vector3.UP * 0.9, aim, []):
			ring_blocked.append(int(rad_to_deg(ang)))
	print("PROBE landed %.2f m from centre (%.2f m from brazier); straight approach from SE brazier: %s; blocked ring angles (deg, +x=east, +z=south): %s" % [
		Vector2(bp.x - c.x, bp.z - c.z).length(), Vector2(bp.x - bz.x, bp.z - bz.z).length(), str(line_log), str(ring_blocked)])
	assert_eq(line_blocked, 0, "the straight approach from the brazier she just lit reaches the stunned boss (%s)" % str(line_log))


## Candidate 2 timeline: death mid-kindle -> brazier lights during the death screen; Krystal wakes at
## the arena checkpoint (~23.6 m out). How long do boss bar / boss music (fight_started) linger?
func test_probe_death_kindle_timeline() -> void:
	GameState.give_item("lantern", 1)
	var anchors := [Vector3(-6, 8, -4), Vector3(6, 8, -4), Vector3(0, 8, 6)]
	var brs: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "vb%d" % i})
		add_child(b)
		b.global_position = Vector3(anchors[i].x * 0.8, 0.0, anchors[i].z * 0.8)
		b.set_process(false)
		brs.append(b)
		_nodes.append(b)
	var d := _dummy((brs[0] as Node3D).global_position + Vector3(0, 0, 2.5))   # knocked back ~2.5 m
	var boss: Node = Factory.create("weaver_matron", {"arena_center": Vector3.ZERO, "anchors": anchors, "braziers": brs})
	add_child(boss)
	_nodes.append(boss)
	boss.set_process(false)
	boss.target_override = d
	boss.intensity_override = 1
	boss.fast_defeat = true
	var t := 0.0
	while String(boss.state) != "cling" and t < 6.0:
		boss.tick(DT)
		t += DT
	(brs[0] as Node).call("interact", d)
	Game.mode = "dead"
	Events.player_died.emit()
	var threat_log: Array = []
	var clock := 0.0
	var respawn_at := 4.0                    # death screen ~3 s + fades
	var cleared_at := -1.0
	var respawned := false
	var restarted := false
	while clock < 20.0:
		(brs[0] as Node).call("_process", DT)
		boss.tick(DT)
		clock += DT
		if bool(boss.fight_started):
			restarted = true
		if not respawned and clock >= respawn_at:
			respawned = true
			respawn_at = clock                    # the actual respawn tick (float steps)
			Game.mode = "playing"
			d.global_position = Vector3(0.0, 0.0, 23.6)      # cp_arena-like distance from the centre
		if respawned and cleared_at < 0.0 and not bool(boss.fight_started):
			cleared_at = clock
	print("PROBE brazier lit: %s; boss state at end: %s; fight_started cleared %.2f s after death (%.2f s after respawn)" % [
		str((brs[0] as Node).call("is_lit")), String(boss.state), cleared_at, cleared_at - respawn_at])
	assert_true(cleared_at < 0.0 or cleared_at <= respawn_at + 0.001, "no boss bar/music lingering after respawn (cleared %.2f s after respawn)" % (cleared_at - respawn_at))
	# FIXED: the kindle fizzles with Krystal, so nothing restarts the fight behind the death screen.
	assert_false(restarted, "the fight never restarted while she was down or after she woke at the checkpoint")
	assert_false(bool((brs[0] as Node).call("is_lit")), "the kindle she started when she went down fizzled")


## Candidate (C) comparison: a NORMAL missed slam onto Krystal kindling at a brazier lands just as close.
func test_probe_normal_slam_next_to_brazier_distance() -> void:
	var anchors := [Vector3(6.1, 7.5, 3.5), Vector3(-6.1, 7.5, 3.5), Vector3(0.0, 7.7, -7.0)]
	var brs: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "nb%d" % i})
		add_child(b)
		b.global_position = Vector3(anchors[i].x, 0.0, anchors[i].z)
		brs.append(b)
		_nodes.append(b)
	var bz: Vector3 = (brs[0] as Node3D).global_position
	var d := _dummy(bz + (Vector3.ZERO - bz).normalized() * 0.9)
	var boss: Node = Factory.create("weaver_matron", {"arena_center": Vector3.ZERO, "anchors": anchors, "braziers": brs})
	add_child(boss)
	_nodes.append(boss)
	boss.set_process(false)
	boss.target_override = d
	boss.intensity_override = 1
	var t := 0.0
	while String(boss.state) != "drop" and t < 15.0:
		boss.tick(DT)
		t += DT
	d.global_position = bz + (Vector3.ZERO - bz).normalized() * 4.0   # she dodged away: a miss
	t = 0.0
	while String(boss.state) == "drop" and t < 2.0:
		boss.tick(DT)
		t += DT
	var bp: Vector3 = (boss as Node3D).global_position
	var flat := Vector2(bp.x - bz.x, bp.z - bz.z).length()
	print("PROBE normal missed slam: state %s, %.2f m from the brazier" % [String(boss.state), flat])
	assert_eq(String(boss.state), "stuck")

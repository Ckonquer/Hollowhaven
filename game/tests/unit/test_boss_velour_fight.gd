extends "res://tests/test_case.gd"
## Count Velour, whole fights with a simple scripted stand-in (module C6a). The stand-in walks at Krystal's walk
## speed (4.2 m/s), swings every 0.55 s when he is in reach AND in a window, otherwise walks to a dark candle and
## relights it, and never dodges. The real boss logic runs unchanged. Checks: every intensity can be won (no softlock,
## no endless invulnerability), all three phases happen in order, phase C needs the candle rule (a light stagger),
## and the engaged time stays bounded - it prints the simulated seconds so tuning has a baseline. These are
## lower-bound numbers for a tireless bot, NOT a claim about real play (MP 13.1 asks for ~2-4 minutes of engaged
## first-encounter play; that needs real-input playtesting).

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Boss := preload("res://src/enemies/count_velour.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const EnemyBase := preload("res://src/enemies/enemy_base.gd")

const DT := 0.05
const CENTER := Vector3(0, 0, 0)
const WALK := 4.2
const SWING := 0.55
const REACH := 2.2

var _nodes: Array = []
var _phases: Array = []


class Dummy extends CharacterBody3D:
	var health: Node
	var lantern_on := false

	func _init() -> void:
		health = preload("res://src/player/player_health.gd").new()
		health.name = "Health"
		health.max_hp = 100000.0
		add_child(health)
		collision_layer = 2

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


var _saved_assist: Variant = false        # Settings "timing_assist" pinned off (exact timings below), restored after


func before_each() -> void:
	fresh_state()
	_saved_assist = Settings.get_value("timing_assist")
	Settings.set_value("timing_assist", false)
	_nodes.clear()
	_phases.clear()
	EnemyBase.reset_attack_tokens()
	Events.boss_phase_changed.connect(_on_phase)


func after_each() -> void:
	Settings.set_value("timing_assist", _saved_assist)
	Events.boss_phase_changed.disconnect(_on_phase)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.get_parent() == self:
			e.queue_free()
	_nodes.clear()
	EnemyBase.reset_attack_tokens()
	await wait_frames(2)


func _on_phase(_id: String, p: int) -> void:
	_phases.append(p)


## Runs one fight; returns {"won", "seconds", "damage_taken", "c_staggers", "dashes", "dispersals", "channels"}.
func _fight(intensity: int, weapon: float, seed_value: int) -> Dictionary:
	var candles: Array = []
	var spots := [Vector3(0, 0, -7.5), Vector3(-6.5, 0, 3.75), Vector3(6.5, 0, 3.75)]
	for i in spots.size():
		var c: Node3D = WardCandle.new()
		c.setup({"id": "c%d" % i, "lit": true, "pool_radius": 3.2})
		add_child(c)
		c.global_position = spots[i]
		_nodes.append(c)
		candles.append(c)
	var bot := Dummy.new()
	add_child(bot)
	bot.global_position = Vector3(0, 0, 8)
	_nodes.append(bot)
	var b: Node3D = Factory.create("count_velour", {"arena_center": CENTER, "arena_radius": 12.0, "candles": candles,
		"seed": seed_value, "helper_points": [Vector3(-10, 0, 9), Vector3(10, 0, 9)]}, CENTER)
	add_child(b)
	_nodes.append(b)
	b.set_process(false)
	b.target_override = bot
	b.intensity_override = intensity
	b.fast_defeat = true
	b.start_fight()
	var t := 0.0
	var swing := 0.0
	var hp0: float = float(bot.health.hp)
	while not bool(b.call("is_gone")) and t < 600.0:
		b.tick(DT)
		t += DT
		swing -= DT
		var bp: Vector3 = b.global_position
		var target := Vector3.INF
		if bool(b.call("can_be_hit_by", bot)):
			target = Vector3(bp.x, 0.0, bp.z)
		else:
			for c in candles:
				if not bool(c.call("is_lit")):
					target = (c as Node3D).global_position
					break
		if target.is_finite():
			var to := Vector3(target.x - bot.global_position.x, 0.0, target.z - bot.global_position.z)
			var d := to.length()
			var stop := REACH - 0.3 if target == Vector3(bp.x, 0.0, bp.z) else 1.2
			if d > stop:
				bot.global_position += to / d * minf(WALK * DT, d - stop)
		# Relight a dark candle when standing by it.
		for c in candles:
			if not bool(c.call("is_lit")) and Vector2(c.global_position.x - bot.global_position.x, c.global_position.z - bot.global_position.z).length() <= 1.6:
				c.call("light", bot)
		# Swing when he is in reach and in a window.
		if swing <= 0.0 and bool(b.call("can_be_hit_by", bot)) and Vector2(bp.x - bot.global_position.x, bp.z - bot.global_position.z).length() <= REACH:
			b.health.apply_damage(weapon, bot, Vector3.FORWARD)
			swing = SWING
	return {"won": bool(b.call("is_gone")), "seconds": t, "damage_taken": hp0 - float(bot.health.hp),
		"c_staggers": int(b.c_staggers), "dashes": int(b.dashes), "dispersals": int(b.dispersals),
		"channels": int(b.channels_started), "drains": int(b.drains_completed) + int(b.drains_broken)}


func test_every_intensity_is_winnable_in_bounded_time_with_all_phases() -> void:
	var names := ["Gentle", "Standard", "Intense"]
	for i in 3:
		_phases.clear()
		var r := _fight(i, 18.0, 7 + i)
		print("VELOUR SIM %s copper(18): won=%s engaged=%.1f s, bot took %.0f, dashes %d, drains %d, dispersals %d, channels %d, light staggers %d"
			% [names[i], str(r["won"]), float(r["seconds"]), float(r["damage_taken"]), int(r["dashes"]), int(r["drains"]),
			int(r["dispersals"]), int(r["channels"]), int(r["c_staggers"])])
		assert_true(bool(r["won"]), "%s: the fight can be won" % names[i])
		assert_true(float(r["seconds"]) < 420.0, "%s: bounded (%.0f s)" % [names[i], float(r["seconds"])])
		assert_true(float(r["seconds"]) > 45.0, "%s: not a pushover even for a tireless bot (%.0f s)" % [names[i], float(r["seconds"])])
		assert_eq(_phases.slice(0, 3), [1, 2, 3], "%s: phases A -> B -> C in order" % names[i])
		assert_true(int(r["c_staggers"]) >= 1, "%s: the candle rule was used" % names[i])
		assert_true(int(r["dispersals"]) >= 1, "%s: the ballroom took flight" % names[i])
		assert_true(int(r["drains"]) >= 1, "%s: the tether appeared" % names[i])
		for n in _nodes:
			if is_instance_valid(n):
				n.queue_free()
		_nodes.clear()
		await wait_frames(1)


func test_strong_gear_helps_but_never_skips_the_rules() -> void:
	var weak := _fight(1, 18.0, 31)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await wait_frames(1)
	_phases.clear()
	var strong := _fight(1, 34.0, 31)
	print("VELOUR SIM Standard copper(18) %.1f s vs moonsteel(34) %.1f s" % [float(weak["seconds"]), float(strong["seconds"])])
	assert_true(bool(strong["won"]))
	assert_true(float(strong["seconds"]) <= float(weak["seconds"]) + 1.0, "strong equipment shortens the fight")
	assert_true(int(strong["c_staggers"]) >= 1, "but the candle rule is still needed")
	assert_eq(_phases.slice(0, 3), [1, 2, 3], "and no phase is skipped")

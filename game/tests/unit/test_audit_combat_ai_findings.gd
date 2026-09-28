extends "res://tests/test_case.gd"
## AUDIT (combat / enemies / companions / director). Each test asserts the INTENDED behaviour; a
## failing assertion is the evidence for a finding. Headless only, manual ticks, no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Boss := preload("res://src/enemies/weaver_boss.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")
const Stalker := preload("res://src/enemies/stalker.gd")
const Combat := preload("res://src/combat/combat.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const PlayerLogic := preload("res://src/player/player_logic.gd")
const CompanionScript := preload("res://src/companions/companion.gd")
const CompanionLogic := preload("res://src/companions/companion_logic.gd")
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


## Krystal stand-in with a lantern (group "light_source" contract, like player.gd).
class LitDummy extends Dummy:
	var light_radius: float = 6.0
	var lantern_on: bool = true

	func is_light_active() -> bool:
		return lantern_on


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


func _make_area() -> Node3D:
	var a: Node3D = load(WORLD).new()
	add_child(a)
	await wait_physics(3)
	return a


func _swing(attacker: Node3D, facing: Vector3) -> Array:
	# Exactly what player.gd _melee_hit() does with the Copper Sword (18 dmg, reach 2.5).
	return Combat.melee(attacker, attacker.global_position + Vector3.UP * 0.9, facing, 2.5, PlayerLogic.MELEE_ARC, 18.0, ["enemy"], 4.0)


# --- 1. Scorched boss lands in / against the Heartseed cocoon: swings silently do nothing ----------------

func test_scorched_boss_never_lands_in_the_heartseed_cocoon() -> void:
	area = await _make_area()
	var boss: Node = area.get("boss")
	assert_not_null(boss, "the real Below builds its boss")
	if boss == null:
		return
	boss.set_process(false)
	boss.intensity_override = 1
	var c := Layout.ARENA_CENTER
	var target := _dummy(Vector3(105.0, -12.0, -135.5), area)     # Krystal fighting beside the cocoon
	boss.target_override = target
	var brs: Array = area.get("braziers")
	# (A) Reposition toward Krystal picks the centre anchor (ARENA_ANCHORS[3], 1.0 m from the centre).
	boss.call("_enter_cling", 0.1)
	boss.call("_begin_reposition")
	var t := 0.0
	while String(boss.state) != "cling" and t < 6.0:
		boss.tick(DT)
		t += DT
	var a3: Vector3 = Layout.ARENA_ANCHORS[3]
	assert_true((boss.get("_anchor") as Vector3).distance_to(a3) < 0.1, "it clings to the centre anchor (the one nearest Krystal)")
	(brs[0] as Node).call("light")                                 # Krystal lights a brazier (south-east)
	assert_eq(String(boss.state), "scorch_fall")
	t = 0.0
	while String(boss.state) != "scorched" and t < 2.0:
		boss.tick(DT)
		t += DT
	var bp: Vector3 = (boss as Node3D).global_position
	var from_c := Vector2(bp.x - c.x, bp.z - c.z).length()
	assert_true(from_c >= Boss.CENTRE_CLEARANCE - 0.01, "scorch_landing() doc: never closer than CENTRE_CLEARANCE (%.1f) to the cocoon - landed %.2f m from the centre" % [Boss.CENTRE_CLEARANCE, from_c])
	assert_true(boss.is_vulnerable(), "stunned: the damage window is open")
	# FIXED: it is pushed straight out (north, the side it hung from), so the cocoon is no longer
	# between it and the way back from the brazier Krystal just lit (the south-east one).
	var aim: Vector3 = boss.get_aim_point()
	var bz: Vector3 = (brs[0] as Node3D).global_position
	var back := Vector3(aim.x - bz.x, 0.0, aim.z - bz.z).normalized()
	var south := _dummy(Vector3(aim.x, -12.0, aim.z) - back * 2.5, area)   # walking back from the lit brazier
	var hp0: float = boss.health.hp
	var hits_s: Array = _swing(south, back)
	assert_true(hits_s.size() > 0, "a sword swing from the brazier (south-east) side hits the stunned boss (hp %.0f -> %.0f)" % [hp0, float(boss.health.hp)])
	var north := _dummy(Vector3(bp.x, -12.0, bp.z - 2.0), area)
	var hits_n: Array = _swing(north, Vector3(0, 0, 1))
	assert_true(hits_n.size() > 0, "control: the same swing from the north side does land")
	# (B) Scorched while repositioning across the centre (A1 -> A4 passes 0.47 m from it).
	var a1: Vector3 = Layout.ARENA_ANCHORS[1]
	boss.set("_anchor", a1)
	(boss as Node3D).global_transform = boss.call("_ceiling_pose", a1, target.global_position)
	boss.call("_enter_cling", 0.1)
	target.global_position = Vector3(110.0, -12.0, -141.0)        # Krystal runs to the south-east
	boss.call("_begin_reposition")
	assert_eq(String(boss.state), "reposition")
	var dur: float = float(boss.get("_state_len"))
	boss.tick(dur * 0.5)                                            # halfway along the ceiling
	(brs[2] as Node).call("light")                                 # the north brazier
	var fall_to: Transform3D = boss.get("_to")
	assert_true(fall_to.origin.y < c.y + 0.3, "the scorched fall aims at the floor, not the cocoon's top (aims at y %.2f, floor %.2f)" % [fall_to.origin.y, c.y])
	t = 0.0
	while String(boss.state) != "scorched" and t < 2.0:
		boss.tick(DT)
		t += DT
	bp = (boss as Node3D).global_position
	from_c = Vector2(bp.x - c.x, bp.z - c.z).length()
	assert_true(from_c > 0.95, "never ends up standing INSIDE the cocoon collider (r 0.95): %.2f m from the centre" % from_c)
	var s2 := _dummy(Vector3(bp.x, -12.0, -136.0), area)
	var n2 := _dummy(Vector3(bp.x, -12.0, -139.6), area)
	var hp1: float = boss.health.hp
	var any := _swing(s2, Vector3(0, 0, -1)).size() + _swing(n2, Vector3(0, 0, 1)).size()
	assert_true(any > 0, "the stunned boss can be hit from somewhere (hp %.0f -> %.0f after swings from both sides)" % [hp1, float(boss.health.hp)])


## Brazier finishes kindling while the boss is mid-drop onto Krystal (who is standing at that brazier):
## _pending_scorch -> _land_scorched() at the slam point, bypassing scorch_landing()'s clearance.
func test_scorch_during_a_drop_also_lands_clear_of_the_brazier() -> void:
	var anchors := [Vector3(6.1, 7.5, 3.5), Vector3(-6.1, 7.5, 3.5), Vector3(0.0, 7.7, -7.0)]
	var brs: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "pb%d" % i})
		add_child(b)
		b.global_position = Vector3(anchors[i].x, 0.0, anchors[i].z)
		brs.append(b)
		_nodes.append(b)
	var bz: Vector3 = (brs[0] as Node3D).global_position
	var d := _dummy(bz + (Vector3.ZERO - bz).normalized() * 0.9)    # kindling it, right beside the bowl
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
	assert_eq(String(boss.state), "drop", "it drops on Krystal's spot")
	(brs[0] as Node).call("light")                                 # the kindle completes mid-drop
	t = 0.0
	while String(boss.state) != "scorched" and t < 2.0:
		boss.tick(DT)
		t += DT
	assert_eq(String(boss.state), "scorched")
	var bp: Vector3 = (boss as Node3D).global_position
	var flat := Vector2(bp.x - bz.x, bp.z - bz.z).length()
	assert_true(flat >= Boss.BRAZIER_CLEARANCE - 0.01, "a scorched landing never ends right beside a brazier (BRAZIER_CLEARANCE %.1f): %.2f m" % [Boss.BRAZIER_CLEARANCE, flat])


# --- 2. Director stalker pass aborts at once whenever Krystal's lantern (or Lumi) is lit -----------------

func test_stalker_pass_plays_out_when_krystal_carries_a_lantern() -> void:
	var d := LitDummy.new()
	add_child(d)
	d.global_position = Vector3(500.0, 0.0, 500.0)
	d.add_to_group("light_source")
	_nodes.append(d)
	var route: Array = []
	var normals: Array = []
	for i in 6:
		route.append(Vector3(480.0 + 3.0 * float(i), 4.0, 500.0))   # ceiling route 5-20 m from Krystal
		normals.append(Vector3.DOWN)
	var s: Node = Factory.create("weaver", {"route": route, "normals": normals, "ambush_points": [], "zone": "silk"})
	add_child(s)
	_nodes.append(s)
	s.set_process(false)
	s.target_override = d
	s.intensity_override = 1
	s.los_override = 1
	var seen: Array = []
	s.state_changed.connect(func(st: String) -> void: seen.append(st))
	# Control: lantern down -> it emerges at the far end and crawls toward her.
	d.lantern_on = false
	Combat.invalidate_light_cache()
	assert_true(bool(s.pass_overhead()), "pass accepted")
	for i in 20:
		s.tick(DT)
	assert_true(seen.has("pass"), "control (lantern off): it crawls (%s)" % str(seen))
	var t := 0.0
	while String(s.state) != "hidden" and t < 20.0:
		s.tick(DT)
		t += DT
	assert_eq(String(s.state), "hidden")
	# The normal case in the Below: lantern raised.
	d.lantern_on = true
	Combat.invalidate_light_cache()
	seen.clear()
	assert_true(bool(s.pass_overhead()), "pass accepted (the runner already played the caption, sting and shake)")
	var own_light: float = Combat.light_at((s as Node3D).global_position)
	for i in 20:
		s.tick(DT)
	assert_true(own_light < 0.05, "it emerged far outside the lantern's reach (light there %.2f)" % own_light)
	assert_true(seen.has("pass"), "lantern on: the pass still crawls overhead, it only shrinks back when it gets INTO the light (%s)" % str(seen))


# --- 3. A kindling brazier finishes while Krystal is dead and restarts the fight --------------------------

func test_brazier_does_not_restart_the_fight_during_the_death_screen() -> void:
	GameState.give_item("lantern", 1)
	var anchors := [Vector3(-6, 8, -4), Vector3(6, 8, -4), Vector3(0, 8, 6)]
	var brs: Array = []
	for i in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "ab%d" % i})
		add_child(b)
		b.global_position = Vector3(anchors[i].x * 0.8, 0.0, anchors[i].z * 0.8)
		b.set_process(false)
		brs.append(b)
		_nodes.append(b)
	var d := _dummy((brs[0] as Node3D).global_position + Vector3(0, 0, 1.4))
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
	assert_true(bool(boss.fight_started), "fight on")
	(brs[0] as Node).call("interact", d)                          # Krystal starts kindling...
	Game.mode = "dead"                                             # ...and is slammed down mid-kindle
	Events.player_died.emit()
	assert_false(bool(boss.fight_started), "death reset: the boss stands down")
	(brs[0] as Node).call("_process", 1.6)                         # her body is still beside the brazier
	assert_false(bool(boss.fight_started), "nothing re-engages while Krystal is dead (brazier lit: %s, boss state: %s)" % [str((brs[0] as Node).call("is_lit")), String(boss.state)])
	assert_false(bool(boss.is_threatening()), "no boss bar / boss music during the death screen")


# --- 4. The lift ride dragged a companion that was told to WAIT down there (fixed: regression) ----------

func test_lift_ride_leaves_a_waiting_companion_at_its_spot() -> void:
	GameState.set_flag("weaver_defeated", true)
	area = await _make_area()
	Game.area_id = "below"
	var gd := GDScript.new()
	gd.source_code = "extends Node3D\nfunc teleport(xf: Transform3D) -> void:\n\tglobal_transform = xf\n"
	assert_eq(gd.reload(), OK)
	var probe: Node3D = Node3D.new()
	probe.set_script(gd)
	area.add_child(probe)
	probe.global_position = area.get_spawn("lift_chamber").origin
	Game.player = probe
	var wait_spot := Vector3(99.0, -12.0, -141.0)                  # "Wait here" in the chamber
	GameState.companion("pebble")["befriended"] = true
	GameState.set_companion_assignment("pebble", "wait", "below", wait_spot)
	var c: Node3D = CompanionScript.new()
	c.setup({"id": "pebble", "mode": "wait", "home": Vector3.ZERO, "wild": Vector3.ZERO, "wait": wait_spot})
	area.add_child(c)
	c.global_position = wait_spot + Vector3.UP * 0.05
	Game.companion_nodes = {"pebble": c}
	await wait_physics(2)
	assert_eq(String(c.get("mode")), "wait")
	await area.call("ride_lift", "lift_bottom")
	var dist := c.global_position.distance_to(wait_spot)
	assert_true(dist < 5.0, "a companion told to wait stays where Krystal left it (it was teleported %.0f m, up to the landing)" % dist)
	assert_eq(String(c.get("mode")), "wait", "still waiting")


# --- 5. Enemies keep attacking while a non-pausing panel locks Krystal's input --------------------------

## (removed test_enemies_hold_off_while_a_panel_locks_krystals_input: by design: the companion menu is not full-screen and the world keeps living (it now closes when Krystal is hit))

## (removed test_lumi_alone_is_not_a_full_lantern: by design: Lumi's light counts as a light source (Chapter One bible, companion table))

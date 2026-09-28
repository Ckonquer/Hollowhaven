extends "res://tests/test_case.gd"
## Shared harness for the Borrowed Choir suites (test_boss_choir_*.gd). It has no tests of its own.
## A bare vault on the test node: centre (0,0,0), radius 12.4, perimeter walk from 10.4, the REAL lantern anchors
## (src/world/works/deep/lantern_anchor.gd) at the vault's three bearings and the REAL resonators
## (resonator.gd) carrying the Bellmaker's symbols (data/works_layout_deep.gd bell_symbols(), taught order).
## The boss is created through EnemyFactory, never processes by itself (manual ticks of DT), and hunts a dummy
## "Krystal" (target_override). Headless; no saves written.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Rules := preload("res://src/enemies/choir/choir_rules.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const TelegraphFx := preload("res://src/enemies/telegraph_fx.gd")
const AnchorScript := preload("res://src/world/works/deep/lantern_anchor.gd")
const ResonatorScript := preload("res://src/world/works/deep/resonator.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const PlayerHealth := preload("res://src/player/player_health.gd")

const DT := 0.05
const CENTER := Vector3(0.0, 0.0, 0.0)
const RADIUS := 12.4
const PERIM := 10.4
const ANCHOR_DEG := [-150.0, -30.0, 90.0]
const ANCHOR_R := 7.0
const RESONATOR_POS := [Vector3(-10.6, 0.0, 0.0), Vector3(10.6, 0.0, 0.0)]
const BOSS_ID := "borrowed_choir"

var anchors: Array = []
var resonators: Array = []
var phases: Array = []
var encounters: Array = []
var defeats: Array = []
var bars: Array = []
var captions: Array = []
var _saved: Dictionary = {}
var _saved_area: Variant = null


class Dummy extends CharacterBody3D:
	var health: Node
	var lantern_on := false
	var knocks: int = 0
	var hits: Array = []

	func _init(use_player_health: bool = false, hp: float = 100.0) -> void:
		health = (preload("res://src/player/player_health.gd").new() if use_player_health else preload("res://src/combat/health.gd").new())
		health.name = "Health"
		health.max_hp = hp
		add_child(health)
		collision_layer = 2
		collision_mask = 0
		health.damaged.connect(_on_hit)

	func _on_hit(amount: float, _s: Node, _d: Vector3) -> void:
		hits.append(amount)

	func knockback(_dir: Vector3, _force: float) -> void:
		knocks += 1


func before_each() -> void:
	fresh_state()
	GameState.give_item("lantern", 1)
	for k in ["high_visibility_cues", "timing_assist", "horror_intensity", "captions", "reduce_flashing"]:
		_saved[k] = Settings.get_value(k)
	Settings.set_value("high_visibility_cues", false)
	Settings.set_value("timing_assist", false)
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("captions", true)
	_saved_area = Game.area
	Game.area = null
	Base.reset_attack_tokens()
	anchors.clear()
	resonators.clear()
	phases.clear()
	encounters.clear()
	defeats.clear()
	bars.clear()
	captions.clear()
	Events.boss_phase_changed.connect(_on_phase)
	Events.boss_encounter_changed.connect(_on_encounter)
	Events.boss_defeated.connect(_on_defeated)
	Events.boss_health_changed.connect(_on_bar)
	Events.caption.connect(_on_caption)
	Combat.invalidate_light_cache()


func after_each() -> void:
	Events.boss_phase_changed.disconnect(_on_phase)
	Events.boss_encounter_changed.disconnect(_on_encounter)
	Events.boss_defeated.disconnect(_on_defeated)
	Events.boss_health_changed.disconnect(_on_bar)
	Events.caption.disconnect(_on_caption)
	for c in get_children():
		c.queue_free()
	for k in _saved:
		Settings.set_value(k, _saved[k])
	Game.area = _saved_area
	Base.reset_attack_tokens()
	Combat.invalidate_light_cache()
	await wait_frames(2)


func _on_phase(id: String, p: int) -> void:
	phases.append([id, p])


func _on_encounter(id: String, active: bool) -> void:
	encounters.append([id, active])


func _on_defeated(id: String) -> void:
	defeats.append(id)


func _on_bar(id: String, hp: float, max_hp: float) -> void:
	bars.append([id, hp, max_hp])


func _on_caption(t: String) -> void:
	captions.append(t)


# --- Building -------------------------------------------------------------------------------------------------

func make_arena() -> void:
	for i in ANCHOR_DEG.size():
		var r := deg_to_rad(float(ANCHOR_DEG[i]))
		var a: Node3D = AnchorScript.new()
		a.setup({"id": "test_anchor_%d" % i, "reveal_radius": 9.0})
		add_child(a)
		a.global_position = CENTER + Vector3(cos(r), 0.0, sin(r)) * ANCHOR_R
		anchors.append(a)
	for i in RESONATOR_POS.size():
		var rs: Node3D = ResonatorScript.new()
		rs.setup({"id": "test_resonator_%d" % i, "symbols": Layout.bell_symbols()})
		add_child(rs)
		var rp: Vector3 = RESONATOR_POS[i]
		rs.global_position = rp
		rs.rotation.y = atan2(CENTER.x - rp.x, CENTER.z - rp.z)      # plates face the centre (as the arena does)
		resonators.append(rs)


func taught_ids() -> Array:
	var out: Array = []
	for s in Layout.bell_symbols():
		out.append(String(s["id"]))
	return out


func make_boss(target: Node3D, intensity: int = 1, extra: Dictionary = {}) -> Node:
	var p := {"arena_center": CENTER, "arena_radius": RADIUS, "perimeter_radius": PERIM, "anchor_nodes": anchors,
		"resonators": resonators, "symbols": Layout.bell_symbols(), "seed": 7}
	for k in extra:
		p[k] = extra[k]
	var b: Node = Factory.create(BOSS_ID, p, CENTER)
	add_child(b)
	b.set_process(false)
	b.target_override = target
	b.intensity_override = intensity
	b.fast_defeat = true
	return b


func dummy(pos: Vector3, use_player_health: bool = false, hp: float = 100.0) -> Dummy:
	var d := Dummy.new(use_player_health, hp)
	add_child(d)
	d.global_position = pos
	d.add_to_group("player")
	return d


func companion(pos: Vector3) -> Node3D:
	var c := Node3D.new()
	add_child(c)
	c.global_position = pos
	c.add_to_group("companion")
	return c


func wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	body.global_position = center
	return body


# --- Driving ------------------------------------------------------------------------------------------------

func run(b: Node, seconds: float) -> void:
	var n := int(ceilf(seconds / DT))
	for i in n:
		b.tick(DT)


## Ticks until the boss is in state `s` (returns the seconds it took, or -1 when it never got there).
func until(b: Node, s: String, max_t: float = 40.0) -> float:
	var t := 0.0
	while String(b.state) != s and t < max_t:
		b.tick(DT)
		t += DT
	return t if String(b.state) == s else -1.0


## Starts the fight straight into phase `p` (the checkpoint way: hp at that phase's start) and runs the intro.
func start_in_phase(b: Node, p: int) -> void:
	if p > 1:
		b.phase = p
		b.health.set_hp(Rules.phase_start_hp(p, float(b.health.max_hp)))
	b.start_fight()


func raise(i: int) -> void:
	(anchors[i] as Node).call("lower")
	(anchors[i] as Node).call("raise", null)


func lower_all() -> void:
	for a in anchors:
		(a as Node).call("lower")


func strike_sequence(r: Node) -> String:
	var last := ""
	for sid in r.get("sequence"):
		last = String(r.call("strike", String(sid)))
	return last


func wrong_form(b: Node) -> int:
	return (int(b.genuine) + 1) % 3


func flat_at(dir: Vector3, dist: float) -> Vector3:
	var f := Vector3(dir.x, 0.0, dir.z).normalized()
	return CENTER + f * dist


func has_caption(part: String) -> bool:
	for c in captions:
		if String(c).contains(part):
			return true
	return false


func phase_list() -> Array:
	var out: Array = []
	for e in phases:
		if String(e[0]) == BOSS_ID:
			out.append(int(e[1]))
	return out

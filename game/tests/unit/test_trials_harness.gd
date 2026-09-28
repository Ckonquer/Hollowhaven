extends "res://tests/test_case.gd"
## Shared harness for the Echo Trial suites (test_trials_*.gd, module D1). It has no tests of its own.
## The trial area is the real scene (scenes/echo_trial.tscn -> echo_trial.gd) instantiated directly after
## EchoTrial.pending_trial is set (no Game.change_area); bosses never process by themselves (manual ticks) and hunt a
## dummy "Krystal" (target_override). Headless; nothing is saved here.

const EchoTrial := preload("res://src/world/areas_ch2/echo_trial.gd")
const TrialsData := preload("res://data/trials.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const ChoirRules := preload("res://src/enemies/choir/choir_rules.gd")
const Combat := preload("res://src/combat/combat.gd")
const TRIAL_SCENE := "res://scenes/echo_trial.tscn"
const DT := 0.05
const SPIDER_WORDS := ["spider", "web", "silk", "skitter", "arachn", "weaver", "brood"]
## Every story flag a trial could be tempted to touch (none may change).
const STORY_FLAGS := ["weaver_defeated", "ward_restored", "chapter_one_complete", "ch2_velour_defeated", "ch2_manor_restored",
	"ch2_choir_defeated", "ch2_crossing_cleared", "chapter_two_complete", "ch2_feast", "ch2_manor_lamp_lit"]

var nodes: Array = []
var ended: Array = []
var defeats: Array = []
var said: Array = []
var captions: Array = []
var _saved: Dictionary = {}
var _saved_area: Node = null
var _saved_player: Node3D = null
var _saved_area_id: String = ""
var _saved_companions: Dictionary = {}


class Dummy extends CharacterBody3D:
	var health: Node
	var lantern_on := true

	func _init() -> void:
		health = preload("res://src/player/player_health.gd").new()
		health.name = "Health"
		health.max_hp = 50000.0
		add_child(health)
		collision_layer = 2
		collision_mask = 0

	func knockback(_dir: Vector3, _force: float) -> void:
		pass


func before_each() -> void:
	fresh_state()
	nodes.clear()
	ended.clear()
	defeats.clear()
	said.clear()
	captions.clear()
	for k in ["arachnophobia", "timing_assist", "horror_intensity", "captions", "high_visibility_cues"]:
		_saved[k] = Settings.get_value(k)
	Settings.set_value("arachnophobia", false)
	Settings.set_value("timing_assist", false)
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("captions", true)
	Settings.set_value("high_visibility_cues", false)
	Base.reset_attack_tokens()
	Combat.invalidate_light_cache()
	_saved_area = Game.area
	_saved_player = Game.player
	_saved_area_id = Game.area_id
	_saved_companions = Game.companion_nodes
	Game.area = null
	Game.player = null
	Game.companion_nodes = {}
	EchoTrial.pending_trial = ""
	Events.trial_ended.connect(_on_ended)
	Events.boss_defeated.connect(_on_defeat)
	Events.say.connect(_on_say)
	Events.caption.connect(_on_caption)


func after_each() -> void:
	Events.trial_ended.disconnect(_on_ended)
	Events.boss_defeated.disconnect(_on_defeat)
	Events.say.disconnect(_on_say)
	Events.caption.disconnect(_on_caption)
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	for k in _saved:
		Settings.set_value(k, _saved[k])
	Game.area = _saved_area
	Game.player = _saved_player
	Game.area_id = _saved_area_id
	Game.companion_nodes = _saved_companions
	EchoTrial.pending_trial = ""
	GameState.buffs.erase("slow")
	Game._bosses.clear()        # a boss freed mid-fight in a test (no area change clears it here)
	Base.reset_attack_tokens()
	Combat.invalidate_light_cache()
	await wait_frames(3)


func _on_ended(id: String, won: bool) -> void:
	ended.append([id, won])


func _on_defeat(id: String) -> void:
	defeats.append(id)


func _on_say(speaker: String, text: String, _d: float) -> void:
	said.append([speaker, text])


func _on_caption(t: String) -> void:
	captions.append(t)


## A save that finished both chapters' fights (every trial is offered).
func completed_save() -> void:
	for f in ["chapter_one_complete", "weaver_defeated", "ward_restored", "ch2_accepted", "ch2_velour_defeated",
			"ch2_manor_restored", "ch2_crossing_cleared", "ch2_choir_defeated"]:
		GameState.set_flag(f, true)
	GameState.give_item("lantern", 1)
	settle()


## Lets the quest layers pay whatever those flags complete NOW (their own rewards, not the trial's), so the
## snapshots a test takes afterwards only see what the trial itself does.
func settle() -> void:
	for i in 6:
		GameState.quests.evaluate()
		GameState.chapter2.evaluate()
		GameState.optional_goals.evaluate()


func story_flags() -> Dictionary:
	var out := {}
	for f in STORY_FLAGS:
		out[f] = bool(GameState.get_flag(f))
	return out


## Flags that differ between `before` (a GameState.flags copy) and now.
func flag_diff(before: Dictionary) -> Array:
	var diff: Array = []
	for k in GameState.flags:
		if not before.has(k) or before[k] != GameState.flags[k]:
			diff.append(String(k))
	for k in before:
		if not GameState.flags.has(k):
			diff.append(String(k))
	return diff


func trial_area(id: String) -> Node3D:
	EchoTrial.pending_trial = id
	var a: Node3D = (load(TRIAL_SCENE) as PackedScene).instantiate()
	add_child(a)
	nodes.append(a)
	await wait_physics(2)
	return a


func dummy(parent: Node, pos: Vector3) -> Dummy:
	var d := Dummy.new()
	parent.add_child(d)
	d.global_position = pos
	d.add_to_group("player")
	nodes.append(d)
	return d


func tick(b: Node, seconds: float) -> void:
	var n := int(ceilf(seconds / DT))
	for i in n:
		b.call("tick", DT)


func tick_until(b: Node, s: String, max_t: float = 30.0) -> bool:
	var t := 0.0
	while String(b.get("state")) != s and t < max_t:
		b.call("tick", DT)
		t += DT
	return String(b.get("state")) == s


## Takes the trial's boss under manual control against a dummy Krystal standing inside the arena.
func control(a: Node3D, pos: Vector3) -> Node:
	var boss: Node = a.get("boss")
	boss.set_process(false)
	boss.set("target_override", dummy(a, pos))
	boss.set("intensity_override", 1)
	boss.set("fast_defeat", true)
	return boss


## Count Velour's trial fought down: phase C, relight a candle (the light staggers him), a finishing blow.
func win_velour(a: Node3D) -> void:
	var boss := control(a, Vector3(0, 0, 3))
	var d: Node = boss.get("target_override")
	boss.call("start_fight")
	tick_until(boss, "glide", 10.0)
	boss.call("jump_to_phase", 3)
	var c: Node = (a.get("arena") as Dictionary)["candles"][0]
	c.call("darken", null)
	c.call("light", d)
	tick(boss, 1.0)
	(boss.get("health") as Node).call("apply_damage", 99999.0, d, Vector3.FORWARD)
	await wait_frames(2)


## The Borrowed Choir's trial fought down: phase C, three kept-flame exposures (raise the flame's anchor, strike).
func win_choir(a: Node3D) -> void:
	var boss := control(a, Vector3(0, 0, -9))
	var anchors: Array = (a.get("arena") as Dictionary)["anchors"]
	var h: Node = boss.get("health")
	boss.set("phase", 3)
	h.call("set_hp", ChoirRules.phase_start_hp(3, float(h.get("max_hp"))))
	boss.call("start_fight")
	for k in 3:
		if not tick_until(boss, "c_open", 40.0):
			break
		var an: Node = anchors[int(boss.get("flame_anchor"))]
		an.call("lower")
		an.call("raise", null)
		h.call("apply_damage", 99999.0, boss.get("target_override"))
	await wait_frames(2)


func has_spider_word(t: String) -> String:
	var low := t.to_lower()
	for w in SPIDER_WORDS:
		if low.contains(w):
			return w
	return ""


## Every Label3D text under `root`.
func label_texts(root: Node) -> Array:
	var out: Array = []
	for l in root.find_children("*", "Label3D", true, false):
		out.append((l as Label3D).text)
	return out

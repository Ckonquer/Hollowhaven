extends "res://tests/test_case.gd"
## CH2-010 (QA bot S1): Game's zone poll recorded EVERY zone entered as a map-landmark discovery, so the surface
## waygate's small 4.5 m safe circle ("ch2_waygate") was "discovered" and paid +15 Wayfinding (a landmark kind).
## And (the report's design question, same code path): v1 saves carry no "discovered" list, so after the one-time
## legacy credit the Chapter One landmarks (the Haven, the Moonlit Ruin...) were paid again as first discoveries -
## a Continued Chapter-One-complete save reached Wayfinding rank 2 within a minute, although the legacy credit is
## kept below rank 2 on purpose.
## Fix: helper zones are marked on their area's zones entry (annexes.mark_helper_zone) and Game.is_landmark_zone()
## skips them for discovery; applying the legacy credit also records the Chapter One landmarks the save proves visited
## (data/mastery.gd LEGACY_LANDMARKS) as already seen - no xp - while new journeys still earn every discovery.

const Mastery := preload("res://src/core/mastery.gd")
const MasteryData := preload("res://data/mastery.gd")
const Layout := preload("res://data/world_layout.gd")
const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")
const Annexes := preload("res://src/world/surface/annexes.gd")

var _world: Node3D = null
var _probe: Node3D = null
var _saved: Dictionary = {}


func before_each() -> void:
	fresh_state()
	Mastery.init()
	_saved = {"area": Game.area, "player": Game.player, "mode": Game.mode, "area_id": Game.area_id,
		"zone_id": Game.zone_id, "in_safe_zone": Game.in_safe_zone}


func after_each() -> void:
	Game.area = _saved["area"]
	Game.player = _saved["player"]
	Game.mode = String(_saved["mode"])
	Game.area_id = String(_saved["area_id"])
	Game.zone_id = String(_saved["zone_id"])
	Game.in_safe_zone = bool(_saved["in_safe_zone"])
	if _probe != null and is_instance_valid(_probe):
		_probe.queue_free()
	_probe = null
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	await wait_frames(2)


func _surface() -> Node3D:
	if _world == null or not is_instance_valid(_world):
		_world = SurfaceWorld.new()
		add_child(_world)
		await wait_physics(3)
	return _world


## Runs Game's real zone poll (the 0.4 s step of Game._process) with Krystal (a stand-in) at `pos`.
func _poll_at(pos: Vector3) -> void:
	_probe.global_position = pos
	Game._process(0.5)


func _start_play(w: Node3D) -> void:
	_probe = Node3D.new()
	add_child(_probe)
	Game.area = w
	Game.player = _probe
	Game.mode = "playing"
	Game.area_id = "surface"
	Game.zone_id = ""


func test_the_waygate_safe_circle_is_no_landmark_discovery() -> void:
	var w: Node3D = await _surface()
	assert_false(Game.is_landmark_zone(w, Annexes.WAYGATE_ZONE), "the waygate's safe circle is a helper zone")
	for id in Layout.LANDMARKS:
		assert_true(Game.is_landmark_zone(w, String(id)), "legacy landmark %s still counts" % id)
	assert_false(Game.is_landmark_zone(w, ""), "no zone is no landmark")
	_start_play(w)
	var xp0 := Mastery.xp("wayfinding")
	var spawn: Transform3D = w.spawns[Annexes.WAYGATE_SPAWN]
	_poll_at(spawn.origin)
	assert_eq(Game.zone_id, Annexes.WAYGATE_ZONE, "the poll still reports the zone (music, hints, safety)")
	assert_true(Game.in_safe_zone, "and it is still a safe zone")
	assert_false(GameState.is_discovered("surface", Annexes.WAYGATE_ZONE), "but it is not recorded as a discovery")
	assert_false(GameState.discovered_in("surface").has(Annexes.WAYGATE_ZONE))
	assert_eq(Mastery.xp("wayfinding"), xp0, "and pays no Wayfinding xp")
	assert_false(Mastery.has_seen("wayfinding", "landmark:surface/" + Annexes.WAYGATE_ZONE))
	# A real landmark on the way still is a discovery (a new journey earns it).
	var rc: Vector2 = Layout.LANDMARKS["ruin"]["pos"]
	_poll_at(Vector3(rc.x, 1.0, rc.y))
	assert_eq(Game.zone_id, "ruin")
	assert_true(GameState.is_discovered("surface", "ruin"), "the Moonlit Ruin is discovered")
	assert_eq(Mastery.xp("wayfinding"), xp0 + int(MasteryData.XP["wayfinding"]["landmark"]["xp"]), "and pays its landmark xp")


## A copy of the real v1 Chapter-One-complete save (fixture 16) as the state: no mastery record, no discoveries.
func _v1_state(flags: Array, lore: int) -> void:
	var d := GameState.to_dict()
	d.erase("mastery")
	d.erase("discovered")
	var f: Dictionary = d["flags"]
	for k in flags:
		f[String(k)] = true
	var l: Array = []
	for i in lore:
		l.append("lore_v1_%d" % i)
	d["lore"] = l
	GameState.from_dict(JSON.parse_string(JSON.stringify(d)))


func test_a_v1_chapter_one_save_is_not_paid_again_for_its_woods() -> void:
	_v1_state(["read_ward_intro", "ruin_cleared", "mine_opened", "entered_below", "reached_silk_hollows",
		"weaver_defeated", "ward_restored", "chapter_one_complete"], 1)
	assert_false(Mastery.legacy_applied())
	Events.game_loaded.emit()
	assert_true(Mastery.legacy_applied())
	var credited := Mastery.xp("wayfinding")
	assert_eq(credited, 10 + 20 + 30, "the legacy credit itself is unchanged (lore + silk + chapter one)")
	for id in Layout.LANDMARKS:
		assert_true(Mastery.has_seen("wayfinding", "landmark:surface/" + String(id)), "%s recorded as already credited" % id)
		GameState.discover("surface", String(id))
		assert_true(GameState.is_discovered("surface", String(id)), "%s still recorded on the map" % id)
	assert_eq(Mastery.xp("wayfinding"), credited, "walking her old woods again pays nothing on top of the credit")
	assert_true(Mastery.rank("wayfinding") < 2, "so the credit stays below rank 2")
	# New Chapter Two places are real discoveries.
	GameState.discover("hallowmere_reach", "hr_commons")
	assert_eq(Mastery.xp("wayfinding"), credited + int(MasteryData.XP["wayfinding"]["landmark"]["xp"]), "the Reach pays")
	# Loading again changes nothing.
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	Events.game_loaded.emit()
	assert_eq(Mastery.xp("wayfinding"), credited + int(MasteryData.XP["wayfinding"]["landmark"]["xp"]))


func test_a_partial_v1_save_is_credited_only_for_what_it_proves() -> void:
	_v1_state(["read_ward_intro", "ruin_cleared"], 0)
	Events.game_loaded.emit()
	var credited := Mastery.xp("wayfinding")
	GameState.discover("surface", "haven")
	GameState.discover("surface", "ruin")
	assert_eq(Mastery.xp("wayfinding"), credited, "the Haven and the cleared ruin were visited: no second pay")
	GameState.discover("surface", "pond")
	assert_eq(Mastery.xp("wayfinding"), credited + int(MasteryData.XP["wayfinding"]["landmark"]["xp"]), "an unproven place still pays")


func test_a_new_journey_still_earns_every_first_discovery() -> void:
	Events.area_loaded.emit("surface")
	assert_true(Mastery.legacy_applied(), "empty credit recorded")
	GameState.discover("surface", "haven")
	assert_eq(Mastery.xp("wayfinding"), int(MasteryData.XP["wayfinding"]["landmark"]["xp"]), "the Haven pays for a new journey")


func test_legacy_landmarks_cover_the_chapter_one_woods() -> void:
	var covered: Dictionary = {}
	for e in MasteryData.LEGACY_LANDMARKS:
		var lm := String(e["landmark"])
		assert_true((e["flags"] as Array).has("chapter_one_complete"), lm + ": chapter_one_complete proves it")
		covered[lm] = true
	for id in Layout.LANDMARKS:
		assert_true(covered.has("surface/" + String(id)), "Chapter One landmark %s is listed" % id)
	assert_eq(covered.size(), Layout.LANDMARKS.size(), "nothing else (Chapter One 1.x extras stay discoverable)")

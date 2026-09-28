extends Node3D
## Weaver's Crossing arena (MP §10 room 10, §13.2; spec §7.4). Owns the encounter state around the broad
## railed service bridge built by rooms_deep.gd: five authored ceiling anchors (Marker3D), three
## line-braziers (src/enemies/boss_brazier.gd) under the first three anchors, the thick threads that
## close the way onward, the Matron's deeper route and its old service gate, and temporary threads.
##
## Boss hook: when Krystal steps onto the bridge and ch2_crossing_cleared is false, enemy id
## "crossing_matron" is spawned through EnemyFactory with boss_params() (guarded: a build without that
## enemy script never crashes). Events.boss_defeated("crossing_matron") (or ch2_crossing_cleared being set
## by the boss / a spawner) -> clear_encounter(): grants the
## content bundle rw_ch2_crossing ONCE (it sets ch2_crossing_cleared; the Thread Veil is the step reward
## paid by the quest layer), burns the threads off the exit, and the service gate shuts the Matron's route.
## Without the boss script (content still completable): the three line-braziers burn the Matron's threads
## away and clear the crossing. debug_mark_cleared() (debug builds / tests) clears it directly.
##
## API for the crossing_matron boss module (all positions global):
##   arena_center() -> Vector3, arena_radius() -> float, deck_y() -> float, bridge_rect() -> Rect2 (x, z)
##   anchor_points() -> Array[Vector3], anchor_markers() -> Array[Marker3D]
##   braziers() -> Array[Node] (boss_brazier.gd: signal lit, is_lit(), light(); metas "anchor_index" / "anchor"),
##       brazier_for_anchor(i) -> Node
##   line_of_brazier(brazier) -> int, lit_lines() -> Array[int]      signal line_lit(line)
##   landing_points() -> Array[Vector3] (valid pounce landings on the deck, clear of braziers and rails)
##   is_on_bridge(pos) -> bool, clamp_to_bridge(pos) -> Vector3, crack_point() -> Vector3
##   spawn_thread(a, b, lifetime := 10.0, line := -1) -> Node (a temporary cuttable veil across the deck)
##   threads_on_line(line) -> Array, clear_threads()
##   boss_params() -> Dictionary (passed to EnemyFactory.spawn), start_encounter(), is_active(), is_cleared()
##   signals encounter_started, encounter_cleared, line_lit(line)

signal encounter_started
signal encounter_cleared
signal line_lit(line: int)

const Layout := preload("res://data/works_layout_deep.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const ThreadScript := preload("res://src/world/works/deep/deep_thread.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")

const BOSS_ID := "crossing_matron"
const REWARD_ID := "rw_ch2_crossing"
const CLEAR_FLAG := "ch2_crossing_cleared"
const BRAZIER_SCRIPT := "res://src/enemies/boss_brazier.gd"
const BRAZIER_CLEARANCE := 1.4

var area: Node3D = null
var controller: Node = null
var boss: Node = null
var active: bool = false
var fallback: bool = false
var cleared: bool = false
var player_override: Node3D = null
var save_on_clear: bool = true

var _anchors: Array = []
var _braziers: Array = []
var _lit_lines: Array = []
var _temp_threads: Array = []
var _thread_seq: int = 0
var exit_veil: Node3D = null
var route_veil: Node3D = null
var route_gate: Node3D = null
var _route_body: StaticBody3D = null


func setup(p: Dictionary) -> void:
	area = p.get("area", area)
	controller = p.get("controller", controller)


func _ready() -> void:
	add_to_group("hw_arena")
	set_meta("arena_id", "crossing")
	cleared = bool(GameState.get_flag(CLEAR_FLAG))
	_build_anchors()
	_build_braziers()
	_build_route()
	var exit := _make_thread("hw_crossing_exit_veil", Layout.CROSSING["exit_veil"], PI * 0.5, 3.2, 3.4, true)
	exit_veil = exit
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.player_died.connect(_on_player_died)
	Events.flag_set.connect(_on_flag)
	if cleared:
		# ch2_crossing_cleared was set while this arena wasn't loaded (e.g. by the boss module elsewhere):
		# commit the content bundle's ledger entry now, still exactly once
		if not GameState.has_reward(REWARD_ID):
			_grant_bundle()
		_apply_cleared(false)


## The boss module (or a spawner's quest_flag_on_clear) may set ch2_crossing_cleared itself: commit the
## crossing the same way (the content bundle stays once-only).
func _on_flag(flag: String, v: Variant) -> void:
	if flag == CLEAR_FLAG and v is bool and v and not cleared:
		clear_encounter()


# --- Queries (boss API) ---------------------------------------------------------------------------------

func arena_center() -> Vector3:
	return Layout.CROSSING["center"]


func arena_radius() -> float:
	return float(Layout.CROSSING["radius"])


func deck_y() -> float:
	return float(Layout.CROSSING["deck_y"])


func bridge_rect() -> Rect2:
	return Layout.CROSSING["bridge"]


func crack_point() -> Vector3:
	return Layout.CROSSING["crack"]


func anchor_points() -> Array:
	var out: Array = []
	for m in _anchors:
		out.append((m as Node3D).global_position if (m as Node3D).is_inside_tree() else (m as Node3D).position)
	return out


func anchor_markers() -> Array:
	return _anchors.duplicate()


func braziers() -> Array:
	return _braziers.duplicate()


func brazier_for_anchor(i: int) -> Node:
	return _braziers[i] if i >= 0 and i < _braziers.size() else null


func line_of_brazier(b: Node) -> int:
	return _braziers.find(b)


func lit_lines() -> Array:
	return _lit_lines.duplicate()


func is_active() -> bool:
	return active


func is_cleared() -> bool:
	return cleared


func is_on_bridge(pos: Vector3) -> bool:
	var r: Rect2 = Layout.CROSSING["bridge"]
	return r.has_point(Vector2(pos.x, pos.z)) and absf(pos.y - deck_y()) < 2.5


## Nearest point on the walkable deck (inside the rails).
func clamp_to_bridge(pos: Vector3) -> Vector3:
	var r: Rect2 = Layout.CROSSING["bridge"]
	var rail: float = float(Layout.CROSSING["rail"]) - 0.6
	return Vector3(clampf(pos.x, r.position.x + 0.8, r.end.x - 0.8), deck_y(), clampf(pos.z, -rail, rail))


## Valid pounce landing points: on the deck, inside the rails, clear of the braziers.
func landing_points() -> Array:
	var out: Array = []
	var r: Rect2 = Layout.CROSSING["bridge"]
	var rail: float = float(Layout.CROSSING["rail"]) - 1.0
	var x := r.position.x + 2.0
	while x <= r.end.x - 2.0:
		for z in [-rail, 0.0, rail]:
			var p := Vector3(x, deck_y(), float(z))
			var ok := true
			for b in Layout.CROSSING["braziers"]:
				if Vector2(p.x - (b as Vector3).x, p.z - (b as Vector3).z).length() < BRAZIER_CLEARANCE + 0.6:
					ok = false
			if ok:
				out.append(p)
		x += 4.0
	return out


func boss_params() -> Dictionary:
	return {"arena_center": arena_center(), "arena_radius": arena_radius(), "anchors": anchor_points(),
		"braziers": braziers(), "crack": crack_point(), "arena": self, "bridge": bridge_rect(), "deck_y": deck_y(),
		"landing_points": landing_points(), "alert": true}


## True when EnemyFactory knows crossing_matron AND its script exists and compiles (never spawns a broken one).
static func boss_available() -> bool:
	return Factory.can_spawn(BOSS_ID)


# --- Encounter --------------------------------------------------------------------------------------------

## Called by the controller ~10x per second with the player.
func check(p: Node3D) -> void:
	if cleared or p == null:
		return
	var pos := p.global_position
	if not active and is_on_bridge(pos) and pos.x > float(Layout.CROSSING["trigger_x"]):
		start_encounter()
	elif active and pos.x < 68.0 and absf(pos.y - deck_y()) < 3.0:
		stop_encounter("left")


func start_encounter() -> void:
	if cleared or active:
		return
	active = true
	Events.horror_event.emit("authored:hw_crossing", {})
	Art.set_fight(area, BOSS_ID, true)
	if boss != null and is_instance_valid(boss):
		for m in ["start_fight", "begin_fight", "start", "activate"]:
			if boss.has_method(m):
				boss.call(m)
				break
	elif boss_available():
		fallback = false
		var parent: Node = area if area != null else get_parent()
		var anchors := anchor_points()
		var at: Vector3 = anchors[0] if not anchors.is_empty() else arena_center() + Vector3.UP * 10.0
		boss = Factory.spawn(BOSS_ID, parent, Transform3D(Basis.IDENTITY, at), boss_params())
		if boss == null:
			_enter_fallback()
	else:
		_enter_fallback()
	encounter_started.emit()


func _enter_fallback() -> void:
	fallback = true
	var a := Art.arachno()
	Art.caption("[pale roots stir over the bridge, but the Hollow Mother does not come]" if a else "[threads tremble overhead, but the Matron does not come]")
	Events.hint.emit("hw_crossing_braziers", "Light the three line-braziers with your lantern to burn the %s away." % ("pale veils" if a else "threads"))
	_check_fallback_clear()


func stop_encounter(_reason: String = "") -> void:
	if not active:
		return
	active = false
	Art.set_fight(area, BOSS_ID, false)


func _on_player_died() -> void:
	if active:
		active = false
		Art.set_fight(area, BOSS_ID, false)
		Art.director_suppress(area, 30.0)
		clear_threads()


func _on_boss_defeated(boss_id: String) -> void:
	if boss_id != BOSS_ID:
		return
	if area != null and Game.area != null and is_instance_valid(Game.area) and Game.area != area:
		return
	clear_encounter()


## Commits the crossing: reward bundle once (sets ch2_crossing_cleared), route onward open, the Matron's
## deeper route shut. Idempotent.
func clear_encounter() -> void:
	var was := cleared
	var was_active := active
	cleared = true              # first: the flag_set echo of the grant below must not re-enter
	active = false
	fallback = false
	_grant_bundle()
	GameState.set_flag(CLEAR_FLAG, true)      # (already set by the bundle; kept explicit)
	if was_active:
		Art.set_fight(area, BOSS_ID, false)
	if not was:
		_apply_cleared(true)
		Art.director_suppress(area, 240.0)
		encounter_cleared.emit()
		if save_on_clear and Game.player != null and is_instance_valid(Game.player) and (area == null or Game.area == area):
			SaveSystem.save_game()


## The content bundle rw_ch2_crossing (data/sources.gd, by "content", this module), once ever.
static func _grant_bundle() -> bool:
	var bundle: Dictionary = ItemDB.reward_bundle(REWARD_ID)
	var items: Dictionary = bundle.get("items", {}) if bundle.get("items", {}) is Dictionary else {}
	var flags: Array = bundle.get("flags", [CLEAR_FLAG]) if bundle.get("flags", []) is Array else [CLEAR_FLAG]
	if not flags.has(CLEAR_FLAG):
		flags = flags.duplicate()
		flags.append(CLEAR_FLAG)
	return GameState.grant_once(REWARD_ID, items, flags)


## Debug builds / tests: mark the encounter cleared (never reachable in release).
func debug_mark_cleared() -> bool:
	if not Debug.is_cheat_allowed():
		return false
	clear_encounter()
	return true


func _apply_cleared(animate: bool) -> void:
	if exit_veil != null and is_instance_valid(exit_veil):
		if animate:
			exit_veil.call("burn", true)
		else:
			exit_veil.call("dissolve")
	if route_veil != null and is_instance_valid(route_veil):
		route_veil.call("dissolve")
	clear_threads()
	for b in _braziers:
		if b != null and is_instance_valid(b) and b.has_method("light") and not bool(b.call("is_lit")):
			b.call("light")
	_shut_route_gate(animate)
	if animate:
		var a := Art.arachno()
		Art.caption("[an old service gate grinds shut over the deeper route]")
		Art.say("The %s retreats behind the old service gate. The way ahead is clear." % ("Hollow Mother" if a else "Matron"), 5.0)


# --- Braziers & threads -----------------------------------------------------------------------------------

func _on_brazier_lit(line: int) -> void:
	if not _lit_lines.has(line):
		_lit_lines.append(line)
	for t in threads_on_line(line):
		(t as Node).call("burn", true)
	line_lit.emit(line)
	_check_fallback_clear()


func _check_fallback_clear() -> void:
	if not fallback or cleared or not active:
		return
	for b in _braziers:
		if b == null or not is_instance_valid(b) or not bool(b.call("is_lit")):
			return
	clear_encounter()


## A temporary veil of threads thrown across the deck from a to b (floor points). It expires after
## `lifetime` seconds, can be cut (it doesn't regrow: lifetime rules) and is burned by its line's brazier.
func spawn_thread(a: Vector3, b: Vector3, lifetime: float = 10.0, line: int = -1) -> Node:
	_prune_threads()
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var w := maxf(d.length(), 0.6)
	_thread_seq += 1
	var mid := (a + b) * 0.5
	var t := _make_thread("hw_crossing_thread_%d" % _thread_seq, Vector3(mid.x, deck_y(), mid.z), atan2(-d.z, d.x), w, 2.6, false, lifetime, line)
	_temp_threads.append(t)
	return t


func threads_on_line(line: int) -> Array:
	var out: Array = []
	for t in _temp_threads:
		if t != null and is_instance_valid(t) and int(t.get("line")) == line and bool(t.call("is_blocking")):
			out.append(t)
	return out


## Frees fight threads that are finished (expired / burned): a long fight never piles up hidden nodes.
func _prune_threads() -> void:
	var keep: Array = []
	for t in _temp_threads:
		if t == null or not is_instance_valid(t):
			continue
		var s := String((t as Node).get("state"))
		if s == "expired" or s == "burned" or s == "gone":
			(t as Node).queue_free()
		else:
			keep.append(t)
	_temp_threads = keep


func clear_threads() -> void:
	for t in _temp_threads:
		if t != null and is_instance_valid(t):
			(t as Node).queue_free()
	_temp_threads.clear()


func _make_thread(id: String, pos: Vector3, yaw: float, width: float, height: float, thick: bool, lifetime: float = -1.0, line: int = -1) -> Node3D:
	var t: Node3D = ThreadScript.new()
	t.setup({"id": id, "width": width, "height": height, "thick": thick, "lifetime": lifetime, "line": line,
		"dissolve_flag": CLEAR_FLAG if thick else ""})
	t.name = id
	add_child(t)
	t.position = pos            # the arena sits at the area origin: local = area space
	t.rotation.y = yaw
	if controller != null and is_instance_valid(controller):
		t.player_override = controller.get("player_override")
	return t


# --- Building ---------------------------------------------------------------------------------------------

func _build_anchors() -> void:
	var holder := Node3D.new()
	holder.name = "Anchors"
	add_child(holder)
	var i := 0
	for p in Layout.CROSSING["anchors"]:
		var m := Marker3D.new()
		m.name = "Anchor_%d" % i
		m.add_to_group("hw_crossing_anchor")
		m.set_meta("index", i)
		holder.add_child(m)
		m.position = p
		_anchors.append(m)
		i += 1


func _build_braziers() -> void:
	if not ResourceLoader.exists(BRAZIER_SCRIPT):
		return
	var script: Script = load(BRAZIER_SCRIPT)
	if script == null:
		return
	var i := 0
	for p in Layout.CROSSING["braziers"]:
		var b: Node3D = script.new()
		b.setup({"id": "hw_crossing_brazier_%d" % i, "lit": cleared, "light_radius": 7.0})
		b.name = "LineBrazier_%d" % i
		b.set_meta("anchor_index", i)            # the ceiling anchor this line-brazier exposes (boss module)
		b.set_meta("anchor", Layout.CROSSING["anchors"][i])
		add_child(b)
		b.position = p
		if b.has_signal("lit"):
			b.connect("lit", _on_brazier_lit.bind(i))
		_braziers.append(b)
		i += 1


## The Matron's deeper route: thick threads in its mouth, an old service gate raised above them. When the
## crossing clears, the threads go with her and the gate drops shut for good.
func _build_route() -> void:
	var at: Vector3 = Layout.CROSSING["matron_gate"]
	route_veil = _make_thread("hw_crossing_route_veil", at + Vector3(0, 0, 0.05), 0.0, 3.0, 3.0, true)
	route_gate = Node3D.new()
	route_gate.name = "ServiceGate"
	add_child(route_gate)
	route_gate.position = at + Vector3(0, 0, -0.3)
	var iron := Mat.outlined(Mat.toon(Color("4a4048"), {"rim": 0.45}), 0.016)
	var bars := Node3D.new()
	bars.name = "Bars"
	route_gate.add_child(bars)
	for i in 8:
		Kit.add(bars, Kit.cylinder(0.04, 0.04, 3.0, iron, 6), Vector3(-1.4 + float(i) * 0.4, 1.5, 0))
	for y in [0.4, 1.5, 2.6]:
		Kit.add(bars, Kit.box(Vector3(3.0, 0.1, 0.1), iron), Vector3(0, float(y), 0))
	_route_body = StaticBody3D.new()
	_route_body.name = "GateBody"
	_route_body.collision_layer = 1
	_route_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.0, 3.0, 0.3)
	cs.shape = sh
	cs.position = Vector3(0, 1.5, 0)
	_route_body.add_child(cs)
	route_gate.add_child(_route_body)
	bars.position.y = 2.7          # raised into the lintel while the Matron still uses the route
	Art.set_collision(_route_body, false)


func _shut_route_gate(animate: bool) -> void:
	if route_gate == null:
		return
	var bars: Node3D = route_gate.get_node("Bars")
	Art.set_collision(_route_body, true)
	if animate and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(bars, "position:y", 0.0, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		Art.sfx3d("gate_unlock", route_gate.global_position + Vector3.UP * 1.5, -2.0)
		Events.camera_shake.emit(0.25, 0.3)
	else:
		bars.position.y = 0.0


func route_gate_shut() -> bool:
	if route_gate == null:
		return false
	var bars: Node3D = route_gate.get_node("Bars")
	return is_equal_approx(bars.position.y, 0.0) or cleared

extends Node3D
## Choir Vault arena (MP §10 room 14, §13.3; spec §7.4). The large readable circular vault built by
## rooms_deep.gd gets: three FIXED lantern anchors (lantern_anchor.gd), two FIXED resonators
## (resonator.gd) carrying the bell symbols taught on the Bellmaker's Floor, a safe walkable perimeter
## ring (radius >= perimeter_radius()), and the exit: an old bell-lift behind a portcullis in the south
## alcove (spawn vault_exit) that rises to the Reach's Sunken Bellhouse once ch2_choir_defeated is set.
##
## Boss hook: when Krystal walks into the vault and ch2_choir_defeated is false, enemy id "borrowed_choir"
## is spawned through EnemyFactory with boss_params() (guarded: a missing script never crashes).
## Events.boss_defeated("borrowed_choir") -> set ch2_choir_defeated FIRST (the quest layer then pays its
## rewards), then the exit opens, the vault becomes a safe zone, the respawn moves to vault_exit and the
## game saves - before any ending presentation (MP §13.3).
## Without the boss script (content still completable): raising the lantern at all three anchors and
## waking both resonators banishes the empty echo. debug_mark_cleared() (debug builds / tests).
##
## API for the borrowed_choir boss module (positions global):
##   arena_center() -> Vector3, arena_radius() -> float, perimeter_radius() -> float, floor_y() -> float
##   anchor_nodes() -> Array (lantern_anchor.gd: signal raised(id), raise(), is_raised(), lower(),
##       reveal_point(), reveal_radius), anchor_points() -> Array[Vector3]
##   resonator_nodes() -> Array (resonator.gd: signal activated(id) / struck(id, symbol, ok), set_sequence(ids),
##       reset(), is_active(), symbol_ids(), window_seconds()), symbols() -> Array[{id, name, caption}]
##   perimeter_points(n := 12) -> Array[Vector3], is_inside(pos), is_on_perimeter(pos)
##   boss_params() -> Dictionary, start_encounter(), is_active(), is_cleared(), exit_open() -> bool
##   signals encounter_started, encounter_cleared

signal encounter_started
signal encounter_cleared

const Layout := preload("res://data/works_layout_deep.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const AnchorScript := preload("res://src/world/works/deep/lantern_anchor.gd")
const ResonatorScript := preload("res://src/world/works/deep/resonator.gd")
const LiftScript := preload("res://src/world/works/deep/deep_lift.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")

const BOSS_ID := "borrowed_choir"
const CLEAR_FLAG := "ch2_choir_defeated"
const RESONATOR_IDS := ["hw_resonator_west", "hw_resonator_east"]

var area: Node3D = null
var controller: Node = null
var boss: Node = null
var active: bool = false
var fallback: bool = false
var cleared: bool = false
var save_on_clear: bool = true

var _anchors: Array = []
var _resonators: Array = []
var _symbols: Array = []
var _raised_ids: Dictionary = {}
var exit_gate: Node3D = null
var exit_lift: Node3D = null
var _gate_body: StaticBody3D = null
var _victory_light: OmniLight3D = null


func setup(p: Dictionary) -> void:
	area = p.get("area", area)
	controller = p.get("controller", controller)


func _ready() -> void:
	add_to_group("hw_arena")
	set_meta("arena_id", "choir")
	cleared = bool(GameState.get_flag(CLEAR_FLAG))
	_symbols = Layout.bell_symbols()
	_build_anchors()
	_build_resonators()
	_build_exit()
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.player_died.connect(_on_player_died)
	Events.flag_set.connect(_on_flag)
	_apply_exit(cleared, false)


# --- Queries (boss API) -------------------------------------------------------------------------------

func arena_center() -> Vector3:
	return Layout.VAULT["center"]


func arena_radius() -> float:
	return float(Layout.VAULT["radius"])


func perimeter_radius() -> float:
	return float(Layout.VAULT["perimeter"])


func floor_y() -> float:
	return (Layout.VAULT["center"] as Vector3).y


func anchor_nodes() -> Array:
	return _anchors.duplicate()


func anchor_points() -> Array:
	var out: Array = []
	for a in _anchors:
		out.append((a as Node3D).global_position if (a as Node3D).is_inside_tree() else (a as Node3D).position)
	return out


func resonator_nodes() -> Array:
	return _resonators.duplicate()


func symbols() -> Array:
	return _symbols.duplicate(true)


func is_inside(pos: Vector3) -> bool:
	var c := arena_center()
	return Vector2(pos.x - c.x, pos.z - c.z).length() <= arena_radius() and absf(pos.y - c.y) < 4.0


func is_on_perimeter(pos: Vector3) -> bool:
	var c := arena_center()
	var d := Vector2(pos.x - c.x, pos.z - c.z).length()
	return d >= perimeter_radius() and d <= arena_radius() - 0.3 and absf(pos.y - c.y) < 4.0


## Evenly spaced points on the safe perimeter walk (mid-ring), skipping the two doorways.
func perimeter_points(n: int = 12) -> Array:
	var out: Array = []
	var c := arena_center()
	var r := (perimeter_radius() + arena_radius()) * 0.5
	for i in n:
		var ang := TAU * float(i) / float(n)
		var deg := rad_to_deg(ang)
		if _near_door(deg):
			continue
		out.append(Vector3(c.x + cos(ang) * r, c.y, c.z + sin(ang) * r))
	return out


static func _near_door(deg: float) -> bool:
	for door in [float(Layout.VAULT["entry_angle"]), float(Layout.VAULT["exit_angle"])]:
		var dd := absf(wrapf(deg - door, -180.0, 180.0))
		if dd < float(Layout.VAULT["door_half_angle"]) + 4.0:
			return true
	return false


func is_active() -> bool:
	return active


func is_cleared() -> bool:
	return cleared


func exit_open() -> bool:
	return cleared and exit_lift != null and bool(exit_lift.call("usable"))


func boss_params() -> Dictionary:
	return {"arena_center": arena_center(), "arena_radius": arena_radius(), "perimeter_radius": perimeter_radius(),
		"anchors": anchor_points(), "anchor_nodes": anchor_nodes(), "resonators": resonator_nodes(), "symbols": symbols(),
		"arena": self, "alert": true}


## True when EnemyFactory knows borrowed_choir AND its script exists and compiles.
static func boss_available() -> bool:
	return Factory.can_spawn(BOSS_ID)


# --- Encounter ------------------------------------------------------------------------------------------

func check(p: Node3D) -> void:
	if cleared or p == null:
		return
	var c := arena_center()
	var pos := p.global_position
	var d := Vector2(pos.x - c.x, pos.z - c.z).length()
	if not active and d < float(Layout.VAULT["trigger_radius"]) and absf(pos.y - c.y) < 3.0:
		start_encounter()
	elif active and (d > arena_radius() + 2.0 or pos.y > c.y + 3.0):
		stop_encounter("left")


func start_encounter() -> void:
	if cleared or active:
		return
	active = true
	_raised_ids.clear()
	Events.horror_event.emit("authored:hw_choir", {})
	Art.set_fight(area, BOSS_ID, true)
	if boss != null and is_instance_valid(boss):
		for m in ["start_fight", "begin_fight", "start", "activate"]:
			if boss.has_method(m):
				boss.call(m)
				break
	elif boss_available():
		fallback = false
		var parent: Node = area if area != null else get_parent()
		boss = Factory.spawn(BOSS_ID, parent, Transform3D(Basis.IDENTITY, arena_center()), boss_params())
		if boss == null:
			_enter_fallback()
	else:
		_enter_fallback()
	encounter_started.emit()


func _enter_fallback() -> void:
	fallback = true
	Art.caption("[borrowed voices echo around the empty centre]")
	Events.hint.emit("hw_choir_anchors", "Raise your lantern at the three anchors and wake both resonators.")
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


func _on_boss_defeated(boss_id: String) -> void:
	if boss_id != BOSS_ID:
		return
	if area != null and Game.area != null and is_instance_valid(Game.area) and Game.area != area:
		return
	clear_encounter()


func _on_flag(flag: String, v: Variant) -> void:
	if flag == CLEAR_FLAG and v is bool and v and not cleared:
		clear_encounter()       # the boss module (or a load) set the flag itself: open the exit the same way


## Commits the victory: ch2_choir_defeated first, then the exit opens and the game saves. Idempotent.
func clear_encounter() -> void:
	var was := cleared
	var was_active := active
	cleared = true
	active = false
	fallback = false
	GameState.set_flag(CLEAR_FLAG, true)
	if was_active:
		Art.set_fight(area, BOSS_ID, false)
	if was:
		return
	_apply_exit(true, true)
	Art.director_suppress(area, 240.0)
	encounter_cleared.emit()
	if area != null and Game.area == area:
		Game.set_respawn(Layout.AREA_ID, "vault_exit")     # a reliable way out: wake beside the exit lift
	if save_on_clear and Game.player != null and is_instance_valid(Game.player) and (area == null or Game.area == area):
		SaveSystem.save_game()


func debug_mark_cleared() -> bool:
	if not Debug.is_cheat_allowed():
		return false
	clear_encounter()
	return true


func _on_anchor_raised(anchor_id: String) -> void:
	if active:
		_raised_ids[anchor_id] = true
	_check_fallback_clear()


func _on_resonator_activated(_id: String) -> void:
	_check_fallback_clear()


func _check_fallback_clear() -> void:
	if not fallback or cleared or not active:
		return
	if _raised_ids.size() < _anchors.size():
		return
	for r in _resonators:
		if not bool((r as Node).call("is_active")):
			return
	clear_encounter()


# --- Building -------------------------------------------------------------------------------------------

func _build_anchors() -> void:
	var i := 0
	var c: Vector3 = Layout.VAULT["center"]
	for p in Layout.VAULT["anchors"]:
		var a: Node3D = AnchorScript.new()
		a.setup({"id": "hw_vault_anchor_%d" % i, "reveal_radius": 9.0})
		a.name = "LanternAnchor_%d" % i
		add_child(a)
		a.position = p
		var to_c := Vector3(c.x - (p as Vector3).x, 0.0, c.z - (p as Vector3).z)
		a.rotation.y = atan2(to_c.x, to_c.z)      # hook arm (local +z) points at the empty centre
		a.connect("raised", _on_anchor_raised)
		_anchors.append(a)
		i += 1


func _build_resonators() -> void:
	var c: Vector3 = Layout.VAULT["center"]
	for i in Layout.VAULT["resonators"].size():
		var p: Vector3 = Layout.VAULT["resonators"][i]
		var r: Node3D = ResonatorScript.new()
		r.setup({"id": RESONATOR_IDS[i], "symbols": _symbols})
		r.name = "Resonator_%d" % i
		add_child(r)
		r.position = p
		var to_c := Vector3(c.x - p.x, 0.0, c.z - p.z)
		r.rotation.y = atan2(to_c.x, to_c.z)      # plates (local +z) face the centre
		r.connect("activated", _on_resonator_activated)
		_resonators.append(r)


func _build_exit() -> void:
	var gp: Vector3 = Layout.VAULT["exit_gate"]
	exit_gate = Node3D.new()
	exit_gate.name = "ExitGate"
	add_child(exit_gate)
	exit_gate.position = gp
	var iron := Mat.outlined(Mat.toon(Color("4a4048"), {"rim": 0.45}), 0.016)
	var bars := Node3D.new()
	bars.name = "Bars"
	exit_gate.add_child(bars)
	for i in 10:
		Kit.add(bars, Kit.cylinder(0.045, 0.045, 3.6, iron, 6), Vector3(-1.8 + float(i) * 0.4, 1.8, 0))
	for y in [0.5, 1.8, 3.1]:
		Kit.add(bars, Kit.box(Vector3(3.8, 0.1, 0.1), iron), Vector3(0, float(y), 0))
	_gate_body = StaticBody3D.new()
	_gate_body.name = "GateBody"
	_gate_body.collision_layer = 1
	_gate_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.0, 3.6, 0.3)
	cs.shape = sh
	cs.position = Vector3(0, 1.8, 0)
	_gate_body.add_child(cs)
	exit_gate.add_child(_gate_body)
	exit_lift = LiftScript.new()
	exit_lift.setup({"id": "hw_vault_lift", "kind": "bell", "requires_flag": CLEAR_FLAG,
		"text": "Ride the bell-lift up to the Sunken Bellhouse", "locked_text": "Not while the voices still sing",
		"sign": "BELLHOUSE", "handler": Callable(self, "_on_exit_lift")})
	exit_lift.name = "ExitLift"
	add_child(exit_lift)
	exit_lift.position = Layout.VAULT["exit_lift"]
	exit_lift.rotation.y = 0.0         # the cage mouth (local -z) faces north, back into the vault
	_victory_light = OmniLight3D.new()
	_victory_light.name = "VictoryLight"
	_victory_light.light_color = Palette.WARD_GLOW
	_victory_light.omni_range = 16.0
	_victory_light.light_energy = 0.0
	_victory_light.shadow_enabled = false
	add_child(_victory_light)
	_victory_light.position = arena_center() + Vector3(0, 8.0, 0)


func _apply_exit(open: bool, animate: bool) -> void:
	if exit_gate == null:
		return
	var bars: Node3D = exit_gate.get_node("Bars")
	Art.set_collision(_gate_body, not open)
	if open:
		_make_safe()
		if animate and is_inside_tree():
			var tw := create_tween().set_parallel(true)
			tw.tween_property(bars, "position:y", 3.4, 2.0).set_trans(Tween.TRANS_SINE)
			tw.tween_property(_victory_light, "light_energy", 1.2, 4.0).set_trans(Tween.TRANS_SINE)
			Art.sfx3d("gate_unlock", exit_gate.global_position + Vector3.UP * 1.5, -2.0)
			Art.caption("[the stolen echoes drift upward as soft chimes; the old bell-lift rattles free]")
		else:
			bars.position.y = 3.4
			_victory_light.light_energy = 1.2
	else:
		bars.position.y = 0.0
		_victory_light.light_energy = 0.0
	for a in _anchors:
		(a as Node3D).set("enabled", true)


## After the victory the quiet vault and its exit alcove are safe (saving, no director, calm companions).
func _make_safe() -> void:
	if area == null:
		return
	Art.add_safe(area, arena_center(), arena_radius() + 1.0, "hw_vault")
	Art.add_safe(area, Layout.SPAWNS["vault_exit"]["pos"], 3.5, "hw_vault")


func _on_exit_lift(_lift: Node) -> void:
	if not cleared:
		return
	var target: Dictionary = Layout.VAULT_EXIT_TARGET
	if controller != null and is_instance_valid(controller) and controller.has_method("travel_area"):
		controller.call("travel_area", String(target["area"]), String(target["spawn"]), "[the bell-lift climbs toward the night air]")

extends "res://tests/unit/test_core_base.gd"
## B11 map (src/ui/panels/map_panel.gd + src/ui/widgets/map_view.gd), per area: the legacy woods map is
## unchanged (geometry pinned), the Chapter Two waygate pin appears only after acceptance, the Reach map shows
## discovered districts only (+ arches, the waygate home) with objective markers for every lamp, interiors list
## the rooms found, the Below / trials show a message, the outdoor toggle, "way there" marks for goals in
## another area, numeric layout checks (no overlapping stickers / names / pins) and windows that fit the canvas.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const MapPanel := preload("res://src/ui/panels/map_panel.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")
const Layout := preload("res://data/world_layout.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const CANVAS := Vector2(1920, 1080)
const REACH := "hallowmere_reach"
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const Mastery := preload("res://src/core/mastery.gd")
const MasteryData := preload("res://data/mastery.gd")

var ui: CanvasLayer
var _mode_before := ""
var _area_before := ""
var _zone_before := ""
var _views: Array = []


func setup() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	GameState.active = true
	Settings.set_value("arachnophobia", false)
	_mode_before = Game.mode
	_area_before = Game.area_id
	_zone_before = Game.zone_id
	Game.mode = "playing"
	Game.area_id = "surface"
	Game.zone_id = ""
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func teardown() -> void:
	for v in _views:
		if is_instance_valid(v):
			v.queue_free()
	_views = []
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	await wait_frames(2)
	get_tree().paused = false
	Game.mode = _mode_before
	Game.area_id = _area_before
	Game.zone_id = _zone_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))


func _accept(extra_flags: Array = []) -> void:
	GameState.set_flag("ward_restored")
	GameState.set_flag("chapter_one_complete")
	GameState.quests.from_dict({"index": QuestsData.STEPS.size() - 1})
	GameState.set_flag("ch2_accepted")
	for f in extra_flags:
		GameState.set_flag(String(f))
	GameState.chapter2.evaluate()


const TO_LAMPS := ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
	"ch2_found_quarry_lamp", "ch2_found_manor_lamp"]


func _open_map(args: Dictionary = {}) -> Control:
	ui.open("map", args)
	await wait_frames(2)
	return ui.panels.get("map")


func _texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		if not c.is_queued_for_deletion():
			_texts(c, out)
	return out


func _has_text(n: Node, needle: String) -> bool:
	for t in _texts(n):
		if String(t).contains(needle):
			return true
	return false


func _standalone(area: String, sz: Vector2) -> Control:
	var v: Control = MapView.new()
	v.map_area = area
	add_child(v)
	v.size = sz
	_views.append(v)
	return v


# --- static helpers --------------------------------------------------------------------------------------

func test_map_kinds_and_place_names() -> void:
	assert_eq(MapView.map_kind("surface"), "surface")
	assert_eq(MapView.map_kind(REACH), "reach")
	for a in ["moonveil_manor", "hushed_works", "tobin_annex"]:
		assert_eq(MapView.map_kind(a), "rooms")
		assert_true(MapView.rooms(a).size() >= 3)
	assert_eq(MapView.map_kind("below"), "none")
	assert_eq(MapView.map_kind("echo_trial"), "none")
	assert_eq(MapView.map_kind("arena"), "surface", "debug areas keep the legacy map")
	assert_eq(MapView.rooms("hushed_works").size(), 14, "spec §7.4 rooms")
	assert_eq(MapView.rooms("moonveil_manor").size(), 5, "spec §7.3 spaces")
	assert_eq(MapView.place_name("haven"), "Krystal's Haven")
	assert_eq(MapView.place_name("hr_orchard"), "Pumpkintide Orchard")
	assert_eq(MapView.place_name("hw_refuge"), "Pocket Conservatory")
	assert_eq(MapView.area_of("hr_bellhouse"), REACH)
	assert_eq(MapView.area_of("mm_gallery"), "moonveil_manor")
	assert_eq(MapView.area_of("quarry"), "surface", "legacy quarry, not Ashbell")
	assert_eq(MapView.place_disc("hr_quarry")["pos"], Vector2(86, 18))
	assert_true(MapView.place_disc("hw_vault").is_empty(), "rooms have no outdoor disc")
	# every Works / Manor / Annex zone of the spec has a room name; alt names under arachnophobia
	for a in ["moonveil_manor", "hushed_works", "tobin_annex"]:
		for r in MapView.rooms(a):
			assert_ne(MapView.place_name(String(r["id"]), a), "")
	Settings.set_value("arachnophobia", true)
	for a2 in ["moonveil_manor", "hushed_works", "tobin_annex"]:
		for r2 in MapView.rooms(a2):
			var n := MapView.place_name(String(r2["id"]), a2).to_lower()
			assert_false(n.contains("weaver") or n.contains("thread") or n.contains("web") or n.contains("silk"), "alt room name: " + n)


# --- Hollowhaven Woods -----------------------------------------------------------------------------------

func test_surface_map_legacy_layout_unchanged() -> void:
	var m: Control = await _open_map()
	assert_eq(m.title, "Hollowhaven Woods")
	assert_false(m.toggle_box.visible, "no toggle before the Reach")
	assert_eq(m.view.map_area, "surface")
	assert_true(m.view.show_player)
	assert_eq(m.view.all_targets(), ["haven"], "first step points home")
	assert_eq(MapPanel.place_ids("surface").size(), Layout.LANDMARKS.size())
	assert_true(_has_text(m, "It's circled on the map."))
	# the legacy projection: a square 800 map, 16 px margin, the same world_to_map as before
	var v := _standalone("surface", Vector2(800, 800))
	assert_eq(v.map_rect(), Rect2(16, 16, 768, 768))
	for id in Layout.LANDMARKS:
		var p: Vector2 = Layout.LANDMARKS[id]["pos"]
		assert_eq(v.to_map(p), UiUtil.world_to_map(p, v.map_rect(), MapView.H), "legacy projection for " + String(id))
	assert_eq(v._trees.size(), 150, "legacy seeded trees")
	assert_false(MapView.surface_waygate_visible(), "no waygate pin in a Chapter One save")


func test_surface_waygate_pin_after_acceptance_without_overlaps() -> void:
	_accept()
	assert_true(MapView.surface_waygate_visible())
	assert_false(MapView.surface_waygate_lit())
	var m: Control = await _open_map()
	assert_eq(m.view.all_targets(), ["ruin"], "The Hallowmere Way points at the Moonlit Ruin")
	# pin + label (above) clear of the ruin's sticker and name (below it)
	var v := _standalone("surface", Vector2(800, 800))
	var f := ThemeFactory.font("heading")
	var r: Rect2 = v.map_rect()
	var wc: Vector2 = v.to_map(Layout.CH2_POINTS["waygate"])
	var pin := Rect2(wc - Vector2(13, 17) * 1.35, Vector2(26, 34) * 1.35)
	var pin_label: Rect2 = v._label_rect(f, MapView.WAYGATE_NAME, Vector2(wc.x, wc.y - 24.0), 20, r)
	var rc: Vector2 = v.to_map(Layout.LANDMARKS["ruin"]["pos"])
	var ruin := Rect2(rc - Vector2(25, 25), Vector2(50, 50))
	var ruin_label: Rect2 = v._label_rect(f, String(Layout.LANDMARKS["ruin"]["name"]), Vector2(rc.x, rc.y + 25.0 + 18.0), 22, r)
	for a in [pin, pin_label]:
		for b in [ruin, ruin_label]:
			assert_false((a as Rect2).intersects(b), "waygate pin/label %s overlaps the ruin %s" % [a, b])
	assert_true(r.encloses(pin) and r.encloses(pin_label), "inside the map")


func test_surface_marks_the_waygate_for_reach_goals() -> void:
	_accept(["ch2_waygate_repaired"])
	assert_eq(GameState.chapter2.current_steps()[0]["id"], "ch2_commons")
	var g: Dictionary = MapPanel.goal_marks("surface")
	assert_eq(g["marks"], [MapView.WAYGATE_ID])
	var lines: Array = []
	for ln in g["lines"]:
		lines.append(String(ln[1]))
	assert_true(lines.has("Head to Lanternwake Commons, in Hallowmere Reach"))
	assert_true(lines.has("Through the Lanternwake waygate, north of the Moonlit Ruin."))
	var m: Control = await _open_map()
	assert_eq(m.view.all_targets(), [MapView.WAYGATE_ID])
	assert_true(_has_text(m, "Through the Lanternwake waygate"))


# --- Hallowmere Reach ------------------------------------------------------------------------------------

func test_reach_map_shows_discovered_places_only() -> void:
	_accept(TO_LAMPS)
	Game.area_id = REACH
	GameState.discover(REACH, "hr_commons")
	var m: Control = await _open_map()
	assert_eq(m.title, "Hallowmere Reach")
	assert_eq(m.view.map_area, REACH)
	assert_true(m.view.show_player)
	assert_eq(MapPanel.place_ids(REACH), ["hr_commons"])
	assert_eq(m.view._discovered, ["hr_commons"])
	assert_true(_has_text(m, "Lanternwake Commons"))
	assert_true(_has_text(m.places_grid, "Lanternwake Commons"))
	assert_false(_has_text(m.places_grid, "Pumpkintide Orchard"), "undiscovered districts are not listed")
	assert_false(_has_text(m.places_grid, "Sunken Bellhouse"), "undiscovered districts are not listed")
	assert_true(_has_text(m, "1 of %d places found" % Reach.LANDMARKS.size()))
	# every lamp is an objective marker, discovered or not ("?" pins)
	var marks: Array = m.view.all_targets()
	marks.sort()
	assert_eq(marks, ["hr_manor_grounds", "hr_orchard", "hr_quarry"])
	# arches: the commons one (district found), plus any lit arch; the orchard stays hidden
	assert_eq(MapView.visible_arches(), ["commons"])
	GameState.set_flag("ch2_arch_quarry")
	assert_eq(MapView.visible_arches(), ["commons", "quarry"])
	assert_true(MapView.arch_lit("quarry"))
	# no tell-tale clearings: trees are only removed inside DISCOVERED districts
	var v := _standalone(REACH, Vector2(1000, 800))
	assert_eq(v._visible_trees.size() < v._reach_trees.size(), true, "the Commons clearing is open")
	var orchard: Dictionary = Reach.LANDMARKS["hr_orchard"]
	var in_orchard := 0
	for t in v._visible_trees:
		var tp: Vector2 = t[0]
		if tp.distance_to(orchard["pos"]) < float(orchard["radius"]) * 0.8:
			in_orchard += 1
	assert_true(in_orchard > 0, "the undiscovered orchard is still forest on the map")
	var commons: Dictionary = Reach.LANDMARKS["hr_commons"]
	for t2 in v._visible_trees:
		var tp2: Vector2 = t2[0]
		assert_true(tp2.distance_to(commons["pos"]) >= float(commons["radius"]) * 0.9 + 4.0 - 0.001)
	# discovering more updates the page
	GameState.discover(REACH, "hr_orchard")
	m.refresh()
	await wait_frames(1)
	assert_eq(MapPanel.place_ids(REACH), ["hr_commons", "hr_orchard"])
	assert_true(_has_text(m.places_grid, "Pumpkintide Orchard"))


func test_reach_layout_geometry_has_no_overlaps() -> void:
	var v := _standalone(REACH, Vector2(1000, 800))
	var r: Rect2 = v.map_rect()
	var he: Vector2 = MapView.REACH_HALF
	assert_almost(r.size.x / r.size.y, he.x / he.y, 0.01, "uniform scale (aspect kept)")
	assert_true(r.size.x > 900.0, "uses the view (%s)" % r)
	for id in Reach.LANDMARKS:
		assert_true(r.has_point(v.to_map(Reach.LANDMARKS[id]["pos"])), "%s inside the map" % id)
	for pid in Reach.POINTS:
		assert_true(r.has_point(v.to_map(Reach.POINTS[pid])), "%s inside the map" % pid)
	# metres -> pixels identical on both axes
	var sx: float = (v.to_map(Vector2(10, 0)) - v.to_map(Vector2.ZERO)).x
	var sz: float = (v.to_map(Vector2(0, 10)) - v.to_map(Vector2.ZERO)).y
	assert_almost(sx, sz, 0.01)
	var boxes: Array = v.reach_boxes(true)
	assert_eq(boxes.size(), Reach.LANDMARKS.size() * 2 + Reach.ARCH_ORDER.size() + 2)
	for i in boxes.size():
		var a: Dictionary = boxes[i]
		assert_true(r.encloses(a["rect"]), "%s %s inside the map" % [a["kind"], a["id"]])
		for j in range(i + 1, boxes.size()):
			var b: Dictionary = boxes[j]
			if a["id"] == b["id"]:
				continue   # a sticker and its own name / the waygate and its label touch by design
			assert_false((a["rect"] as Rect2).intersects(b["rect"]), "%s %s overlaps %s %s" % [a["kind"], a["id"], b["kind"], b["id"]])


func test_reach_goal_in_another_area_points_the_way() -> void:
	_accept(TO_LAMPS + ["ch2_garden_lamp_lit", "ch2_quarry_lamp_lit", "ch2_manor_lamp_lit", "ch2_read_preparations",
		"ch2_lamps_linked"])
	assert_eq(GameState.chapter2.current_steps()[0]["id"], "ch2_service_gate")
	assert_eq(MapPanel.goal_marks(REACH)["marks"], ["hr_bellhouse"])
	# into the Works: the Bellhouse stair is the way down
	GameState.set_flag("ch2_service_gate_open")
	GameState.chapter2.evaluate()
	var g: Dictionary = MapPanel.goal_marks(REACH)
	assert_eq(g["marks"], ["hr_bellhouse"])
	var lines: Array = []
	for ln in g["lines"]:
		lines.append(String(ln[1]))
	assert_true(lines.has("Down the stair at the Sunken Bellhouse."))
	# a surface goal seen from the Reach: the waygate home
	assert_eq(MapPanel.way_to("surface", REACH), MapView.REACH_WAYGATE)
	assert_eq(MapPanel.way_to("moonveil_manor", REACH), "hr_manor_grounds")


func test_outdoor_toggle_after_visiting_the_reach() -> void:
	_accept(TO_LAMPS)
	GameState.discover(REACH, "hr_commons")
	Game.area_id = REACH
	var m: Control = await _open_map()
	assert_true(m.toggle_box.visible)
	assert_eq(m.toggle_box.get_child_count(), 2)
	m.show_area("surface")
	await wait_frames(1)
	assert_eq(m.shown_area, "surface")
	assert_eq(m.title, "Hollowhaven Woods")
	assert_eq(m.view.map_area, "surface")
	assert_false(m.view.show_player, "Krystal is not drawn on a map of another area")
	m.show_area(REACH)
	await wait_frames(1)
	assert_true(m.view.show_player)
	ui.close("map")
	await wait_frames(2)
	m = await _open_map({"area": "surface"})
	assert_eq(m.shown_area, "surface", "args.area opens a given outdoor map")


# --- interiors and no-map areas -------------------------------------------------------------------------------

func test_works_room_list_hides_undiscovered_rooms() -> void:
	_accept(TO_LAMPS + ["ch2_garden_lamp_lit", "ch2_quarry_lamp_lit", "ch2_manor_lamp_lit", "ch2_read_preparations",
		"ch2_lamps_linked", "ch2_service_gate_open"])
	assert_eq(GameState.chapter2.current_steps()[0]["id"], "ch2_true_signal")
	Game.area_id = "hushed_works"
	Game.zone_id = "hw_lockers"
	GameState.discover("hushed_works", "hw_landing")
	var rows: Array = MapPanel.room_rows("hushed_works", "hw_lockers", ["hw_rails"])
	var ids: Array = []
	for r in rows:
		ids.append(String(r["id"]))
	assert_eq(ids, ["hw_landing", "hw_lockers"], "found rooms + the one she stands in, in route order")
	assert_true(bool(rows[0]["safe"]))
	assert_true(bool(rows[1]["here"]))
	var m: Control = await _open_map()
	assert_eq(m.title, "The Hushed Works")
	assert_null(m.view, "no painted map in here")
	assert_true(_has_text(m, "Rooms you've found"))
	assert_true(_has_text(m, "Service Landing"))
	assert_true(_has_text(m, "you are here"))
	assert_true(_has_text(m, "2 of 14 rooms found"))
	assert_false(_has_text(m, "Choir Vault"), "undiscovered rooms stay hidden")
	assert_true(_has_text(m, "Head to Humming Rails"), "the goal room is named in the card")


func test_manor_and_annex_room_lists() -> void:
	Game.area_id = "moonveil_manor"
	GameState.discover("moonveil_manor", "mm_cloakroom")
	var m: Control = await _open_map()
	assert_eq(m.title, "Moonveil Manor")
	assert_true(_has_text(m, "Entrance Cloakroom"))
	assert_true(_has_text(m, "1 of 5 rooms found"))
	ui.close("map")
	await wait_frames(2)
	Game.area_id = "tobin_annex"
	m = await _open_map()
	assert_eq(m.title, "Tobin's Annex")
	assert_true(_has_text(m, "Nothing written down yet"))


func test_below_and_trial_have_no_map() -> void:
	Game.area_id = "below"
	var m: Control = await _open_map()
	assert_eq(m.title, "The Deep Places")
	assert_true(_has_text(m, "The map can't help you down here."))
	assert_true(_has_text(m, "Current goal: "))
	ui.close("map")
	await wait_frames(2)
	Game.area_id = "echo_trial"
	m = await _open_map()
	assert_true(_has_text(m, "Echoes don't keep maps."))


func test_map_windows_fit_the_canvas() -> void:
	_accept(TO_LAMPS)
	for id in Reach.LANDMARKS:
		GameState.discover(REACH, String(id))
	for a in ["surface", REACH, "hushed_works", "moonveil_manor", "tobin_annex", "below", "echo_trial"]:
		Game.area_id = String(a)
		for r in MapView.rooms(String(a)):
			GameState.discover(String(a), String(r["id"]))
		var m: Control = await _open_map()
		await wait_frames(2)
		var ms: Vector2 = m.window.get_combined_minimum_size()
		print("B11-LAYOUT map/%s %s" % [a, ms])
		assert_true(ms.x <= CANVAS.x and ms.y <= CANVAS.y - 30.0, "map %s fits (%s)" % [a, ms])
		ui.close("map")
		await wait_frames(2)


func test_festival_map_reveals_the_branch_roads() -> void:
	# Step 4 says "The festival map marks three sleeping lamps"; data/hallowmere_layout.gd MAP_ROUTES lists the
	# roads the board reveals. Before the board: nothing. After it: the roads and a "?" per unfound branch.
	var routes: Dictionary = MapView._reach_const("MAP_ROUTES", {})
	assert_false(routes.is_empty(), "the layout declares MAP_ROUTES")
	_accept(["ch2_waygate_repaired", "ch2_arch_commons"])
	GameState.discover(REACH, "hr_commons")
	assert_false(MapView.festival_map_read())
	assert_eq(MapView.festival_roads(), [])
	assert_eq(MapView.festival_hints(), [])
	GameState.discover(REACH, "hr_conservatory")
	var before := _standalone(REACH, Vector2(1000, 800))
	assert_eq(before._routes_world.size(), 0)
	assert_true(before.footpath_shown(1), "Commons -> Conservatory footpath while the road is unknown")
	var trees_before: int = before._visible_trees.size()
	GameState.set_flag(String(routes["flag"]))
	assert_true(MapView.festival_map_read())
	assert_eq(MapView.festival_roads().size(), (routes["roads"] as Array).size())
	assert_eq(MapView.festival_hints(), ["hr_orchard", "hr_quarry", "hr_manor_grounds"])
	var v := _standalone(REACH, Vector2(1000, 800))
	await wait_frames(2)
	assert_eq(v._routes_world.size(), (routes["roads"] as Array).size())
	assert_eq(v._route_ids, routes["roads"])
	assert_eq(v._routes_map.size(), v._routes_world.size(), "drawn (map-space cache built)")
	assert_false(v.footpath_shown(1), "the real main road replaces the straight dashed footpath")
	assert_false(v.footpath_shown(0), "arrival road likewise")
	var r: Rect2 = v.map_rect()
	for line in v._routes_map:
		for p in (line as PackedVector2Array):
			assert_true(r.grow(1.0).has_point(p), "road point %s inside the map" % p)
	# the known roads cut through the forest: no drawn tree disc sits on a road
	assert_true(v._visible_trees.size() < trees_before, "trees cleared along the roads")
	for t in v._visible_trees:
		assert_false(v._near_any_route(t[0], float(t[1]) * 0.9), "tree %s on a festival road" % t[0])
	# "?" pins only for branches still unfound; the undiscovered districts stay unnamed
	GameState.discover(REACH, "hr_orchard")
	assert_eq(MapView.festival_hints(), ["hr_quarry", "hr_manor_grounds"])
	assert_eq(MapPanel.place_ids(REACH), ["hr_commons", "hr_conservatory", "hr_orchard"])


func test_long_way_home_upgrades_the_pins() -> void:
	# The Long Way Home reward message promises fancier map pins (flag ch2_map_pins_upgraded).
	var plain := _standalone("surface", Vector2(800, 800))
	plain.target_ids = ["haven"]
	assert_false(plain.pins_upgraded)
	GameState.set_flag(MapView.PINS_UPGRADE_FLAG)
	var w := _standalone("surface", Vector2(800, 800))
	w.target_ids = ["haven"]
	var rv := _standalone(REACH, Vector2(1000, 800))
	rv.target_ids = ["hr_orchard"]
	await wait_frames(2)
	assert_true(w.pins_upgraded and rv.pins_upgraded)
	assert_eq(w._star.size(), 10, "star polygon without a closing duplicate (valid triangulation)")
	assert_eq(w._star_outline.size(), 11)
	assert_true(w.frames_drawn > 0 and rv.frames_drawn > 0, "upgraded pins drew without errors")


func test_map_reopen_switches_the_shown_area() -> void:
	_accept(TO_LAMPS)
	GameState.discover(REACH, "hr_commons")
	Game.area_id = REACH
	var m: Control = await _open_map()
	assert_eq(m.shown_area, REACH)
	ui.open("map", {"area": "surface"})      # already open -> reopen(args)
	await wait_frames(2)
	assert_eq(ui.panels.get("map"), m, "same panel")
	assert_eq(m.shown_area, "surface")
	assert_eq(m.title, "Hollowhaven Woods")


func test_both_painted_maps_really_draw() -> void:
	# Every drawing path runs without a script error: legacy woods, woods with the waygate + a Reach goal,
	# the Reach with undiscovered "?" targets, discovered districts, lit / unlit arches and the waygate home.
	_accept(TO_LAMPS)
	GameState.discover(REACH, "hr_commons")
	GameState.discover(REACH, "hr_quarry")
	GameState.set_flag("ch2_arch_orchard")
	var w := _standalone("surface", Vector2(800, 800))
	w.target_ids = [MapView.WAYGATE_ID, "haven"]
	var rv := _standalone(REACH, Vector2(1000, 800))
	rv.target_ids = ["hr_orchard", "hr_quarry", "hr_manor_grounds"]
	await wait_frames(3)
	assert_true(w.frames_drawn > 0, "woods map drew")
	assert_true(rv.frames_drawn > 0, "Reach map drew")
	assert_eq(rv._target_world.size(), 3)
	assert_eq(w._target_world.size(), 2)
	assert_eq(rv._arches, [["commons", true], ["orchard", true], ["quarry", false]])


# --- Mastery map clarity and Chapter One additions -------------------------------------------------------

func _wayfinding(rank: int) -> void:
	GameState.mastery["wayfinding"] = int(MasteryData.RANK_XP[rank])


## Wayfinding 2: gathered special-material spots become small icon pins (a pocket shares one pin); Wayfinding 4:
## unfound caches in discovered districts get a soft "?"; both on both outdoor maps, with legend rows, drawn
## without errors, and the windows still fit the canvas.
func test_mastery_pins_and_cache_hints_on_the_maps() -> void:
	_accept(TO_LAMPS)
	assert_true(Mastery.record_spot("surface", "sap_stump", Vector3(-46, 0, -14)))
	assert_true(Mastery.record_spot("surface", "sap_stump", Vector3(-40, 0, -14)), "6 m apart: a second spot")
	assert_true(Mastery.record_spot("surface", "bush", Vector3(-55, 0, 12)))
	assert_true(Mastery.record_spot(REACH, "iron_vein", Vector3(80, 0, 20)))
	_wayfinding(1)
	var v1 := _standalone("surface", Vector2(800, 800))
	assert_eq(v1.resource_pins, [], "rank 1: no pins")
	assert_eq(MapPanel.legend_extras("surface"), [])
	_wayfinding(2)
	var w := _standalone("surface", Vector2(800, 800))
	assert_eq(w.resource_pins.size(), 2, "the two stumps share one pin")
	var items: Array = []
	for pin in w.resource_pins:
		items.append(String(pin[2]))
	assert_true(items.has("resin") and items.has("berries"), "pins show the material (%s)" % [items])
	for pin in w.resource_pins:
		if String(pin[1]) == "sap_stump":
			assert_eq(int(pin[3]), 2)
	assert_eq(w.cache_hint_points, [], "rank 2: no cache hints yet")
	GameState.discover(REACH, "hr_commons")
	GameState.discover(REACH, "hr_candleyard")
	var rv := _standalone(REACH, Vector2(1000, 800))
	assert_eq(rv.resource_pins.size(), 1)
	assert_eq(String(rv.resource_pins[0][2]), "iron_ore")
	assert_eq(MapPanel.legend_extras("surface")[0]["text"], MapPanel.LEGEND_PINS)
	_wayfinding(4)
	GameState.discover("surface", "old_oak")
	var w4 := _standalone("surface", Vector2(800, 800))
	var c1x: Dictionary = (load("res://data/c1x_layout.gd") as Script).get_script_constant_map()
	assert_eq(w4.cache_hint_points, [c1x["TAILOR_CACHE"]["pos"]], "the Tailor's Cache hint near the Old Oak")
	var r4 := _standalone(REACH, Vector2(1000, 800))
	assert_eq(r4.cache_hint_points.size(), 2, "the Candleyard's hat and pattern (the Pools are not found yet)")
	var kinds: Array = []
	for ex in MapPanel.legend_extras(REACH):
		kinds.append(ex["kind"])
	assert_eq(kinds, ["pins", "hints"])
	await wait_frames(3)
	assert_true(w4.frames_drawn > 0 and r4.frames_drawn > 0 and rv.frames_drawn > 0, "pins and hints drew without errors")
	var r: Rect2 = w4.map_rect()
	for pin in w4.resource_pins:
		assert_true(r.has_point(w4.to_map(pin[0])), "pin inside the map")
	# the panels show the legend rows and still fit the canvas
	for a in ["surface", REACH]:
		Game.area_id = String(a)
		var m: Control = await _open_map()
		await wait_frames(2)
		assert_true(_has_text(m, MapPanel.LEGEND_PINS), "%s legend names the pins" % a)
		assert_true(_has_text(m, MapPanel.LEGEND_HINTS), "%s legend names the hints" % a)
		assert_eq(m.view.resource_pins.size(), 2 if a == "surface" else 1)
		var ms: Vector2 = m.window.get_combined_minimum_size()
		print("G3-LAYOUT map/%s with mastery rows %s" % [a, ms])
		assert_true(ms.x <= CANVAS.x and ms.y <= CANVAS.y - 30.0, "map %s fits with the mastery rows (%s)" % [a, ms])
		ui.close("map")
		await wait_frames(2)
	# found caches disappear (and so does the legend row once none is left on that map)
	GameState.set_flag("c1x_tailor_cache")
	GameState.set_flag("ch2_witch_hat_found")
	var w5 := _standalone("surface", Vector2(800, 800))
	assert_eq(w5.cache_hint_points, [])
	assert_eq(_standalone(REACH, Vector2(1000, 800)).cache_hint_points.size(), 1)
	assert_eq(MapPanel.legend_extras("surface").size(), 1, "surface: pins only")


## Chapter One's Bramblewatch gets its name on the woods map once its zone is discovered, clear of every
## sticker, name and the waygate pin.
func test_bramblewatch_named_on_the_woods_map_once_found() -> void:
	_accept()
	var before := _standalone("surface", Vector2(800, 800))
	assert_null(before.bramblewatch_at, "not before it is found")
	GameState.discover("surface", "c1x_bramblewatch")
	var zones: Array = (load("res://data/c1x_layout.gd") as Script).get_script_constant_map()["BRAMBLEWATCH_ZONES"]
	var v := _standalone("surface", Vector2(800, 800))
	assert_eq(v.bramblewatch_at, zones[0][0])
	var lr: Rect2 = v.bramblewatch_label_rect()
	var r: Rect2 = v.map_rect()
	assert_true(r.encloses(lr), "the name is inside the map")
	assert_false(lr.intersects(v.bramblewatch_marker_rect()), "the name does not cover its marker")
	for b in v.surface_blocks():
		assert_false(lr.intersects(b[1]), "Bramblewatch name %s overlaps %s %s" % [lr, b[0], b[1]])
	assert_false(v.surface_blocks().is_empty())
	assert_null(_standalone(REACH, Vector2(1000, 800)).bramblewatch_at, "woods only")
	await wait_frames(2)
	assert_true(v.frames_drawn > 0, "drawn without errors")


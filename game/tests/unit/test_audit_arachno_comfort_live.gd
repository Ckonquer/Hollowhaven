extends "res://tests/test_case.gd"
## AUDIT (arachnophobia & comfort): spider content that does not follow the arachnophobia option.
##  * the authored pale shapes (THE DISTANT CROSSING, the Silk Hollows intro) keep their spider body
##    when the option is switched on while they are on screen (everything else swaps live);
##  * the Ward Stone's warning still says the thing "weaves in the dark" (the lore alt text removes
##    exactly that wording);
##  * the title screen's Continue line shows the step title baked into the save ("The Silk Hollows").

const WORLD := "res://src/world/below/below_world.gd"
const WARD := "res://src/world/surface/ward_stone.gd"
const TITLE := "res://src/ui/title_screen.gd"

var area: Node3D = null
var extra: Node = null
var _saved: bool = false


func before_each() -> void:
	fresh_state()
	_saved = bool(Settings.get_value("arachnophobia"))


func after_each() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	if extra != null and is_instance_valid(extra):
		extra.queue_free()
	extra = null
	Settings.set_value("arachnophobia", _saved)
	await wait_frames(2)


func _goto_step(step_id: String) -> void:
	var steps: Array = GameState.quests.steps()
	for i in steps.size():
		if String(steps[i]["id"]) == step_id:
			GameState.quests.index = i
			return
	fail("no quest step " + step_id)


func test_pale_shapes_swap_when_arachnophobia_is_switched_on() -> void:
	Settings.set_value("arachnophobia", false)
	area = load(WORLD).new()
	add_child(area)
	await wait_physics(2)
	area.moments.hold = true
	area.moments.start_silk_intro()
	var silk: Node3D = area.moments.silk_shape
	assert_eq(String(silk.variant), "spider", "starts as the spider")
	area.moments.fire_crossing()
	var crossing: Node = area.find_child("CrossingShape", true, false)
	assert_not_null(crossing, "crossing shape spawned")
	# The player pauses, opens Comfort and turns arachnophobia mode on while both are on screen.
	Settings.set_value("arachnophobia", true)
	await wait_frames(3)
	var silk_now: Variant = area.moments.silk_shape
	if silk_now is Node and is_instance_valid(silk_now):
		assert_eq(String((silk_now as Node).get("variant")), "shade", "Silk Hollows intro shape is still a spider after switching arachnophobia on")
		assert_true(((silk_now as Node).get("_legs") as Array).is_empty(), "Silk Hollows intro shape still has %d spider legs" % ((silk_now as Node).get("_legs") as Array).size())
	if is_instance_valid(crossing) and not crossing.is_queued_for_deletion():
		assert_eq(String(crossing.get("variant")), "shade", "Distant Crossing shape is still a spider after switching arachnophobia on")


func test_ward_stone_warning_has_no_weaving_with_arachnophobia() -> void:
	Settings.set_value("arachnophobia", true)
	GameState.set_flag("read_ward_intro", true)
	_goto_step("prepare")
	var ws: Node3D = load(WARD).new()
	extra = ws
	add_child(ws)
	await wait_frames(1)
	var said: Array = []
	var cb := func(_speaker: String, text: String, _d: float) -> void:
		said.append(text)
	Events.say.connect(cb)
	ws.interact(null)
	Events.say.disconnect(cb)
	assert_true(bool(GameState.get_flag("read_ward_warning")), "warning inscription read")
	assert_false(said.is_empty(), "the stone spoke")
	for line in said:
		assert_false(String(line).to_lower().contains("weav"), "Ward Stone says '%s' with arachnophobia on" % String(line))


func test_title_continue_line_follows_arachnophobia() -> void:
	Settings.set_value("arachnophobia", false)
	_goto_step("silk")
	var data: Dictionary = SaveSystem.build_save_data()
	# Later (another session, or from the title's own Settings) arachnophobia mode is turned on.
	Settings.set_value("arachnophobia", true)
	var txt: String = load(TITLE).continue_text(data)
	assert_true(txt != "", "continue line built")
	assert_false(txt.contains("Silk"), "title Continue line shows '%s' with arachnophobia on" % txt)

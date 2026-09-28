extends "res://tests/test_case.gd"
## AUDIT (UI/input): every panel window must fit the 1920x1080 virtual canvas (stretch mode
## canvas_items + aspect expand means 1280x720 shows exactly this layout, scaled). A window whose
## combined minimum size is taller than the canvas gets clipped (its bottom buttons / top ribbon
## leave the screen). Prints the measured sizes as evidence.

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const CANVAS := Vector2(1920, 1080)

var ui: CanvasLayer
var _mode_before := ""


func before_each() -> void:
	UiUtil.allow_settings_save = false
	fresh_state()
	_mode_before = Game.mode
	Game.mode = "playing"
	ui = UiRootScript.new()
	add_child(ui)
	await wait_frames(2)


func after_each() -> void:
	if ui != null and is_instance_valid(ui):
		ui.close_all()
		ui.queue_free()
	await wait_frames(2)
	get_tree().paused = false
	Game.mode = _mode_before
	for p in Game._ui_stack.duplicate():
		Game.pop_ui(String(p))


func _measure(panel: String, args: Dictionary = {}) -> Dictionary:
	ui.open(panel, args)
	await wait_frames(3)
	var p: Control = ui.panels.get(panel)
	if p == null:
		return {}
	var w: Control = p.get("window")
	var ms: Vector2 = w.get_combined_minimum_size()
	var vp: Vector2 = p.get_viewport_rect().size
	var ribbon_top := 0.0
	var rib: Variant = w.get("ribbon")
	if rib is Control:
		var wy := roundf((CANVAS.y - ms.y) * 0.5)
		if wy < 30.0 and CANVAS.y > ms.y + 30.0:
			wy = 30.0
		ribbon_top = wy + (rib as Control).position.y   # where the ribbon would sit on a 1080-high canvas
	var out := {"panel": panel, "min": ms, "vp": vp, "pos": w.position, "size": w.size, "ribbon_top": ribbon_top}
	print("AUDIT-LAYOUT ", out)
	ui.close(panel)
	await wait_frames(2)
	return out


func test_all_panels_fit_the_virtual_canvas() -> void:
	# Give the backpack/crafting realistic content.
	for id in ["wood", "stone", "fiber", "berries", "copper_ore", "stone_axe", "stone_pickaxe", "lantern"]:
		if ItemDB.has_item(id):
			GameState.give_item(id, 3)
	var cases := [["pause", {}], ["settings", {}], ["settings", {"tab": "comfort"}], ["controls", {}],
		["comfort", {}], ["inventory", {}], ["crafting", {}], ["journal", {}], ["map", {}],
		["storage", {"uid": ""}], ["companion", {"id": "mochi"}]]
	for c in cases:
		var r: Dictionary = await _measure(String(c[0]), c[1])
		if r.is_empty():
			fail("panel %s did not open" % String(c[0]))
			continue
		var ms: Vector2 = r["min"]
		var vp := CANVAS   # headless reports a 1920x1920 root; the game's virtual canvas is 1920x1080
		assert_true(ms.y <= vp.y, "%s: window needs %.0f px height but the canvas is %.0f px (content clipped)" % [String(c[0]), ms.y, vp.y])
		assert_true(ms.x <= vp.x, "%s: window needs %.0f px width but the canvas is %.0f px" % [String(c[0]), ms.x, vp.x])
		assert_true(float(r["ribbon_top"]) >= 0.0, "%s: title ribbon starts above the screen (y=%.0f)" % [String(c[0]), float(r["ribbon_top"])])

extends "res://src/ui/panels/panel_base.gd"
## "Meet Krystal" (MP §4): the New Game creation screen, shown by the title after the overwrite warning and
## the comfort screen and BEFORE the first playable arrival. A rotating 3D preview plus the shared look
## editor (hair style, hair colour, skin, eyes, complete starter looks, single pieces, clothing colours from
## the starter swatches). Nothing is written while it is open: Confirm hands the look to the title
## (Game.new_game(look)); Back, Esc and the X return to the comfort screen without touching the save.
## Emits `finished` from on_close() on EVERY close path (the title's Esc path calls on_close() directly).
##   accepted = true only through Confirm; result = "confirm" | "back".
## args: {"look": a look dictionary to start from (e.g. the draft kept while going Back)}.

signal finished

const Wardrobe := preload("res://src/ui/panels/wardrobe_panel.gd")
const Preview := preload("res://src/ui/widgets/avatar_preview.gd")
const INTRO := "Choose how Krystal looks. It's all cosmetic, and you can change everything later at a mirror or wardrobe."

var look: Dictionary = {}
var accepted := false
var result := ""
var editor: Control
var preview: Control
var confirm_btn: Button
var back_btn: Button
var reset_btn: Button
var _finished := false


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Meet Krystal"
	window_min = Vector2(1660, 0)
	var start: Variant = p_args.get("look", {})
	var src: Variant = start if (start is Dictionary and not (start as Dictionary).is_empty()) else ItemDB.legacy_look()
	look = ItemDB.sanitize_look(src)["look"]


func _build() -> void:
	var il := Kit.wrap_label(INTRO, "", 1500, HORIZONTAL_ALIGNMENT_CENTER)
	il.add_theme_font_size_override("font_size", 25)
	il.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(il)
	var cols := Kit.hbox(28)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(cols)
	var pc := Kit.vbox(10)
	cols.add_child(pc)
	preview = Preview.new()
	preview.setup({"look": look, "size": Vector2(500, 620)})
	pc.add_child(preview)
	pc.add_child(Wardrobe.turn_row(preview))
	var ed := Wardrobe.LookEditor.new()
	ed.setup({"look": look, "wardrobe": Wardrobe.Looks.starter_wardrobe(), "show_locked": false,
		"width": 1040.0, "height": 500.0, "columns": 3, "category": "outfit"})
	ed.look_changed.connect(_on_look_changed)
	cols.add_child(ed)
	editor = ed
	Wardrobe.bind_face_preview(ed, preview)
	var bottom := Kit.hbox(18)
	body.add_child(bottom)
	back_btn = Kit.button("Back", _back, "GhostButton")
	back_btn.tooltip_text = "Back to the comfort options. Nothing is saved."
	bottom.add_child(back_btn)
	bottom.add_child(Kit.expander())
	var hint := Kit.label("Q / E: category    < >: turn", "Small")
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(hint)
	bottom.add_child(Kit.spacer(20, 0))
	reset_btn = Kit.button("Reset to default", _reset)
	reset_btn.tooltip_text = "Krystal's classic look: auburn side braid and her explorer outfit."
	bottom.add_child(reset_btn)
	confirm_btn = Kit.button("Confirm", _confirm, "AccentButton")
	confirm_btn.custom_minimum_size.x = 220
	confirm_btn.add_theme_font_size_override("font_size", 30)
	confirm_btn.name = "Confirm"
	bottom.add_child(confirm_btn)


func default_focus() -> Control:
	return confirm_btn


func _on_look_changed(l: Dictionary) -> void:
	look = l.duplicate(true)
	preview.call("set_look", look)


## Picks one choice (see Wardrobe.Looks key names). Starter items only; false if refused.
func choose(key: String, value: String) -> bool:
	return bool(editor.call("choose", key, value))


func _reset() -> void:
	look = ItemDB.legacy_look()
	editor.call("set_look", look)
	preview.call("set_look", look)


func _confirm() -> void:
	accepted = true
	result = "confirm"
	request_close()


func _back() -> void:
	result = "back"
	request_close()


func on_close() -> void:
	if _finished:
		return
	_finished = true
	if result == "":
		result = "back"
	finished.emit()


func handle_key(event: InputEvent) -> bool:
	if editor != null and bool(editor.call("handle_key", event)):
		return true
	return Wardrobe.preview_key(preview, event)


## On the title (no UI root) the panel handles its own keys.
func _unhandled_input(event: InputEvent) -> void:
	if ui_root != null or _closing or not is_visible_in_tree():
		return
	if handle_key(event):
		get_viewport().set_input_as_handled()


## Called by the title right before Game.new_game(look): once the new journey's state exists (Game.new_game
## resets GameState, then applies the look and emits Events.appearance_changed), marks "A Look of Your
## Own" as chosen and the one-time wardrobe notice as not needed (the player just styled Krystal).
static func arm_new_journey_marks() -> void:
	var cb := func() -> void:
		GameState.set_flag(Wardrobe.LOOK_FLAG, true)
		GameState.wardrobe["notice_shown"] = true
	Events.appearance_changed.connect(cb, CONNECT_ONE_SHOT)

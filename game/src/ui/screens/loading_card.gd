extends CanvasLayer
## Loading card between areas (perf finding, qa/tmp/perf/packaged_v200_nofocus: an area scene builds all its children
## on the main thread in ONE frame - 0.85-2.8 s cold in the packaged build - and Continue from the title had no fade, so
## the screen froze on whatever was last drawn). Game.load_area() shows this card BEFORE that frame: the fade colour
## as a backdrop, a small parchment card with the area's name (MapView.area_name, so every screen names places the
## same way) and a lantern whose warm glow pulses gently (a steady glow with Settings "reduce_flashing"). show_card()
## returns only after PRESENT_FRAMES more frames with the card fully shown have been drawn, so the frozen build frame
## keeps showing the card. Nothing animates while the main thread builds - the pulse is only seen around it. After the
## area is built, hide_card() dissolves the card while the UI root fades the new area in.
## Owned by Game (one node created in Game._ready, a child of the autoload so it survives the scene change); layer 60 is
## above the UI root (50) and the title (10). Always processes (the tree may still be paused when a load starts).
## API: show_card(area_id, fade := FADE_IN) (awaitable), hide_card(fade := FADE_OUT), is_showing(), is_fully_shown(),
## is_hiding(), is_pulsing(), shown_frame, static area_title(area_id). Emits `hidden` once it has gone.

signal hidden

const Kit := preload("res://src/ui/ui_kit.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")

const MAP_VIEW_PATH := "res://src/ui/widgets/map_view.gd"   # loaded on first use (a large script: not at boot)
const LAYER := 60
const FADE_COLOR := Color(0.07, 0.05, 0.08, 1.0)      # the UI root's / the title's fade colour
const FADE_IN := 0.3
const FADE_OUT := 0.4
## Process frames show_card() still waits once the card is fully opaque: the frame that reached full opacity plus
## these are drawn (and handed to the swap chain) before the caller may start the blocking build.
const PRESENT_FRAMES := 2
const FALLBACK_TITLE := "Hollowhaven"
const CARD_MIN_W := 560.0
const LANTERN_BOX := 136.0
const LANTERN_ICON := 88.0
const GLOW_COLOR := Color(1.0, 0.78, 0.42)
const PULSE_HALF := 1.3            # seconds from dim to bright (a full breath is twice that)
const GLOW_LOW := 0.45
const GLOW_HIGH := 1.0
const GLOW_STEADY := 0.8           # reduce_flashing: one steady glow, no pulse
const GLOW_SCALE_LOW := 0.93
const GLOW_SCALE_HIGH := 1.06

var root: Control
var backdrop: ColorRect
var card: PanelContainer
var name_l: Label
var glow: TextureRect
var lantern: TextureRect
var area_id := ""
## Engine.get_process_frames() when the card was first known to be fully opaque in this showing (-1 = not yet).
var shown_frame := -1
var _state := "hidden"             # hidden | showing | shown | hiding
var _tw: Dictionary = {}
var _pulse: Tween = null

static var _map_view: Script = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


## The name shown for an area: MapView.area_name(area_id), or FALLBACK_TITLE for an area without one (debug arenas).
static func area_title(p_area_id: String) -> String:
	if _map_view == null and ResourceLoader.exists(MAP_VIEW_PATH):
		var s: Variant = load(MAP_VIEW_PATH)
		if s is Script and (s as Script).can_instantiate():
			_map_view = s
	var n := ""
	if _map_view != null:
		n = String(_map_view.call("area_name", p_area_id))
	return n if n != "" else FALLBACK_TITLE


## Fades the card in (from wherever it is) and returns once it is fully shown AND PRESENT_FRAMES more process frames
## have passed, i.e. frames showing it have been drawn. Returns early if hide_card() takes over meanwhile.
func show_card(p_area_id: String, fade: float = FADE_IN) -> void:
	_build()
	area_id = p_area_id
	name_l.text = area_title(p_area_id)
	visible = true
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_state = "showing"
	shown_frame = -1
	_set_pulse(not _calm())
	var tw := Kit.retween(self, _tw, "fade")
	var from := root.modulate.a
	if fade <= 0.0 or from >= 0.999:
		tw.kill()
		root.modulate.a = 1.0
	else:
		tw.tween_property(root, "modulate:a", 1.0, fade * (1.0 - from)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		await _wait_tween(tw)
		if _tw.get("fade") != tw or _state != "showing":
			return
		root.modulate.a = 1.0
	_state = "shown"
	shown_frame = Engine.get_process_frames()
	for i in PRESENT_FRAMES:
		await get_tree().process_frame


## Dissolves the card (not awaitable; `hidden` is emitted and is_showing() turns false once it has gone). fade 0 = at once.
func hide_card(fade: float = FADE_OUT) -> void:
	if _state == "hidden" or _state == "hiding":
		return
	_state = "hiding"
	if backdrop != null:
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := Kit.retween(self, _tw, "fade")
	if fade <= 0.0 or root == null:
		tw.kill()
		_finish_hide()
		return
	tw.tween_property(root, "modulate:a", 0.0, fade).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_finish_hide)


## On screen at all (fading in, shown, or dissolving).
func is_showing() -> bool:
	return _state != "hidden"


## Fully opaque (the state the blocking build frame starts in).
func is_fully_shown() -> bool:
	return _state == "shown" and root != null and root.modulate.a >= 0.999


func is_hiding() -> bool:
	return _state == "hiding"


func is_pulsing() -> bool:
	return _pulse != null and _pulse.is_valid() and _pulse.is_running()


func _finish_hide() -> void:
	if root != null:
		root.modulate.a = 0.0
	visible = false
	_state = "hidden"
	shown_frame = -1
	_set_pulse(false)
	hidden.emit()


func _calm() -> bool:
	var v: Variant = Settings.get_value("reduce_flashing")
	return v is bool and v


## Waits until `tw` finished OR was killed by a newer fade (a killed tween never emits `finished`).
func _wait_tween(tw: Tween) -> void:
	while tw != null and tw.is_valid() and tw.is_running():
		await get_tree().process_frame


func _set_pulse(on: bool) -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	if glow == null:
		return
	glow.scale = Vector2.ONE
	if not on:
		glow.modulate.a = GLOW_STEADY
		return
	glow.modulate.a = GLOW_LOW
	glow.scale = Vector2.ONE * GLOW_SCALE_LOW
	_pulse = create_tween().set_loops()
	_pulse.tween_property(glow, "modulate:a", GLOW_HIGH, PULSE_HALF).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.parallel().tween_property(glow, "scale", Vector2.ONE * GLOW_SCALE_HIGH, PULSE_HALF).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(glow, "modulate:a", GLOW_LOW, PULSE_HALF).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.parallel().tween_property(glow, "scale", Vector2.ONE * GLOW_SCALE_LOW, PULSE_HALF).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- Building (once, on first use) --------------------------------------------------------------------------

func _build() -> void:
	if root != null:
		return
	root = Control.new()
	root.name = "Root"
	Kit.full_rect(root)
	root.theme = ThemeFactory.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.modulate.a = 0.0
	add_child(root)
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = FADE_COLOR
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(Kit.full_rect(backdrop))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(Kit.full_rect(cc))
	card = PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", ThemeFactory.parchment_style())
	card.material = ThemeFactory.paper_material()
	card.custom_minimum_size = Vector2(CARD_MIN_W, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(card)
	var col := Kit.vbox(6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	col.add_child(_build_lantern())
	name_l = Kit.label("", "Heading", HORIZONTAL_ALIGNMENT_CENTER)
	name_l.name = "AreaName"
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var orn := Kit.hbox(12)
	orn.alignment = BoxContainer.ALIGNMENT_CENTER
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var leaf_col := Color("9cbf63")
	var lf := Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, leaf_col), 34)
	lf.flip_h = true
	orn.add_child(lf)
	orn.add_child(Kit.icon_rect(IconFactory.glyph("leaf", 60, 24, leaf_col), 34))
	col.add_child(orn)


## The lantern: a warm radial glow (pulsed by _set_pulse) behind the Lantern item's icon, in a fixed square box.
func _build_lantern() -> Control:
	var box := Control.new()
	box.name = "Lantern"
	box.custom_minimum_size = Vector2(LANTERN_BOX, LANTERN_BOX)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(GLOW_COLOR, 0.85))
	grad.set_color(1, Color(GLOW_COLOR, 0.0))
	grad.add_point(0.45, Color(GLOW_COLOR, 0.38))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	glow = TextureRect.new()
	glow.name = "Glow"
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = Vector2.ZERO
	glow.size = Vector2(LANTERN_BOX, LANTERN_BOX)
	glow.pivot_offset = Vector2(LANTERN_BOX, LANTERN_BOX) * 0.5
	box.add_child(glow)
	lantern = Kit.icon_rect(IconFactory.item_icon("lantern", 128), LANTERN_ICON)
	lantern.name = "Icon"
	lantern.position = Vector2(LANTERN_BOX - LANTERN_ICON, LANTERN_BOX - LANTERN_ICON) * 0.5
	lantern.size = Vector2(LANTERN_ICON, LANTERN_ICON)
	box.add_child(lantern)
	return box

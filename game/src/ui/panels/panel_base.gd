extends Control
## Base for UI panels: optional dimmed backdrop + a centred parchment window with a ribbon title and
## a round close button. Subclasses override _build() (add content to `body`), refresh(), on_close(),
## handle_key(event) and is_capturing_input(). The owner (ui_root or the title screen) listens to
## `close_requested`, handles Game.push_ui/pop_ui and pausing; panels never change global state
## themselves except through GameState / Settings.

signal close_requested

## Room kept on each side of the title ribbon, so a long title never runs into the round close button (visual QA
## UI-10: "Echo Trial: The Last Waltz (a remembered challenge)" was wider than its card).
const RIBBON_SIDE_CLEAR := 84.0

const Kit := preload("res://src/ui/ui_kit.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const Parchment := preload("res://src/ui/widgets/parchment_panel.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

var panel_id: String = ""
var ui_root: Node = null               # the owning UI root (null on the title screen)
var args: Dictionary = {}
var title: String = ""
var dim_background: bool = true
var window_min := Vector2(1100, 700)
## Screen height (canvas px) kept free at the bottom when centring the window, e.g. the HUD hotbar under a panel
## that does not dim the world (companion menu, visual QA UI-12). 0 = centre on the whole screen.
var bottom_reserve: float = 0.0
var show_close: bool = true
var window: PanelContainer
var body: VBoxContainer
var close_btn: Button
var _frame: Control
var _tw: Dictionary = {}
var _closing := false


func setup(p_args: Dictionary) -> void:
	args = p_args


func _ready() -> void:
	Kit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP if dim_background else Control.MOUSE_FILTER_IGNORE
	if dim_background:
		var dim := ColorRect.new()
		dim.color = ThemeFactory.DIM
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(Kit.full_rect(dim))
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(_frame))
	window = Parchment.new()
	window.custom_minimum_size = window_min
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.add_child(window)
	if title != "":
		window.set_ribbon(title)
	_fit_ribbon()
	body = Kit.vbox(14)
	window.add_child(body)
	if show_close:
		close_btn = Kit.close_button(request_close)
		close_btn.focus_mode = Control.FOCUS_NONE
		window.add_child(close_btn)
		window.sort_children.connect(_place_close)
	_frame.resized.connect(_layout_window)
	window.minimum_size_changed.connect(_layout_window)
	_build()
	refresh()
	_layout_window()
	_animate_in()
	_focus_default.call_deferred()


## Override: build the panel content into `body`.
func _build() -> void:
	pass


## Override: update from game state.
func refresh() -> void:
	pass


## Override: called by the owner just before the panel is removed.
func on_close() -> void:
	pass


## Override: panel-specific keys. Return true if handled (the global hotkeys are then skipped).
func handle_key(_event: InputEvent) -> bool:
	return false


## Override: true while the panel captures raw input (e.g. waiting for a key to rebind).
func is_capturing_input() -> bool:
	return false


## Override: the control that should get keyboard focus when opened.
func default_focus() -> Control:
	return null


func request_close() -> void:
	if _closing:
		return
	close_requested.emit()


func set_title(text: String) -> void:
	title = text
	if window != null:
		window.set_ribbon(text)
		_fit_ribbon()


## Widens the window (never narrows it below window_min) so the ribbon keeps RIBBON_SIDE_CLEAR on both sides.
func _fit_ribbon() -> void:
	if window == null:
		return
	var rb: Variant = window.get("ribbon")
	var need := window_min.x
	if rb is Control and title != "":
		need = maxf(need, (rb as Control).get_combined_minimum_size().x + RIBBON_SIDE_CLEAR * 2.0)
	window.custom_minimum_size.x = need


## Plays the closing animation then frees the panel.
func animate_out_and_free() -> void:
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := Kit.retween(self, _tw, "anim")
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
	if window != null:
		tw.tween_property(window, "scale", Vector2(0.97, 0.97), 0.14)
	tw.chain().tween_callback(queue_free)


func _layout_window() -> void:
	if window == null or _frame == null:
		return
	var ms := window.get_combined_minimum_size()
	var avail := _frame.size
	if avail.x <= 0.0:
		avail = get_viewport_rect().size
	var sz := Vector2(minf(ms.x, avail.x - 24.0), minf(ms.y, avail.y - 24.0))
	sz = sz.max(ms.min(avail))
	window.size = sz
	window.position = ((avail - sz) * 0.5).round()
	if bottom_reserve > 0.0:
		# centred in the space above the reserve, but never pushed above the ribbon's clearance
		window.position.y = maxf(minf(window.position.y, round((avail.y - bottom_reserve - sz.y) * 0.5)), 30.0)
	if window.position.y < 30.0 and avail.y > sz.y + 30.0:
		window.position.y = 30.0
	window.pivot_offset = sz * 0.5


func _place_close() -> void:
	if close_btn == null:
		return
	var ms := close_btn.get_combined_minimum_size()
	close_btn.size = ms
	close_btn.position = Vector2(window.size.x - ms.x * 0.72, -ms.y * 0.28)


func _animate_in() -> void:
	modulate.a = 0.0
	window.scale = Vector2(0.965, 0.965)
	var tw := Kit.retween(self, _tw, "anim")
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "modulate:a", 1.0, 0.16)
	tw.tween_property(window, "scale", Vector2.ONE, 0.22)


func _focus_default() -> void:
	if not is_inside_tree():
		return
	var c := default_focus()
	if c != null and c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE:
		c.grab_focus()


## Helper: a section heading label with a small leaf ornament.
func section_title(text: String) -> HBoxContainer:
	var h := Kit.hbox(8)
	h.add_child(Kit.icon_rect(IconFactory.glyph("leaf", 30, 20, Color("7fae57")), 22))
	h.add_child(Kit.label(text, "Subheading"))
	return h

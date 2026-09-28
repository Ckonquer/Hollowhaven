extends HBoxContainer
## Active companion portrait with name, bond hearts and what they're doing. Hidden when nobody follows.
## Chapter Two (MP §6.1): a cooldown ring around the portrait for the signature skill (shared by the autocast
## and the Companion Skill key), a small "[T] Bloomguard" / "Bloomguard 12 s" line, and a ready flash when the
## skill comes back (with reduce_flashing: a steady glow instead of the flash). Reads GameState only; the ring
## freezes while the game is paused because the cooldown lives on the play_seconds timeline.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const Support := preload("res://src/companions/companion_support.gd")

const RING_COLOR := Color("7fc3a0")
const RING_BACK := Color(0, 0, 0, 0.28)
const READY_COLOR := Color("ffd98a")
const FLASH_SECONDS := 0.9

var portrait: Control
var name_l: Label
var hearts_box: HBoxContainer
var skill_l: Label
var _tex: Texture2D
var _id := ""
var _level := -1
var _frac := 0.0              # 0..1 of the cooldown still running (drawn as the ring)
var _flash := 0.0             # seconds of the ready flash left
var _ready_glow := false      # steady ring when the skill is ready and flashing is reduced
var _tick := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	portrait = Control.new()
	portrait.custom_minimum_size = Vector2(78, 78)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.draw.connect(_draw_portrait)
	add_child(portrait)
	var v := Kit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)
	name_l = Kit.label("", "HudText")
	name_l.add_theme_font_override("font", ThemeFactory.font("heading"))
	name_l.add_theme_font_size_override("font_size", 26)
	v.add_child(name_l)
	hearts_box = Kit.hbox(0)
	hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hearts_box)
	skill_l = Kit.label("", "HudText")
	skill_l.add_theme_font_size_override("font_size", 18)
	skill_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(skill_l)
	Events.companion_assignment_changed.connect(func(_i: String, _a: String) -> void: refresh())
	Events.companion_bond_changed.connect(func(_i: String, _l: int) -> void: refresh(true))
	Events.companion_befriended.connect(func(_i: String) -> void: refresh())
	Events.area_loaded.connect(func(_a: String) -> void: refresh())
	Events.game_loaded.connect(refresh)
	Events.companion_skill_ready.connect(_on_skill_ready)
	Events.companion_skill_used.connect(func(_i: String, _s: String) -> void: _update_skill())
	Events.settings_changed.connect(func(_k: String) -> void: _update_skill())
	refresh()


func refresh(bump: bool = false) -> void:
	var id := GameState.active_companion
	if id == "" or ItemDB.creature(id).is_empty():
		visible = false
		_id = ""
		return
	visible = true
	var lvl := GameState.bond_level(id)
	if id != _id:
		_id = id
		_tex = IconFactory.portrait(id)
		portrait.queue_redraw()
		name_l.text = String(ItemDB.creature(id).get("name", id.capitalize()))
	if lvl != _level:
		_level = lvl
		for c in hearts_box.get_children():
			c.queue_free()
		var hb := Kit.hearts(lvl, 5, 26)
		hearts_box.add_child(hb)
	_update_skill()
	if bump:
		modulate = Color(1.3, 1.15, 1.2)
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color.WHITE, 0.8)


## Cooldown ring + label from GameState (cheap: a few dictionary reads, 8 times a second while visible).
func _update_skill() -> void:
	if _id == "" or skill_l == null:
		return
	var sk := Support.skill_name(_id)
	if sk == "":
		skill_l.text = ""
		_frac = 0.0
		portrait.queue_redraw()
		return
	var rem := Support.remaining(_id)
	var f := Support.cooldown_fraction(_id)
	if rem > 0.0:
		skill_l.text = "%s  %d s" % [sk, ceili(rem)]
	else:
		skill_l.text = "[%s] %s" % [Settings.action_label("companion_skill"), sk]
	_ready_glow = rem <= 0.0 and _reduce_flashing()
	if not is_equal_approx(f, _frac):
		_frac = f
		portrait.queue_redraw()


func _reduce_flashing() -> bool:
	var v: Variant = Settings.get_value("reduce_flashing")
	return v is bool and v


func _on_skill_ready(id: String) -> void:
	if id != _id or not visible:
		return
	_update_skill()
	if _reduce_flashing():
		_ready_glow = true            # no flash: the ring simply glows steadily while ready
		portrait.queue_redraw()
		return
	_flash = FLASH_SECONDS
	portrait.queue_redraw()


func _process(delta: float) -> void:
	if not visible or _id == "":
		return
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		portrait.queue_redraw()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.125
		_update_skill()


func flash_strength() -> float:
	return _flash / FLASH_SECONDS if FLASH_SECONDS > 0.0 else 0.0


func _draw_portrait() -> void:
	var c := portrait.size * 0.5
	var r := 36.0
	portrait.draw_circle(c + Vector2(0, 3), r + 3.0, Color(0, 0, 0, 0.25), true, -1.0, true)
	portrait.draw_circle(c, r + 3.0, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
	if _tex != null:
		portrait.draw_texture_rect(_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
	portrait.draw_arc(c, r + 1.5, 0.0, TAU, 64, ThemeFactory.INK, 3.0, true)
	# Cooldown ring: the part still recharging, sweeping clockwise from the top.
	if _frac > 0.001:
		portrait.draw_arc(c, r + 5.5, 0.0, TAU, 64, RING_BACK, 4.0, true)
		var start := -PI * 0.5
		portrait.draw_arc(c, r + 5.5, start, start + TAU * _frac, maxi(8, int(64.0 * _frac)), RING_COLOR, 4.0, true)
	elif _ready_glow:
		portrait.draw_arc(c, r + 5.5, 0.0, TAU, 64, Color(READY_COLOR, 0.75), 3.0, true)
	if _flash > 0.0:
		var k := _flash / FLASH_SECONDS
		portrait.draw_arc(c, r + 5.5 + (1.0 - k) * 6.0, 0.0, TAU, 64, Color(READY_COLOR, k), 5.0, true)

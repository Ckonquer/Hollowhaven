extends VBoxContainer
## Boss health bar (Events.boss_health_changed; hp < 0 hides it). Name via ItemDB.enemy_display_name
## so the arachnophobia option shows "The Hollow Mother".

const Kit := preload("res://src/ui/ui_kit.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var boss_id := ""
var hp := 0.0
var max_hp := 1.0
var name_l: Label
var bar: Control
var _shown := 0.0
var _ghost := 0.0
var _ghost_hold := 0.0
var _tw: Dictionary = {}
var _sb_frame: StyleBoxFlat
var _sb_ghost: StyleBoxFlat
var _sb_fill: StyleBoxFlat
var _sb_gloss: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_sb_frame = ThemeFactory.box(Color("2a2330"), 16, 3, Color("e2b95a"), 0, 8, Vector2(0, 4), Color(0, 0, 0, 0.35))
	_sb_ghost = ThemeFactory.box(Color("e7b0c4"), 11)
	_sb_fill = ThemeFactory.box(Color("a24a8a"), 11)
	_sb_gloss = ThemeFactory.box(Color(1, 1, 1, 0.22), 5)
	name_l = Kit.label("", "HudTitle", HORIZONTAL_ALIGNMENT_CENTER)
	name_l.add_theme_font_size_override("font_size", 32)
	add_child(name_l)
	bar = Control.new()
	bar.custom_minimum_size = Vector2(760, 34)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(_draw_bar)
	add_child(bar)
	visible = false
	modulate.a = 0.0
	Events.boss_health_changed.connect(on_boss_health)
	Events.settings_changed.connect(func(k: String) -> void:
		if k == "arachnophobia" and boss_id != "":
			name_l.text = ItemDB.enemy_display_name(boss_id))
	Events.area_exiting.connect(func(_a: String) -> void: on_boss_health("", -1.0, 1.0))


func on_boss_health(p_boss_id: String, p_hp: float, p_max: float) -> void:
	if p_hp < 0.0:
		if visible:
			var tw := Kit.retween(self, _tw, "fade")
			tw.tween_property(self, "modulate:a", 0.0, 0.8)
			tw.tween_callback(func() -> void: visible = false)
		boss_id = ""
		return
	var first := boss_id != p_boss_id or not visible
	boss_id = p_boss_id
	hp = p_hp
	max_hp = maxf(p_max, 1.0)
	name_l.text = ItemDB.enemy_display_name(boss_id)
	if first:
		_shown = hp
		_ghost = hp
		visible = true
		var tw2 := Kit.retween(self, _tw, "fade")
		tw2.tween_property(self, "modulate:a", 1.0, 0.8)


func _process(delta: float) -> void:
	if not visible:
		return
	_shown = lerpf(_shown, hp, clampf(delta * 9.0, 0.0, 1.0))
	if hp < _ghost - 0.1:
		_ghost_hold -= delta
		if _ghost_hold <= 0.0:
			_ghost = lerpf(_ghost, hp, clampf(delta * 2.5, 0.0, 1.0))
	else:
		_ghost_hold = 0.6
		_ghost = maxf(_ghost, _shown)
	bar.queue_redraw()


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, bar.size)
	bar.draw_style_box(_sb_frame, r)
	var inner := r.grow(-5)
	var gw := inner.size.x * clampf(_ghost / max_hp, 0.0, 1.0)
	if gw > 2.0:
		bar.draw_style_box(_sb_ghost, Rect2(inner.position, Vector2(gw, inner.size.y)))
	var fw := inner.size.x * clampf(_shown / max_hp, 0.0, 1.0)
	if fw > 2.0:
		bar.draw_style_box(_sb_fill, Rect2(inner.position, Vector2(fw, inner.size.y)))
		if fw > 20.0:
			bar.draw_style_box(_sb_gloss, Rect2(inner.position + Vector2(8, 3), Vector2(fw - 16.0, 6)))

extends HBoxContainer
## Day / time indicator: a little round window onto the sky (sun or moon travelling across it, soft
## hills below) with "Day 3" and the time of day next to it.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Palette := preload("res://src/art/palette.gd")

const R := 44.0

var day_l: Label
var time_l: Label
var dial: Control
var _hour := 8.0
var _sun: Texture2D
var _moon: Texture2D
var _lantern: Texture2D
var _last_min := -1
var _hills: Array = []
var _hill_cache_hour := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	alignment = BoxContainer.ALIGNMENT_END
	var v := Kit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)
	day_l = Kit.label("", "HudTitle", HORIZONTAL_ALIGNMENT_RIGHT)
	day_l.add_theme_font_size_override("font_size", 32)
	v.add_child(day_l)
	time_l = Kit.label("", "HudSmall", HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(time_l)
	dial = Control.new()
	dial.custom_minimum_size = Vector2(R * 2.0 + 10.0, R * 2.0 + 10.0)
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial.draw.connect(_draw_dial)
	add_child(dial)
	_sun = IconFactory.icon("ui_sun", Color.WHITE, 64)
	_moon = IconFactory.icon("ui_moon", Color.WHITE, 64)
	_lantern = IconFactory.item_icon("lantern", 64)
	Events.time_of_day_changed.connect(func(_d: int, _t: float) -> void: refresh())
	Events.area_loaded.connect(func(_a: String) -> void:
		_last_min = -1
		refresh())
	refresh()


func refresh() -> void:
	_hour = GameState.hour()
	var minute := int(_hour * 60.0)
	if minute == _last_min:
		return
	_last_min = minute
	day_l.text = "Day %d" % GameState.day()
	time_l.text = "%s  ·  %s" % [UiUtil.day_phase(_hour), UiUtil.format_clock(_hour)]
	dial.queue_redraw()


static func sky_color(hour: float) -> Color:
	var h := fposmod(hour, 24.0)
	var night := Palette.SKY_NIGHT_TOP.lerp(Palette.SKY_NIGHT_HORIZON, 0.45)
	var day := Palette.SKY_TOP
	var dusk := Color("f2a36b")
	if h < 5.0 or h >= 21.0:
		return night
	if h < 7.0:
		return night.lerp(dusk, (h - 5.0) / 2.0)
	if h < 8.5:
		return dusk.lerp(day, (h - 7.0) / 1.5)
	if h < 18.0:
		return day
	if h < 19.5:
		return day.lerp(dusk, (h - 18.0) / 1.5)
	return dusk.lerp(night, (h - 19.5) / 1.5)


func _draw_dial() -> void:
	var c := dial.size * 0.5
	var below := Game.area_id == "below"
	var sky := sky_color(_hour) if not below else Color("2e2733")
	dial.draw_circle(c + Vector2(0, 3), R + 4.0, Color(0, 0, 0, 0.25), true, -1.0, true)
	dial.draw_circle(c, R + 4.0, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
	dial.draw_circle(c, R, sky, true, -1.0, true)
	dial.draw_circle(c + Vector2(0, -R * 0.35), R * 0.62, Color(sky.lightened(0.18), 0.5), true, -1.0, true)
	# celestial body travelling along an arc: sun 6h..20h, moon otherwise
	var h := fposmod(_hour, 24.0)
	var is_day := h >= 6.0 and h < 20.0
	var t: float
	if is_day:
		t = (h - 6.0) / 14.0
	else:
		t = fposmod(h - 20.0, 24.0) / 10.0
	var ang := PI + t * PI
	var body_pos := c + Vector2(cos(ang), sin(ang)) * (R * 0.62) + Vector2(0, R * 0.12)
	var bs := 30.0
	if below:
		# underground: a little lantern glows where the sky would be
		dial.draw_circle(c + Vector2(0, -R * 0.2), R * 0.5, Color(1.0, 0.75, 0.4, 0.18), true, -1.0, true)
		dial.draw_texture_rect(_lantern, Rect2(c + Vector2(-17, -R * 0.2 - 19), Vector2(34, 34)), false)
	else:
		dial.draw_texture_rect(_sun if is_day else _moon, Rect2(body_pos - Vector2(bs, bs) * 0.5, Vector2(bs, bs)), false)
	if not is_day and not below:
		for s in [Vector2(-0.45, -0.35), Vector2(0.35, -0.55), Vector2(0.55, -0.1), Vector2(-0.15, -0.65)]:
			dial.draw_circle(c + s * R, 1.8, Color(1, 1, 0.9, 0.85), true, -1.0, true)
	# hills: a wavy band intersected with the dial circle
	if _hill_cache_hour != int(_hour * 4.0) or _hills.is_empty():
		_hill_cache_hour = int(_hour * 4.0)
		var band := PackedVector2Array()
		var y0 := R * 0.32
		for i in 25:
			var x := -R - 6.0 + (2.0 * R + 12.0) * float(i) / 24.0
			var wave := sin(float(i) * 0.55) * 4.0 + sin(float(i) * 0.21 + 1.0) * 5.0
			band.append(Vector2(x, y0 + wave))
		band.append(Vector2(R + 6.0, R + 8.0))
		band.append(Vector2(-R - 6.0, R + 8.0))
		var circle := PackedVector2Array()
		for i in 48:
			var a := TAU * float(i) / 48.0
			circle.append(Vector2(cos(a), sin(a)) * (R - 0.5))
		_hills = Geometry2D.intersect_polygons(band, circle)
	var hill_col := Palette.GRASS if is_day else Palette.GRASS_DARK.darkened(0.45)
	if below:
		hill_col = Palette.MINE_ROCK
	for poly in _hills:
		var pts: PackedVector2Array = poly
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + c)
		dial.draw_colored_polygon(moved, hill_col)
	dial.draw_arc(c, R + 2.0, 0.0, TAU, 64, ThemeFactory.INK, 3.0, true)
	dial.draw_arc(c, R + 5.5, 0.0, TAU, 64, Color(ThemeFactory.INK, 0.55), 1.6, true)

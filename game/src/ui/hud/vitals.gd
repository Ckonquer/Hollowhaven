extends Control
## Health and stamina: sticker icons + rounded, framed bars. Values ease toward the real ones, a pale
## "ghost" trail shows recent damage, the heart pulses gently at low health and the stamina bar fades
## away while it is full.
## Chapter Two: a transient shield (Pebble's Stoneheart, Events.player_shield_changed) shows as a pale stone
## segment on the health bar, right after the health fill (over its end when health is full). It eases in and
## out (never flashes) and is gone at 0. The bar's maximum is Stats.effective_max_hp() when that is larger than
## the health node's max_hp.

const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const Palette := preload("res://src/art/palette.gd")
const Stats := preload("res://src/core/stats.gd")

const SHIELD_COLOR := Color("dde6ee")          # pale stone, reads on the dark track and over the red fill
const SHIELD_EDGE := Color("8fa3b8")

const BAR_W := 360.0
const BAR_H := 30.0
const ST_W := 290.0
const ST_H := 18.0

var hp := 100.0
var max_hp := 100.0
var stamina := 100.0
var max_stamina := 100.0
var _shown_hp := 100.0
var _ghost_hp := 100.0
var _ghost_hold := 0.0
var _shown_st := 100.0
var _st_alpha := 0.0
var _full_time := 0.0
var _t := 0.0
var _heal_glow := 0.0
var _first := true
var _last_sig := Vector4(-1, -1, -1, -1)
## Current shield (hp it will absorb) and the eased value drawn.
var shield := 0.0
var _shown_shield := 0.0
var _last_shield_sig := -1.0

var _heart: Texture2D
var _bolt: Texture2D
var _sb_frame: StyleBoxFlat
var _sb_track: StyleBoxFlat
var _sb_hp: StyleBoxFlat
var _sb_ghost: StyleBoxFlat
var _sb_st: StyleBoxFlat
var _sb_st_frame: StyleBoxFlat
var _sb_st_track: StyleBoxFlat
var _sb_gloss: StyleBoxFlat
var _sb_shield: StyleBoxFlat
var _st_frame_bg := Color.WHITE
var _st_frame_border := Color.WHITE
var _st_frame_shadow := Color.WHITE
var _st_track_bg := Color.WHITE


func _ready() -> void:
	custom_minimum_size = Vector2(470, 104)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heart = IconFactory.icon("ui_heart", Palette.UI_HEALTH, 96)
	_bolt = IconFactory.icon("ui_stamina", Color.WHITE, 96)
	_sb_frame = ThemeFactory.box(Color(ThemeFactory.PAPER_LIGHT, 0.96), 17, 3, Color(ThemeFactory.INK, 0.9), 0, 6, Vector2(0, 3), Color(0.1, 0.05, 0.08, 0.3))
	_sb_track = ThemeFactory.box(Color("5a4650"), 12)
	_sb_hp = ThemeFactory.box(Palette.UI_HEALTH, 12)
	_sb_ghost = ThemeFactory.box(Color("f6c3b8"), 12)
	_sb_st = ThemeFactory.box(Palette.UI_STAMINA, 9)
	_sb_st_frame = ThemeFactory.box(Color(ThemeFactory.PAPER_LIGHT, 0.96), 12, 3, Color(ThemeFactory.INK, 0.9), 0, 4, Vector2(0, 2), Color(0.1, 0.05, 0.08, 0.3))
	_sb_st_track = ThemeFactory.box(Color("5a4650"), 8)
	_sb_gloss = ThemeFactory.box(Color(1, 1, 1, 0.32), 5)
	_sb_shield = ThemeFactory.box(Color(SHIELD_COLOR, 0.88), 12, 2, Color(SHIELD_EDGE, 0.95))
	_st_frame_bg = _sb_st_frame.bg_color
	_st_frame_border = _sb_st_frame.border_color
	_st_frame_shadow = _sb_st_frame.shadow_color
	_st_track_bg = _sb_st_track.bg_color
	if not Events.player_shield_changed.is_connected(_on_shield_changed):
		Events.player_shield_changed.connect(_on_shield_changed)
	shield = Stats.player_shield()


func _on_shield_changed(amount: float) -> void:
	shield = maxf(amount, 0.0)


func _process(delta: float) -> void:
	_t += delta
	_read_values()
	if _first:
		_first = false
		_shown_hp = hp
		_ghost_hp = hp
		_shown_st = stamina
		_shown_shield = shield
	# health easing + ghost trail
	if hp > _shown_hp + 0.5:
		_heal_glow = 1.0
	_shown_hp = lerpf(_shown_hp, hp, clampf(delta * 10.0, 0.0, 1.0))
	if _ghost_hp < _shown_hp:
		_ghost_hp = _shown_hp
	if hp < _ghost_hp - 0.1:
		_ghost_hold -= delta
		if _ghost_hold <= 0.0:
			_ghost_hp = lerpf(_ghost_hp, hp, clampf(delta * 3.0, 0.0, 1.0))
	else:
		_ghost_hold = 0.55
	_heal_glow = maxf(_heal_glow - delta * 1.6, 0.0)
	# shield: eases like the health fill, and is simply gone once it has run out
	_shown_shield = lerpf(_shown_shield, shield, clampf(delta * 10.0, 0.0, 1.0))
	if shield <= 0.0 and _shown_shield < 0.5:
		_shown_shield = 0.0
	# stamina: fade when full
	_shown_st = lerpf(_shown_st, stamina, clampf(delta * 12.0, 0.0, 1.0))
	if stamina >= max_stamina - 0.5:
		_full_time += delta
	else:
		_full_time = 0.0
	var target_a := 0.0 if _full_time > 1.4 else 1.0
	_st_alpha = move_toward(_st_alpha, target_a, delta * (3.0 if target_a > _st_alpha else 1.6))
	# redraw only when something visible changed (bars ease, pulse animates at low health)
	var low := hp < max_hp * 0.3 and hp > 0.0
	var sig := Vector4(roundf(_shown_hp * 4.0), roundf(_ghost_hp * 4.0), roundf(_shown_st * 4.0), roundf(_st_alpha * 50.0 + _heal_glow * 20.0))
	var shield_sig := roundf(_shown_shield * 4.0)
	if sig != _last_sig or low or shield_sig != _last_shield_sig:
		_last_sig = sig
		_last_shield_sig = shield_sig
		queue_redraw()


func _read_values() -> void:
	var p: Node = Game.player
	var h: Node = null
	if p != null and is_instance_valid(p):
		var hv: Variant = p.get("health")
		if hv is Node:
			h = hv
	if h != null and is_instance_valid(h):
		hp = float(h.get("hp"))
		max_hp = maxf(float(h.get("max_hp")), 1.0)
		# The player's own health node is the source of truth for the shield (a new player after an area
		# change or a respawn starts without one, and emits nothing about it).
		var sv0: Variant = h.get("shield")
		if sv0 is float or sv0 is int:
			shield = maxf(float(sv0), 0.0)
	else:
		hp = float(GameState.player.get("hp", 100.0))
		max_hp = maxf(float(GameState.player.get("max_hp", 100.0)), 1.0)
	max_hp = maxf(max_hp, Stats.effective_max_hp())
	max_stamina = maxf(float(GameState.player.get("max_stamina", 100.0)), 1.0)
	if p != null and is_instance_valid(p):
		var sv: Variant = p.get("stamina")
		if sv is float or sv is int:
			stamina = float(sv)
		else:
			stamina = float(GameState.player.get("stamina", max_stamina))
	else:
		stamina = float(GameState.player.get("stamina", max_stamina))
	hp = clampf(hp, 0.0, max_hp)
	stamina = clampf(stamina, 0.0, max_stamina)


func _draw() -> void:
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	# --- health ---
	var icon_c := Vector2(34, 36)
	var pulse := 0.0
	if ratio < 0.3 and hp > 0.0:
		var calm := bool(Settings.get_value("reduce_flashing"))
		pulse = (sin(_t * (4.0 if not calm else 2.0)) * 0.5 + 0.5) * (0.12 if not calm else 0.05)
	var isz := 64.0 * (1.0 + pulse)
	var bar := Rect2(Vector2(62, 21), Vector2(BAR_W, BAR_H))
	draw_style_box(_sb_frame, bar.grow(4))
	draw_style_box(_sb_track, bar.grow(-2))
	var inner := bar.grow(-4)
	var gw := inner.size.x * clampf(_ghost_hp / max_hp, 0.0, 1.0)
	if gw > 2.0:
		draw_style_box(_sb_ghost, Rect2(inner.position, Vector2(gw, inner.size.y)))
	var fw := inner.size.x * clampf(_shown_hp / max_hp, 0.0, 1.0)
	if fw > 2.0:
		var col := Palette.UI_HEALTH.lerp(Color("ffd0c0"), _heal_glow * 0.5)
		_sb_hp.bg_color = col
		draw_style_box(_sb_hp, Rect2(inner.position, Vector2(fw, inner.size.y)))
		# glossy highlight along the top of the fill
		if fw > 16.0:
			draw_style_box(_sb_gloss, Rect2(inner.position + Vector2(6, 3), Vector2(fw - 12.0, 5)))
	var shield_rect := shield_segment(inner, _shown_hp, _shown_shield, max_hp)
	if shield_rect.size.x > 2.0:
		draw_style_box(_sb_shield, shield_rect)
	var f := ThemeFactory.font("body_bold")
	var txt := "%d" % int(ceil(hp))
	if shield >= 0.5:
		txt = "%d  +%d" % [int(ceil(hp)), int(ceil(shield))]
	var tp := Vector2(bar.position.x, bar.position.y + bar.size.y - 7)
	draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x - 12.0, 21, 6, Color(ThemeFactory.INK, 0.9))
	draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_RIGHT, bar.size.x - 12.0, 21, ThemeFactory.CREAM)
	draw_texture_rect(_heart, Rect2(icon_c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false)
	# --- stamina ---
	if _st_alpha > 0.01:
		var a := _st_alpha
		var st_bar := Rect2(Vector2(68, 70), Vector2(ST_W, ST_H))
		_sb_st_frame.bg_color = Color(_st_frame_bg, _st_frame_bg.a * a)
		_sb_st_frame.border_color = Color(_st_frame_border, _st_frame_border.a * a)
		_sb_st_frame.shadow_color = Color(_st_frame_shadow, _st_frame_shadow.a * a)
		draw_style_box(_sb_st_frame, st_bar.grow(3))
		_sb_st_track.bg_color = Color(_st_track_bg, _st_track_bg.a * a)
		draw_style_box(_sb_st_track, st_bar.grow(-1))
		var si := st_bar.grow(-3)
		var sw := si.size.x * clampf(_shown_st / max_stamina, 0.0, 1.0)
		if sw > 2.0:
			var sc := Palette.UI_STAMINA
			if stamina < max_stamina * 0.2:
				sc = sc.lerp(Palette.UI_WARN, 0.6)
			sc.a = a
			_sb_st.bg_color = sc
			draw_style_box(_sb_st, Rect2(si.position, Vector2(sw, si.size.y)))
		draw_texture_rect(_bolt, Rect2(Vector2(36, 58), Vector2(42, 42)), false, Color(1, 1, 1, a))


## Where the pale shield segment sits inside the health bar's inner rect: right after the health fill, as
## wide as the shield in bar units; when that would run past the end it is pushed back over the end of the
## fill instead (a full-health shield still shows). Empty Rect2 when there is no shield. Pure; see tests.
static func shield_segment(inner: Rect2, shown_hp: float, shown_shield: float, bar_max: float) -> Rect2:
	if shown_shield <= 0.0 or bar_max <= 0.0 or inner.size.x <= 0.0:
		return Rect2()
	var w := inner.size.x * clampf(shown_shield / bar_max, 0.0, 1.0)
	var x := inner.size.x * clampf(shown_hp / bar_max, 0.0, 1.0)
	x = clampf(x, 0.0, inner.size.x - w)
	return Rect2(inner.position + Vector2(x, 0.0), Vector2(w, inner.size.y))

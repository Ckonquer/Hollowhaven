extends RefCounted
## Small widget builders shared by the HUD, panels and the title screen, so every screen is built
## from the same themed parts (and every button makes the same gentle sounds).
##   const Kit := preload("res://src/ui/ui_kit.gd")
##   box.add_child(Kit.button("Resume", _on_resume, "AccentButton"))

const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")


static func label(text: String, variation: String = "", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Word-wrapped label; min_width keeps containers from collapsing it to one word per line.
static func wrap_label(text: String, variation: String = "", min_width: float = 200.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, variation, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = min_width
	return l


static func rich(bbcode: String = "", min_width: float = 200.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size.x = min_width
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bbcode
	return r


## Themed button with click / hover sounds. `cb` is called on press (optional).
static func button(text: String, cb: Callable = Callable(), variation: String = "", icon_tex: Texture2D = null) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if icon_tex != null:
		b.icon = icon_tex
		b.expand_icon = false
	if cb.is_valid():
		b.pressed.connect(cb)
	hook_sounds(b)
	return b


## Round close ("X") button.
static func close_button(cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "RoundButton"
	b.icon = IconFactory.glyph("close", 34, 34)
	b.tooltip_text = "Close"
	b.custom_minimum_size = Vector2(52, 52)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(cb)
	hook_sounds(b, "ui_close")
	return b


static func hook_sounds(b: BaseButton, click: String = "ui_click") -> void:
	b.pressed.connect(func() -> void: Audio.play_ui(click))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.play_ui("ui_hover", -12.0))


static func icon_rect(tex: Texture2D, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func margin(m: Variant) -> MarginContainer:
	var mc := MarginContainer.new()
	var arr: Array = m if m is Array else [m, m, m, m]
	mc.add_theme_constant_override("margin_left", int(arr[0]))
	mc.add_theme_constant_override("margin_top", int(arr[1]))
	mc.add_theme_constant_override("margin_right", int(arr[2]))
	mc.add_theme_constant_override("margin_bottom", int(arr[3]))
	return mc


static func panel(variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	return p


static func spacer(w: float = 0.0, h: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func separator() -> HSeparator:
	return HSeparator.new()


## Row of bond hearts (filled up to `level`).
static func hearts(level: int, max_level: int = 5, size: float = 26.0) -> HBoxContainer:
	var h := hbox(2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in max_level:
		var tex := IconFactory.icon("ui_heart", Color("ff8fa8"), 48) if i < level else IconFactory.icon("ui_heart_empty", Color.WHITE, 48)
		h.add_child(icon_rect(tex, size))
	return h


## Little keyboard key cap ("E", "Tab", "Left Mouse").
static func key_cap(text: String) -> PanelContainer:
	var p := panel("KeyCap")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, "KeyCapLabel", HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size.x = 18
	p.add_child(l)
	return p


## Key caps for every binding of an action (e.g. [Tab] [I]).
static func action_caps(action: String, max_caps: int = 2) -> HBoxContainer:
	var h := hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := 0
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if n >= max_caps:
				break
			h.add_child(key_cap(Settings.event_label(ev)))
			n += 1
	if n == 0:
		h.add_child(key_cap("-"))
	return h


static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.add_child(child)
	return c


## Full-rect helper for Controls created in code.
static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c


## Kills a previous tween stored in `holder[key]` and returns a fresh one bound to `node`.
static func retween(node: Node, holder: Dictionary, key: String) -> Tween:
	var old: Variant = holder.get(key, null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := node.create_tween()
	holder[key] = tw
	return tw


## Connects `cb` to a global signal (e.g. Events.settings_changed) for as long as `owner` lives in the
## tree; disconnects automatically when it leaves (lambdas made in static funcs never auto-disconnect).
static func listen(owner: Node, sig: Signal, cb: Callable) -> void:
	if not sig.is_connected(cb):
		sig.connect(cb)
	owner.tree_exiting.connect(func() -> void:
		if sig.is_connected(cb):
			sig.disconnect(cb), CONNECT_ONE_SHOT)

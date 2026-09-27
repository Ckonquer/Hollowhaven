extends CanvasLayer
## Debug contact sheet of every procedural icon (QA only):
##   tools/godot.sh --path game --windowed --resolution 1600x900 -- --preview=res://src/ui/debug/icon_sheet.gd --preview-shots=1 --shot-dir=<dir>
## Also works headless: it saves the raw icon images to --shot-dir when --icon-dump is given.

const IconFactory := preload("res://src/ui/icon_factory.gd")
const Palette := preload("res://src/art/palette.gd")


func _ready() -> void:
	layer = 10
	var bg := ColorRect.new()
	bg.color = Palette.UI_PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var t0 := Time.get_ticks_msec()
	var grid := GridContainer.new()
	grid.columns = 14
	grid.position = Vector2(20, 16)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	var ids: Array = []
	for item_id in ItemDB.all_item_ids():
		ids.append(item_id)
	var n := 0
	for item_id in ids:
		_cell(grid, IconFactory.item_icon(item_id), String(item_id), 96)
		n += 1
	for extra in IconFactory.EXTRA_ICONS:
		_cell(grid, IconFactory.icon(extra, Palette.UI_ACCENT if extra == "unknown" else Color.WHITE), extra, 96)
		n += 1
	for pid in IconFactory.PORTRAITS:
		_cell(grid, IconFactory.portrait(pid), "portrait_" + pid, 96)
	var small := HBoxContainer.new()
	small.position = Vector2(20, 1000)
	add_child(small)
	for item_id in ids.slice(0, 24):
		var tr := TextureRect.new()
		tr.texture = IconFactory.item_icon(item_id)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(48, 48)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		small.add_child(tr)
	for g in ["box_off", "box_on", "switch_off", "switch_on", "knob", "arrow_down", "radio_on", "leaf"]:
		var tr2 := TextureRect.new()
		tr2.texture = IconFactory.glyph(g, 64 if g.begins_with("switch") else 40, 36 if g.begins_with("switch") else 40)
		small.add_child(tr2)
	print("IconSheet: %d icons in %d ms" % [n, Time.get_ticks_msec() - t0])
	if Debug.has_arg("icon-dump"):
		var dir := Debug.arg("shot-dir", "user://icons")
		DirAccess.make_dir_recursive_absolute(dir)
		for item_id in ids:
			IconFactory.render(IconFactory.item_icon_id(item_id), IconFactory.item_color(item_id), 96).save_png(dir.path_join("icon_%s.png" % item_id))


func _cell(grid: GridContainer, tex: Texture2D, label: String, sz: int) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = Vector2(sz, sz)
	v.add_child(tr)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Palette.UI_INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(sz, 0)
	l.clip_text = true
	v.add_child(l)
	grid.add_child(v)

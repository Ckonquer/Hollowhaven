extends "res://src/ui/panels/panel_base.gd"
## Wardrobe (in-game, full-screen: pauses the world). Krystal's look editor with a rotating preview:
## hair style, hair colour, skin, eyes, complete outfits, single pieces and clothing colours; owned vs
## locked clothes (locked ones say how to earn them), three named presets (save / wear / rename), the
## "Show equipped armor" option and a reset to her Chapter One look.
## Styling is free and COSMETIC ONLY: it writes GameState.appearance (+ Events.appearance_changed) and never
## touches equipment, stats or the inventory. Every change is worn at once; "Undo changes" returns to the
## look she had when the panel opened. Unknown ids from a newer version stay in the save untouched (only the
## keys the player changes are written) and are reported under the editor.
## Opened from the pause menu, the Ward Stone ("Change your look"), wardrobe / vanity mirror furniture and
## the one-time "Your wardrobe is ready" notice (ui_root). args: {"category": "outfit"|"hair"|...}.
## This file also holds the pieces the "Meet Krystal" creation screen shares:
##   Looks      - pure look / ownership / preset logic (tests call it directly)
##   LookEditor - category tabs + option grid (keyboard: arrows/Enter, Q/E or PageUp/PageDown = category)

const Preview := preload("res://src/ui/widgets/avatar_preview.gd")
const AppearanceData := preload("res://data/appearance.gd")
## Optional goal "A Look of Your Own" (data/optional_goals.gd): set when a look is confirmed at creation or
## changed here. The optional log pays its reward; the UI only sets the flag.
const LOOK_FLAG := "c1x_look_chosen"
const PRESET_NAME_MAX := 40
const COSMETIC_NOTE := "Styling is always free. Clothes are cosmetic only: they never change Krystal's stats, armor or pockets."

var editor: LookEditor
var preview: Control
var status_l: Label
var missing_l: Label
var armor_btn: CheckButton
var undo_btn: Button
var reset_btn: Button
var _opened_raw: Dictionary = {}
var _preset_rows: Array = []        # per slot: {card, name, edit, wear, save, rename}
var _renaming: int = -1
var _done_btn: Button


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	title = "Wardrobe"
	window_min = Vector2(1790, 0)


func _build() -> void:
	_opened_raw = Looks.raw_appearance()
	var head := Kit.hbox(16)
	body.add_child(head)
	var pill := Kit.panel("Pill")
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(Kit.label("Cosmetic only", "HudSmall"))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pill)
	status_l = Kit.wrap_label(COSMETIC_NOTE, "Muted", 1400)
	status_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(status_l)
	var cols := Kit.hbox(24)
	body.add_child(cols)
	# Preview
	var pc := Kit.vbox(10)
	cols.add_child(pc)
	var cur := Looks.current_look()
	preview = Preview.new()
	preview.setup({"look": cur, "size": Vector2(440, 600), "show_armor": bool(GameState.wardrobe.get("show_armor", false)),
		"equipment": GameState.equipment.duplicate()})
	pc.add_child(preview)
	pc.add_child(turn_row(preview))
	# Editor
	editor = LookEditor.new()
	editor.setup({"look": cur, "wardrobe": GameState.wardrobe, "show_locked": true, "width": 860.0,
		"height": 468.0, "columns": 3, "category": String(args.get("category", "outfit"))})
	editor.look_changed.connect(_on_look_changed)
	cols.add_child(editor)
	# Presets, armor, undo / reset
	var side := Kit.vbox(10)
	side.custom_minimum_size.x = 400
	cols.add_child(side)
	side.add_child(section_title("Saved looks"))
	for i in ItemDB.preset_slots():
		side.add_child(_make_preset_row(i))
	side.add_child(Kit.spacer(0, 4))
	side.add_child(section_title("Armor"))
	armor_btn = CheckButton.new()
	armor_btn.text = "Show equipped armor"
	armor_btn.add_theme_font_override("font", ThemeFactory.font("body_bold"))
	armor_btn.toggled.connect(_on_armor_toggled)
	Kit.hook_sounds(armor_btn)
	side.add_child(armor_btn)
	side.add_child(Kit.wrap_label("Armor protects Krystal whether it shows or not. Hide it to show off her outfit.", "Small", 390))
	side.add_child(Kit.spacer(0, 4))
	var row := Kit.hbox(10)
	side.add_child(row)
	undo_btn = Kit.button("Undo changes", _undo, "GhostButton")
	undo_btn.tooltip_text = "Go back to the look Krystal had when you opened the wardrobe."
	row.add_child(undo_btn)
	reset_btn = Kit.button("Chapter One look", _reset_legacy, "GhostButton")
	reset_btn.tooltip_text = "Krystal's original auburn side braid and explorer outfit."
	row.add_child(reset_btn)
	# Bottom
	var bottom := Kit.hbox(16)
	body.add_child(bottom)
	missing_l = Kit.wrap_label("", "WarnText", 1200)
	missing_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	missing_l.visible = false
	bottom.add_child(missing_l)
	bottom.add_child(Kit.expander())
	_done_btn = Kit.button("Done", request_close, "AccentButton")
	_done_btn.custom_minimum_size.x = 200
	bottom.add_child(_done_btn)


## "< Turn  Turn >" buttons under a preview (shared with the creation screen).
static func turn_row(pv: Control) -> HBoxContainer:
	var h := Kit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Kit.button("Turn left", func() -> void: pv.call("turn", Preview.TURN_STEP), "GhostButton")
	l.tooltip_text = "Or press <"
	h.add_child(l)
	h.add_child(Kit.label("Drag to turn", "Small"))
	var r := Kit.button("Turn right", func() -> void: pv.call("turn", -Preview.TURN_STEP), "GhostButton")
	r.tooltip_text = "Or press >"
	h.add_child(r)
	return h


## Turns a preview with the < and > keys. True if handled.
static func preview_key(pv: Control, event: InputEvent) -> bool:
	if pv == null or not (event is InputEventKey) or not event.is_pressed():
		return false
	var k := LookEditor.key_of(event as InputEventKey)
	if k == KEY_COMMA:
		pv.call("turn", Preview.TURN_STEP)
		return true
	if k == KEY_PERIOD:
		pv.call("turn", -Preview.TURN_STEP)
		return true
	return false


func refresh() -> void:
	if editor == null:
		return
	editor.set_wardrobe(GameState.wardrobe)
	var cur := Looks.current_look()
	editor.set_look(cur)
	preview.call("set_look", cur)
	armor_btn.set_pressed_no_signal(bool(GameState.wardrobe.get("show_armor", false)))
	_refresh_presets()
	var missing := Looks.missing_ids()
	missing_l.text = ("Some saved styles come from a newer version of Hollowhaven (%s). They are kept safe and shown as her classic pieces here." \
		% Looks.missing_names(missing)) if not missing.is_empty() else ""
	missing_l.visible = missing_l.text != ""
	_refresh_undo()


func reopen(p_args: Dictionary) -> void:
	var cat := String(p_args.get("category", ""))
	refresh()
	if cat != "" and editor != null:
		editor.show_category(cat)
	_focus_default.call_deferred()


func default_focus() -> Control:
	return editor.default_focus() if editor != null else _done_btn


func handle_key(event: InputEvent) -> bool:
	if editor != null and editor.handle_key(event):
		return true
	return preview_key(preview, event)


func is_capturing_input() -> bool:
	return _renaming >= 0


func on_close() -> void:
	if _renaming >= 0:
		_finish_rename(_renaming, true, false)


func _set_status(text: String) -> void:
	if status_l != null:
		status_l.text = text


func _refresh_undo() -> void:
	if undo_btn != null:
		undo_btn.disabled = Looks.same_look(Looks.raw_appearance(), _opened_raw)


func _on_look_changed(l: Dictionary) -> void:
	if Looks.wear(l):
		_set_status("Krystal is wearing her new look. Styling is free.")
	preview.call("set_look", l)
	_refresh_undo()


func _sync_from_state(msg: String) -> void:
	var cur := Looks.current_look()
	editor.set_look(cur)
	preview.call("set_look", cur)
	_refresh_undo()
	if msg != "":
		_set_status(msg)


func _undo() -> void:
	Looks.set_appearance(_opened_raw, false)
	_sync_from_state("Back to the look Krystal came in with.")


func _reset_legacy() -> void:
	Looks.reset_to_legacy()
	_sync_from_state("Krystal's Chapter One look: auburn side braid and her explorer outfit.")


func _on_armor_toggled(on: bool) -> void:
	GameState.wardrobe["show_armor"] = on
	preview.call("set_show_armor", on)
	Events.appearance_changed.emit()
	_set_status("Equipped armor will show over her outfit." if on else "Armor stays hidden. It still protects her.")


# --- Presets ------------------------------------------------------------------------------------------

func _make_preset_row(i: int) -> Control:
	var card := Kit.panel("Card")
	var v := Kit.vbox(6)
	card.add_child(v)
	var name_l := Kit.label("", "CardTitle")
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(340, 0)
	v.add_child(name_l)
	var edit := LineEdit.new()
	edit.max_length = PRESET_NAME_MAX
	edit.placeholder_text = "Name this look"
	edit.visible = false
	edit.custom_minimum_size = Vector2(340, 0)
	edit.text_submitted.connect(_on_rename_submitted.bind(i))
	edit.focus_exited.connect(_finish_rename.bind(i, true, false))   # clicking elsewhere keeps that focus
	edit.gui_input.connect(_on_rename_input.bind(i))
	v.add_child(edit)
	var btns := Kit.hbox(6)
	v.add_child(btns)
	var wear := Kit.button("Wear", _wear_preset.bind(i), "GhostButton")
	btns.add_child(wear)
	var save := Kit.button("Save here", _save_preset.bind(i), "GhostButton")
	btns.add_child(save)
	var ren := Kit.button("Rename", _start_rename.bind(i), "GhostButton")
	btns.add_child(ren)
	_preset_rows.append({"card": card, "name": name_l, "edit": edit, "wear": wear, "save": save, "rename": ren})
	return card


func _refresh_presets() -> void:
	var list := Looks.presets()
	for i in _preset_rows.size():
		var r: Dictionary = _preset_rows[i]
		var has := i < list.size()
		var name_l: Label = r["name"]
		var rec: Dictionary = list[i] if has and list[i] is Dictionary else {}
		name_l.text = String(rec.get("name", "")) if has else "Empty slot"
		name_l.theme_type_variation = "CardTitle" if has else "Muted"
		name_l.tooltip_text = name_l.text
		(r["wear"] as Button).disabled = not has
		(r["rename"] as Button).disabled = not has
		var save: Button = r["save"]
		save.disabled = i > list.size()
		save.text = "Save here"
		save.tooltip_text = "Replace this saved look with what Krystal wears now." if has else ("Save what Krystal wears now." if i == list.size() else "Fill the slot above first.")
		if _renaming != i:
			name_l.visible = true
			(r["edit"] as LineEdit).visible = false


func _wear_preset(i: int) -> void:
	var list := Looks.presets()
	if i >= list.size():
		return
	Looks.apply_preset(i)
	_sync_from_state("Wearing \"%s\"." % String((list[i] as Dictionary).get("name", "")))


func _save_preset(i: int) -> void:
	if not Looks.save_preset(i):
		Audio.play_ui("ui_error")
		return
	_refresh_presets()
	var list := Looks.presets()
	_set_status("Saved as \"%s\"." % String((list[i] as Dictionary).get("name", "")))


func _start_rename(i: int) -> void:
	var list := Looks.presets()
	if i >= list.size() or i >= _preset_rows.size():
		return
	if _renaming >= 0 and _renaming != i:
		_finish_rename(_renaming, true)
	_renaming = i
	var r: Dictionary = _preset_rows[i]
	var edit: LineEdit = r["edit"]
	edit.text = String((list[i] as Dictionary).get("name", ""))
	(r["name"] as Label).visible = false
	edit.visible = true
	edit.grab_focus()
	edit.select_all()


func _on_rename_submitted(_text: String, i: int) -> void:
	_finish_rename(i, true)


func _on_rename_input(event: InputEvent, i: int) -> void:
	if event is InputEventKey and event.is_pressed() and LookEditor.key_of(event as InputEventKey) == KEY_ESCAPE:
		_finish_rename(i, false)
		var r: Dictionary = _preset_rows[i]
		(r["edit"] as LineEdit).accept_event()


func _finish_rename(i: int, commit: bool, refocus: bool = true) -> void:
	if _renaming != i or i >= _preset_rows.size():
		return
	_renaming = -1
	var r: Dictionary = _preset_rows[i]
	var edit: LineEdit = r["edit"]
	if commit and Looks.rename_preset(i, edit.text):
		_set_status("Renamed to \"%s\"." % Looks.clean_name(edit.text))
	edit.visible = false
	(r["name"] as Label).visible = true
	_refresh_presets()
	var ren: Button = r["rename"]
	if refocus and is_inside_tree() and not _closing:
		ren.call_deferred("grab_focus")


# =========================================================================================================
## Pure look logic shared by the wardrobe and the creation screen. A "wardrobe" argument is a
## GameState.wardrobe-shaped dictionary ({"owned": [part / pattern ids], "palettes": [dye palette ids]}).
## Choice keys: "hair", "hair_color", "skin", "eyes", "outfit", a clothing slot ("upper", "lower", "shoes",
## "hat", "hair_acc", "back") or "palette.<primary|secondary|accent>".
class Looks:
	const PICK_KEYS := ["hair", "hair_color", "skin", "eyes", "upper", "lower", "shoes", "hat", "hair_acc", "back"]

	## The ownership a brand-new journey starts with (starter items only).
	static func starter_wardrobe() -> Dictionary:
		return {"owned": [], "palettes": []}

	static func _list(wardrobe: Dictionary, key: String) -> Array:
		var v: Variant = wardrobe.get(key, [])
		return v if v is Array else []

	static func owned_part(part_id: String, wardrobe: Dictionary) -> bool:
		var p := ItemDB.appearance_part(part_id)
		if p.is_empty():
			return false
		if bool(p.get("starter", false)):
			return true
		var owned := _list(wardrobe, "owned")
		var pat := String(p.get("pattern", ""))
		return owned.has(part_id) or (pat != "" and owned.has(pat))

	static func owned_swatch(swatch_id: String, wardrobe: Dictionary) -> bool:
		var s: Dictionary = ItemDB.appearance_table("swatches").get(swatch_id, {})
		if s.is_empty():
			return false
		if bool(s.get("starter", false)):
			return true
		return _list(wardrobe, "palettes").has(String(s.get("dye", "")))

	## A complete look is wearable when every piece in it is owned (earnable ones come from patterns).
	static func owned_outfit(outfit_id: String, wardrobe: Dictionary) -> bool:
		var o := ItemDB.outfit(outfit_id)
		if o.is_empty():
			return false
		if bool(o.get("starter", false)):
			return true
		var parts: Dictionary = o.get("parts", {})
		for slot in parts:
			var pid := String(parts[slot])
			if pid != "" and not owned_part(pid, wardrobe):
				return false
		return true

	## Does `value` exist for `key` at all (ignoring ownership)?
	static func exists(key: String, value: String) -> bool:
		match key:
			"hair":
				return ItemDB.appearance_table("hairstyles").has(value)
			"hair_color":
				return ItemDB.appearance_table("hair_colors").has(value)
			"skin":
				return ItemDB.appearance_table("skin_tones").has(value)
			"eyes":
				return ItemDB.appearance_table("eye_colors").has(value)
			"outfit":
				return ItemDB.appearance_table("outfits").has(value)
		if key.begins_with("palette."):
			return AppearanceData.PALETTE_CHANNELS.has(key.substr(8)) and ItemDB.appearance_table("swatches").has(value)
		if AppearanceData.SLOTS.has(key):
			if value == "":
				return AppearanceData.OPTIONAL_SLOTS.has(key)
			var p := ItemDB.appearance_part(value)
			return not p.is_empty() and String(p.get("slot", "")) == key
		return false

	## Can Krystal pick `value` for `key` with this ownership? Hair, colours of hair / skin / eyes are always
	## free; clothes and clothing colours must be owned.
	static func can_choose(key: String, value: String, wardrobe: Dictionary) -> bool:
		if not exists(key, value):
			return false
		if key == "outfit":
			return owned_outfit(value, wardrobe)
		if key.begins_with("palette."):
			return owned_swatch(value, wardrobe)
		if AppearanceData.SLOTS.has(key):
			return value == "" or owned_part(value, wardrobe)
		return true

	## Spider-like names in "how to earn" lines and their arachnophobia wording (the Weaver Matron is the
	## Hollow Mother there, as in the quest texts and the boss captions).
	const ARACHNO_WORDS := [["Weaver Matron", "Hollow Mother"], ["Matron", "Hollow Mother"], ["Weaver", "Hollow"]]

	## A pattern's `source` line, honouring the arachnophobia option (an `alt_source` in the data wins).
	static func source_text(pd: Dictionary) -> String:
		var s := String(pd.get("source", ""))
		if s == "" or not bool(Settings.get_value("arachnophobia")):
			return s
		var alt := String(pd.get("alt_source", ""))
		if alt != "":
			return alt
		for w in ARACHNO_WORDS:
			s = s.replace(String(w[0]), String(w[1]))
		return s

	## How to earn a locked choice ("" when it is not earnable / already owned).
	static func how_to_earn(key: String, value: String, wardrobe: Dictionary = {}) -> String:
		if key.begins_with("palette."):
			var s: Dictionary = ItemDB.appearance_table("swatches").get(value, {})
			var dye := ItemDB.dye_palette(String(s.get("dye", "")))
			return "Mix %s at the Loom to unlock this colour." % String(dye.get("name", "a dye")) if not dye.is_empty() else ""
		if key == "outfit":
			var o := ItemDB.outfit(value)
			var unlock: Dictionary = o.get("unlock", {})
			var out: Array = []
			for pat in unlock.get("patterns", []):
				var pd := ItemDB.pattern(String(pat))
				var missing := false
				for pid in pd.get("parts", []):
					if not owned_part(String(pid), wardrobe):
						missing = true
				if missing and source_text(pd) != "":
					out.append(source_text(pd))
			return ("How to earn: " + " ".join(PackedStringArray(out))) if not out.is_empty() else ""
		if AppearanceData.SLOTS.has(key):
			var p := ItemDB.appearance_part(value)
			var src := source_text(ItemDB.pattern(String(p.get("pattern", ""))))
			return ("How to earn: " + src) if src != "" else ""
		return ""

	## The value of a choice key in a look ("" if absent).
	static func value_of(look: Dictionary, key: String) -> String:
		if key.begins_with("palette."):
			var pal: Variant = look.get("palette", {})
			return String((pal as Dictionary).get(key.substr(8), "")) if pal is Dictionary else ""
		var v: Variant = look.get(key, "")
		return String(v) if (v is String or v is StringName) else ""

	## A copy of `look` with one choice changed (no ownership check: see can_choose).
	static func with_choice(look: Dictionary, key: String, value: String) -> Dictionary:
		if key == "outfit":
			return with_outfit(look, value)
		var out := look.duplicate(true)
		if key.begins_with("palette."):
			var pal: Dictionary = (out.get("palette") as Dictionary).duplicate(true) if out.get("palette") is Dictionary else {}
			pal[key.substr(8)] = value
			out["palette"] = pal
		else:
			out[key] = value
		return out

	## Applies a complete outfit: every clothing slot + the palette, never hair, skin or eyes.
	static func with_outfit(look: Dictionary, outfit_id: String) -> Dictionary:
		var o := ItemDB.outfit(outfit_id)
		var out := look.duplicate(true)
		if o.is_empty():
			return out
		var parts: Dictionary = o.get("parts", {})
		for slot in AppearanceData.SLOTS:
			out[slot] = String(parts.get(slot, ""))
		out["palette"] = (o.get("palette", {}) as Dictionary).duplicate(true)
		out["outfit"] = outfit_id
		return out

	## Deep comparison (key order does not matter; ints and floats compare by value).
	static func same_look(a: Variant, b: Variant) -> bool:
		if a is Dictionary and b is Dictionary:
			var da: Dictionary = a
			var db: Dictionary = b
			if da.size() != db.size():
				return false
			for k in da:
				if not db.has(k) or not same_look(da[k], db[k]):
					return false
			return true
		if a is Array and b is Array:
			var aa: Array = a
			var ab: Array = b
			if aa.size() != ab.size():
				return false
			for i in aa.size():
				if not same_look(aa[i], ab[i]):
					return false
			return true
		if (a is String or a is StringName) and (b is String or b is StringName):
			return String(a) == String(b)
		if (a is int or a is float) and (b is int or b is float):
			return is_equal_approx(float(a), float(b))
		return typeof(a) == typeof(b) and a == b

	## The saved look with the player's edits written in: only keys whose value differs from what was
	## SHOWN are written, so ids this version doesn't know (shown as defaults) survive untouched, and so do
	## extra keys a newer version added.
	static func merge_edit(raw: Dictionary, shown: Dictionary, edited: Dictionary) -> Dictionary:
		var out := raw.duplicate(true)
		for k in PICK_KEYS + ["outfit"]:
			if not edited.has(k):
				continue
			var ev := value_of(edited, k)
			if ev != value_of(shown, k) or not out.has(k):
				out[k] = ev
		var rp: Dictionary = (out.get("palette") as Dictionary).duplicate(true) if out.get("palette") is Dictionary else {}
		var ep: Variant = edited.get("palette", null)
		if ep is Dictionary:
			for ch in AppearanceData.PALETTE_CHANNELS:
				if not (ep as Dictionary).has(ch):
					continue
				var ev2 := String((ep as Dictionary)[ch])
				if ev2 != value_of(shown, "palette." + String(ch)) or not rp.has(ch):
					rp[ch] = ev2
			out["palette"] = rp
		return out

	## A friendly default name for a saved look: "Strawberry Picnic · Twin Braids".
	static func describe(look: Dictionary) -> String:
		var l: Dictionary = ItemDB.sanitize_look(look)["look"]
		var first := ""
		var o := ItemDB.outfit(String(l.get("outfit", "")))
		if not o.is_empty():
			var same := true
			var parts: Dictionary = o.get("parts", {})
			for slot in AppearanceData.SLOTS:
				if String(parts.get(slot, "")) != String(l.get(slot, "")):
					same = false
			if same:
				first = String(o.get("name", ""))
		if first == "":
			first = String(ItemDB.appearance_part(String(l.get("upper", ""))).get("name", "Her own style"))
		var hair := String((ItemDB.appearance_table("hairstyles").get(String(l.get("hair", "")), {}) as Dictionary).get("name", ""))
		return clean_name(first + ("  ·  " + hair if hair != "" else ""))

	static func clean_name(n: String) -> String:
		var s := n.replace("\n", " ").replace("\t", " ").strip_edges()
		return s.substr(0, PRESET_NAME_MAX).strip_edges()

	# --- GameState-bound ------------------------------------------------------------------------------

	static func raw_appearance() -> Dictionary:
		var a: Variant = GameState.appearance
		return (a as Dictionary).duplicate(true) if a is Dictionary else {}

	## What Krystal wears as the game can show it (unknown ids -> safe defaults).
	static func current_look() -> Dictionary:
		return ItemDB.sanitize_look(GameState.appearance)["look"]

	## Saved ids this version can't show ("key=id" strings, see ItemDB.sanitize_look).
	static func missing_ids() -> Array:
		return ItemDB.sanitize_look(GameState.appearance)["missing"]

	## Friendly names of the options behind missing ids ("Top, Main colour"), each once, in order.
	const MISSING_NAMES := {"hair": "Hair style", "hair_color": "Hair colour", "skin": "Skin", "eyes": "Eyes",
		"upper": "Top", "lower": "Skirt or trousers", "shoes": "Shoes", "hat": "Hat", "hair_acc": "Hair accessory",
		"back": "Back accessory", "palette.primary": "Main colour", "palette.secondary": "Second colour",
		"palette.accent": "Accent colour", "palette": "Colours", "look": "Look"}

	static func missing_names(missing: Array) -> String:
		var out: PackedStringArray = []
		for m in missing:
			var key := String(m).get_slice("=", 0)
			var n := String(MISSING_NAMES.get(key, key.capitalize()))
			if not out.has(n):
				out.append(n)
		return ", ".join(out)

	## Replaces GameState.appearance (when different), marks "A Look of Your Own" if asked, and emits
	## Events.appearance_changed. Never touches equipment or items. True if something changed.
	static func set_appearance(raw: Dictionary, mark_chosen: bool) -> bool:
		if same_look(raw, GameState.appearance):
			return false
		GameState.appearance = raw.duplicate(true)
		if mark_chosen:
			GameState.set_flag(LOOK_FLAG, true)
		Events.appearance_changed.emit()
		return true

	## Wears an edited look (a full look dictionary as the editor holds it). Free; true if it changed.
	static func wear(edited: Dictionary) -> bool:
		return set_appearance(merge_edit(raw_appearance(), current_look(), edited), true)

	## Back to the Chapter One look (extra keys from a newer version are kept).
	static func reset_to_legacy() -> bool:
		var raw := raw_appearance()
		var legacy := ItemDB.legacy_look()
		for k in legacy:
			raw[k] = (legacy[k] as Dictionary).duplicate(true) if legacy[k] is Dictionary else legacy[k]
		return set_appearance(raw, true)

	static func presets() -> Array:
		var p: Variant = GameState.wardrobe.get("presets", [])
		return p if p is Array else []

	## Saves `look` (default: what she wears now, kept verbatim) into preset slot `index` (0-based; a new
	## preset may only fill the first empty slot). An empty name keeps a name the player gave, or describes
	## the look. False when the slot is out of range.
	static func save_preset(index: int, preset_name: String = "", look: Variant = null) -> bool:
		var list: Array = presets().duplicate(true)
		if index < 0 or index >= ItemDB.preset_slots() or index > list.size():
			return false
		var l: Dictionary = (look as Dictionary).duplicate(true) if look is Dictionary else raw_appearance()
		var n := clean_name(preset_name)
		var auto := n == ""
		var rec: Dictionary = (list[index] as Dictionary).duplicate(true) if index < list.size() and list[index] is Dictionary else {}
		if auto and not rec.is_empty() and not bool(rec.get("auto", true)):
			n = String(rec.get("name", ""))   # the player named this slot: keep it
			auto = false
		if n == "":
			n = describe(l)
			auto = true
		rec["name"] = n
		rec["look"] = l
		rec["auto"] = auto
		if index < list.size():
			list[index] = rec
		else:
			list.append(rec)
		GameState.wardrobe["presets"] = list
		return true

	static func rename_preset(index: int, preset_name: String) -> bool:
		var list: Array = presets().duplicate(true)
		var n := clean_name(preset_name)
		if index < 0 or index >= list.size() or n == "" or not (list[index] is Dictionary):
			return false
		var rec: Dictionary = list[index]
		rec["name"] = n
		rec["auto"] = false
		GameState.wardrobe["presets"] = list
		return true

	## Wears a saved look. Anything in it Krystal doesn't own (or that this version doesn't know) keeps what
	## she wears now; the preset itself is never changed. False when there is no such preset.
	static func apply_preset(index: int) -> bool:
		var list := presets()
		if index < 0 or index >= list.size() or not (list[index] is Dictionary):
			return false
		var pl: Variant = (list[index] as Dictionary).get("look")
		if not (pl is Dictionary):
			return false
		var target: Dictionary = pl
		var edited := current_look()
		for k in PICK_KEYS:
			var v := value_of(target, k)
			if target.has(k) and can_choose(k, v, GameState.wardrobe):
				edited[k] = v
		for ch in AppearanceData.PALETTE_CHANNELS:
			var v2 := value_of(target, "palette." + String(ch))
			if can_choose("palette." + String(ch), v2, GameState.wardrobe):
				edited = with_choice(edited, "palette." + String(ch), v2)
		var oid := value_of(target, "outfit")
		if ItemDB.outfit(oid).size() > 0:
			edited["outfit"] = oid
		wear(edited)
		return true


# =========================================================================================================
## The look editor: category tabs (Hair / Hair Colour / Skin / Eyes / Outfits / Pieces / Colours), a
## sub-row for the clothing slot or colour channel, a grid of option tiles and an info line. Locked options
## are shown (with a lock and how to earn them) when `show_locked`, and pressing one never selects it.
##   var ed := LookEditor.new(); ed.setup({"look": look, "wardrobe": w, "show_locked": true, "width": 900.0})
##   ed.look_changed.connect(func(l): ...)
class LookEditor extends VBoxContainer:
	signal look_changed(look: Dictionary)

	const CATEGORIES := [["hair", "Hair"], ["hair_color", "Hair Colour"], ["skin", "Skin"], ["eyes", "Eyes"],
		["outfit", "Outfits"], ["pieces", "Pieces"], ["colours", "Colours"]]
	const PIECE_SLOTS := [["upper", "Tops"], ["lower", "Skirts & Trousers"], ["shoes", "Shoes"], ["hat", "Hats"],
		["hair_acc", "Hair Accessory"], ["back", "Back"]]
	const CHANNELS := [["primary", "Main colour"], ["secondary", "Second colour"], ["accent", "Accent"]]
	const SLOT_NAMES := {"upper": "Top", "lower": "Skirt, trousers or dress", "shoes": "Shoes", "hat": "Hat",
		"hair_acc": "Hair accessory", "back": "Back accessory"}
	const BLURBS := {
		"hair": "Eight hairstyles. Hair is always free to change.",
		"hair_color": "Pick any hair colour, any time.",
		"skin": "Choose Krystal's skin tone.",
		"eyes": "Choose Krystal's eye colour.",
		"outfit": "Complete looks change her clothes and colours, never her hair or face. Clothes are cosmetic only.",
		"pieces": "Mix single pieces. Clothes are cosmetic only: armor protects her whatever she wears.",
		"colours": "Clothing colours. Dyes mixed at the Loom add more.",
	}

	var look: Dictionary = {}
	var wardrobe: Dictionary = {}
	var show_locked: bool = true
	var width: float = 1000.0
	var list_height: float = 460.0
	var columns: int = 3
	var category: String = "outfit"
	var piece_slot: String = "upper"
	var channel: String = "primary"
	var tab_row: HFlowContainer
	var sub_row: HBoxContainer
	var scroll: ScrollContainer
	var grid: GridContainer
	var info: Label
	var tiles: Dictionary = {}           # option id -> Button (the grid on screen)
	var _tab_buttons: Dictionary = {}
	var _sub_buttons: Dictionary = {}

	func setup(p: Dictionary) -> void:
		look = ItemDB.sanitize_look(p.get("look", {}))["look"]
		var w: Variant = p.get("wardrobe", {})
		wardrobe = (w as Dictionary).duplicate(true) if w is Dictionary else {}
		show_locked = bool(p.get("show_locked", true))
		width = float(p.get("width", width))
		list_height = float(p.get("height", list_height))
		columns = maxi(int(p.get("columns", columns)), 1)
		var cat := String(p.get("category", category))
		category = cat if _valid_category(cat) else "outfit"

	static func key_of(ev: InputEventKey) -> int:
		return int(ev.physical_keycode) if int(ev.physical_keycode) != 0 else int(ev.keycode)

	static func _valid_category(cat: String) -> bool:
		for c in CATEGORIES:
			if String(c[0]) == cat:
				return true
		return false

	func _ready() -> void:
		add_theme_constant_override("separation", 10)
		custom_minimum_size.x = width
		tab_row = HFlowContainer.new()
		tab_row.add_theme_constant_override("h_separation", 8)
		tab_row.add_theme_constant_override("v_separation", 8)
		add_child(tab_row)
		var group := ButtonGroup.new()
		for c in CATEGORIES:
			var b := Kit.button(String(c[1]), show_category.bind(String(c[0])), "TabLike")
			b.toggle_mode = true
			b.button_group = group
			b.add_theme_font_size_override("font_size", 22)
			tab_row.add_child(b)
			_tab_buttons[String(c[0])] = b
		sub_row = Kit.hbox(8)
		add_child(sub_row)
		scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(width, list_height)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		add_child(scroll)
		var gm := Kit.margin([4, 4, 14, 4])
		gm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(gm)
		grid = GridContainer.new()
		grid.columns = columns
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gm.add_child(grid)
		var card := Kit.panel("Inset")
		card.custom_minimum_size = Vector2(width, 84)
		add_child(card)
		info = Kit.wrap_label("", "Small", width - 40.0)
		card.add_child(info)
		show_category(category)

	func categories() -> Array:
		var out: Array = []
		for c in CATEGORIES:
			out.append(String(c[0]))
		return out

	## The look key the grid on screen edits.
	func grid_key() -> String:
		match category:
			"pieces":
				return piece_slot
			"colours":
				return "palette." + channel
		return category

	func show_category(cat: String) -> void:
		category = cat if _valid_category(cat) else "outfit"
		for id in _tab_buttons:
			(_tab_buttons[id] as Button).set_pressed_no_signal(String(id) == category)
		_build_sub_row()
		_build_grid()

	func cycle_category(step: int) -> void:
		var ids := categories()
		var i := ids.find(category)
		show_category(String(ids[wrapi(i + step, 0, ids.size())]))
		var f := default_focus()
		if f != null and f.is_inside_tree():
			f.grab_focus()

	func set_piece_slot(slot: String) -> void:
		piece_slot = slot if AppearanceData.SLOTS.has(slot) else "upper"
		category = "pieces"
		_mark_sub()
		_build_grid()

	func set_channel(ch: String) -> void:
		channel = ch if AppearanceData.PALETTE_CHANNELS.has(ch) else "primary"
		category = "colours"
		_mark_sub()
		_build_grid()

	func set_look(l: Dictionary) -> void:
		look = ItemDB.sanitize_look(l)["look"]
		_sync_selection()

	## New ownership (rebuilds the grid only when owned pieces or dyes changed).
	func set_wardrobe(w: Dictionary) -> void:
		var same := Looks.same_look(w.get("owned", []), wardrobe.get("owned", [])) \
			and Looks.same_look(w.get("palettes", []), wardrobe.get("palettes", []))
		wardrobe = w.duplicate(true)
		if grid != null and not same:
			_build_grid()

	func _build_sub_row() -> void:
		if sub_row == null:
			return
		for c in sub_row.get_children():
			sub_row.remove_child(c)
			c.queue_free()
		_sub_buttons.clear()
		var items: Array = PIECE_SLOTS if category == "pieces" else (CHANNELS if category == "colours" else [])
		sub_row.visible = not items.is_empty()
		var group := ButtonGroup.new()
		for it in items:
			var id := String(it[0])
			var cb := set_piece_slot.bind(id) if category == "pieces" else set_channel.bind(id)
			var b := Kit.button(String(it[1]), cb, "TabLike")
			b.toggle_mode = true
			b.button_group = group
			b.add_theme_font_size_override("font_size", 20)
			sub_row.add_child(b)
			_sub_buttons[id] = b
		_mark_sub()

	func _mark_sub() -> void:
		var cur := piece_slot if category == "pieces" else channel
		for id in _sub_buttons:
			(_sub_buttons[id] as Button).set_pressed_no_signal(String(id) == cur)

	## Options for a key: [{id, name, owned, color (Color or null), desc}] in data order.
	func options(key: String) -> Array:
		var out: Array = []
		match key:
			"hair":
				var hc: Color = (ItemDB.appearance_table("hair_colors").get(value_of("hair_color"), {}) as Dictionary).get("base", Color("7a3b2e"))
				var hs := ItemDB.appearance_table("hairstyles")
				for id in hs:
					out.append({"id": String(id), "name": String(hs[id]["name"]), "owned": true, "color": hc, "desc": "Hair style: %s." % String(hs[id]["name"])})
			"hair_color", "skin", "eyes":
				var table := ItemDB.appearance_table({"hair_color": "hair_colors", "skin": "skin_tones", "eyes": "eye_colors"}[key])
				var ck := "iris" if key == "eyes" else "base"
				for id in table:
					out.append({"id": String(id), "name": String(table[id]["name"]), "owned": true, "color": table[id].get(ck, Color.WHITE), "desc": ""})
			"outfit":
				var outfits := ItemDB.appearance_table("outfits")
				for id in outfits:
					var o: Dictionary = outfits[id]
					var pal: Dictionary = o.get("palette", {})
					out.append({"id": String(id), "name": String(o["name"]), "owned": Looks.owned_outfit(String(id), wardrobe),
						"color": ItemDB.swatch_color(String(pal.get("primary", ""))), "desc": String(o.get("desc", ""))})
			_:
				if key.begins_with("palette."):
					var sw := ItemDB.appearance_table("swatches")
					for id in sw:
						out.append({"id": String(id), "name": String(sw[id]["name"]), "owned": Looks.owned_swatch(String(id), wardrobe), "color": sw[id].get("color", Color.WHITE), "desc": ""})
				elif AppearanceData.SLOTS.has(key):
					if AppearanceData.OPTIONAL_SLOTS.has(key):
						out.append({"id": "", "name": "None", "owned": true, "color": null, "desc": "Nothing in this slot."})
					for pid in ItemDB.parts_for_slot(key):
						var p := ItemDB.appearance_part(String(pid))
						out.append({"id": String(pid), "name": String(p.get("name", pid)), "owned": Looks.owned_part(String(pid), wardrobe),
							"color": _part_color(p), "desc": "%s. Cosmetic only." % String(SLOT_NAMES.get(key, key))})
		return out

	func value_of(key: String) -> String:
		return Looks.value_of(look, key)

	## Main cloth colour of a part as it would look with the current palette.
	func _part_color(p: Dictionary) -> Variant:
		var ch: Dictionary = p.get("channels", {})
		for k in ch:
			return ItemDB.swatch_color(value_of("palette." + String(ch[k])))
		var fx: Dictionary = p.get("fixed", {})
		for k in fx:
			return fx[k]
		return null

	func _build_grid() -> void:
		if grid == null:
			return
		for c in grid.get_children():
			grid.remove_child(c)
			c.queue_free()
		tiles.clear()
		var key := grid_key()
		var tile_w := floorf((width - 30.0 - float(columns - 1) * 10.0) / float(columns))
		for opt in options(key):
			if not bool(opt["owned"]) and not show_locked:
				continue
			var b := _make_tile(key, opt, tile_w)
			grid.add_child(b)
			tiles[String(opt["id"])] = b
		_sync_selection()
		if info != null:
			info.text = String(BLURBS.get(category, ""))
		if scroll != null:
			scroll.scroll_vertical = 0

	func _make_tile(key: String, opt: Dictionary, tile_w: float) -> Button:
		var b := Button.new()
		b.theme_type_variation = "TabLike"
		b.toggle_mode = true
		b.text = String(opt["name"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(tile_w, 58)
		b.add_theme_font_size_override("font_size", 21)
		b.expand_icon = false
		var owned := bool(opt["owned"])
		if not owned:
			b.icon = IconFactory.icon("ui_lock", Color.WHITE, 48)
			b.modulate = Color(1, 1, 1, 0.72)
		elif opt["color"] is Color:
			b.icon = IconFactory.glyph("dot", 34, 34, opt["color"])
		var tip := String(opt["name"])
		if String(opt.get("desc", "")) != "":
			tip += "\n" + String(opt["desc"])
		if not owned:
			tip += "\nLocked. " + Looks.how_to_earn(key, String(opt["id"]), wardrobe)
		b.tooltip_text = tip.strip_edges()
		b.set_meta("locked", not owned)
		b.pressed.connect(_on_tile_pressed.bind(key, String(opt["id"])))
		b.focus_entered.connect(_describe.bind(key, opt))
		b.mouse_entered.connect(_describe.bind(key, opt))
		Kit.hook_sounds(b)
		return b

	func _describe(key: String, opt: Dictionary) -> void:
		if info == null:
			return
		var t := String(opt["name"])
		if String(opt.get("desc", "")) != "":
			t += ": " + String(opt["desc"])
		if not bool(opt["owned"]):
			var why := Looks.how_to_earn(key, String(opt["id"]), wardrobe)
			t += "\nLocked. " + (why if why != "" else "Not available yet.")
		info.text = t

	func _on_tile_pressed(key: String, value: String) -> void:
		choose(key, value)

	## Picks `value` for `key`. Locked / unknown choices are refused (info line says how to earn them).
	## Emits look_changed when the look actually changes. True unless refused.
	func choose(key: String, value: String) -> bool:
		if not Looks.can_choose(key, value, wardrobe):
			if info != null:
				var why := Looks.how_to_earn(key, value, wardrobe)
				info.text = "Locked. " + (why if why != "" else "Not available yet.")
			Audio.play_ui("ui_error")
			_sync_selection()
			return false
		var nl := Looks.with_choice(look, key, value)
		if Looks.same_look(nl, look):
			_sync_selection()
			return true
		look = nl
		_sync_selection()
		look_changed.emit(look.duplicate(true))
		return true

	func _sync_selection() -> void:
		var cur := value_of(grid_key())
		for id in tiles:
			(tiles[id] as Button).set_pressed_no_signal(String(id) == cur)

	## The selected tile of the grid on screen (else its first tile, else the category tab).
	func default_focus() -> Control:
		var cur := value_of(grid_key())
		if tiles.has(cur):
			return tiles[cur]
		for id in tiles:
			return tiles[id]
		return _tab_buttons.get(category)

	## Q / E and PageUp / PageDown switch category. True if handled.
	func handle_key(event: InputEvent) -> bool:
		if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
			return false
		var k := key_of(event as InputEventKey)
		if k == KEY_Q or k == KEY_PAGEUP:
			cycle_category(-1)
			return true
		if k == KEY_E or k == KEY_PAGEDOWN:
			cycle_category(1)
			return true
		return false

extends "res://src/ui/panels/panel_base.gd"
## Friends menu for a befriended companion (args {"id"}): Pet / Follow me / Wait here / Go home / Feed, and
## (Chapter Two, MP §6.1) what the friend does in a fight: its passive, the purpose of its basic attack, its
## signature skill with the live cooldown / range / reason it can't be used now (and a button that requests
## the SAME skill as the autocast and the Companion Skill key: one cooldown), the next bond perk, the Assist /
## Stay close behaviour choice, the ribbon (Mochi's Comfort Ribbon for Brave Little Steps) and its home spot.
## Calls Game.companion_nodes[id].command(cmd); falls back to GameState when the node is missing. Not
## full-screen: the world keeps living around you while it's open (it closes when Krystal is hurt).

const Support := preload("res://src/companions/companion_support.gd")

const TEXT_W := 640.0

var cid := ""
var first_btn: Button
var _status_l: Label
var _passive_l: Label
var _attack_l: Label
var _skill_l: Label
var _skill_state_l: Label
var _skill_btn: Button
var _perk_l: Label
var _assist_btn: Button
var _close_btn: Button
var _auto_attack_btn: CheckButton
var _autocast_btn: CheckButton
var _ribbon_l: Label
var _ribbon_btn: Button
var _home_l: Label
var _note := ""
var _note_ms := 0
var _tick := 0.0


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	cid = String(p_args.get("id", ""))
	dim_background = false
	var c := ItemDB.creature(cid)
	title = String(c.get("name", cid.capitalize()))
	window_min = Vector2(720, 0)


func reopen(p_args: Dictionary) -> void:
	if String(p_args.get("id", cid)) != cid:
		request_close()


func _build() -> void:
	var c := ItemDB.creature(cid)
	var top := Kit.hbox(20)
	body.add_child(top)
	var port := Control.new()
	port.custom_minimum_size = Vector2(136, 136)
	var tex := IconFactory.portrait(cid)
	port.draw.connect(func() -> void:
		var ctr := port.size * 0.5
		port.draw_circle(ctr, 66, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
		port.draw_texture_rect(tex, Rect2(ctr - Vector2(62, 62), Vector2(124, 124)), false)
		port.draw_arc(ctr, 63, 0.0, TAU, 64, ThemeFactory.INK, 3.0, true))
	top.add_child(port)
	var v := Kit.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(v)
	var role := Support.role(cid)
	var sp := Kit.label((String(c.get("species", "")) + ("  ·  " + role if role != "" else "")).to_upper(), "Tiny")
	sp.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.15))
	v.add_child(sp)
	v.add_child(Kit.hearts(GameState.bond_level(cid), 5, 30))
	_status_l = Kit.label(status_text(cid), "Small")
	v.add_child(_status_l)
	var blurb := Kit.wrap_label(String(c.get("blurb", "")), "", 420)
	blurb.add_theme_font_size_override("font_size", 21)
	v.add_child(blurb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	var rec := GameState.companion(cid)
	var assignment := String(rec.get("assignment", "home"))
	first_btn = _cmd_button(grid, "Pet", "pet", "AccentButton")
	if assignment == "follow":
		_cmd_button(grid, "Wait here", "wait")
	else:
		_cmd_button(grid, "Follow me", "follow")
	_cmd_button(grid, "Go home", "home")
	var food := String(c.get("favorite_food", ""))
	var have := GameState.count_item(food) if food != "" else 0
	var fb := _cmd_button(grid, "Feed %s (%d)" % [ItemDB.display_name(food), have] if food != "" else "Feed", "feed")
	if food != "":
		fb.icon = IconFactory.item_icon(food, 48)
	fb.disabled = have <= 0
	fb.tooltip_text = "" if have > 0 else "You don't have any %s." % ItemDB.display_name(food)
	if not ItemDB.companion_skill(cid).is_empty():
		_build_together()
	# The menu doesn't pause the world but does hold Krystal still: step out of it the moment she's hurt.
	# (A bound-method connection is dropped automatically when the panel is freed.)
	Events.player_damaged.connect(_on_player_damaged)
	Events.companion_bond_changed.connect(_on_bond_changed)


func _build_together() -> void:
	body.add_child(section_title("Together"))
	var col := Kit.vbox(6)
	body.add_child(col)
	_passive_l = _text(col)
	_attack_l = _text(col)
	_skill_l = _text(col)
	var srow := Kit.hbox(12)
	col.add_child(srow)
	_skill_btn = Kit.button("", _use_skill)
	_skill_btn.custom_minimum_size = Vector2(250, 0)
	srow.add_child(_skill_btn)
	_skill_state_l = Kit.label("", "Small")
	_skill_state_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skill_state_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_state_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	srow.add_child(_skill_state_l)
	_perk_l = _text(col, "Small")
	var mrow := Kit.hbox(12)
	col.add_child(mrow)
	var ml := Kit.label("In a fight:", "Small")
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(ml)
	_assist_btn = Kit.button("Assist", _set_mode.bind("assist"))
	_assist_btn.toggle_mode = true
	_assist_btn.tooltip_text = "Helps with enemies you're fighting or that go for you."
	mrow.add_child(_assist_btn)
	_close_btn = Kit.button("Stay close", _set_mode.bind("close"))
	_close_btn.toggle_mode = true
	_close_btn.tooltip_text = "Stays right beside you and only answers enemies at your side."
	mrow.add_child(_close_btn)
	# The two companion settings (Settings, saved): automatic attacks (off = support only) and autocast.
	var trow := Kit.hbox(18)
	col.add_child(trow)
	_auto_attack_btn = _setting_toggle(trow, "Attacks on its own", "companion_auto_attack",
		"Off: your friends only support you (passive and skill), they never attack by themselves.")
	_autocast_btn = _setting_toggle(trow, "Uses its skill on its own", "companion_autocast",
		"Off: the skill is only used when you ask for it (%s)." % Settings.action_label("companion_skill"))
	var rrow := Kit.hbox(12)
	col.add_child(rrow)
	_ribbon_btn = Kit.button("Tie the Comfort Ribbon", _give_ribbon)
	rrow.add_child(_ribbon_btn)
	_ribbon_l = Kit.label("", "Small")
	_ribbon_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ribbon_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ribbon_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rrow.add_child(_ribbon_l)
	_home_l = _text(col, "Small")


func _setting_toggle(parent: Control, text: String, key: String, tip: String) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 20)
	b.button_pressed = Support.setting_on(key)
	b.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		UiUtil.save_settings())
	Kit.hook_sounds(b)
	parent.add_child(b)
	return b


func _text(parent: Control, variation: String = "") -> Label:
	var l := Kit.wrap_label("", variation, TEXT_W)
	l.add_theme_font_size_override("font_size", 20)
	parent.add_child(l)
	return l


func refresh() -> void:
	if _status_l != null:
		_status_l.text = status_text(cid)
	if _passive_l == null:
		return
	_passive_l.text = "Passive: " + Support.passive_text(cid)
	_attack_l.text = "Attack: " + Support.attack_text(cid)
	_skill_l.text = "Skill: " + Support.skill_text(cid)
	var np := Support.next_perk_text(cid)
	_perk_l.text = np if np != "" else "Every bond perk is unlocked. Thank you for being such good friends."
	var m := Support.mode(cid)
	_assist_btn.set_pressed_no_signal(m == "assist")
	_close_btn.set_pressed_no_signal(m == "close")
	_auto_attack_btn.set_pressed_no_signal(Support.auto_attack())
	_autocast_btn.set_pressed_no_signal(Support.setting_on("companion_autocast"))
	_refresh_ribbon()
	_home_l.text = home_text(cid)
	_refresh_skill()


func _refresh_skill() -> void:
	if _skill_btn == null:
		return
	var st := skill_state(cid)
	_skill_btn.text = "Use %s (%s)" % [Support.skill_name(cid), Settings.action_label("companion_skill")]
	_skill_btn.disabled = not bool(st["ok"])
	var line := String(st["text"])
	if _note != "" and Time.get_ticks_msec() - _note_ms < 2500:
		line = _note
	_skill_state_l.text = line


func _refresh_ribbon() -> void:
	var chk := Support.ribbon_check(cid)
	var item := String(chk.get("item", ""))
	var r := Support.ribbon(cid)
	_ribbon_btn.visible = item != "" and r != item
	_ribbon_btn.disabled = not bool(chk.get("ok", false))
	_ribbon_btn.tooltip_text = String(chk.get("reason", ""))
	if r == "comfort_ribbon":
		_ribbon_l.text = "Wearing the Comfort Ribbon." + ("" if Support.has_courage(cid) else " Rest by the lit lantern at the mine's mouth together.")
	elif r == Support.RIBBON_BOND:
		_ribbon_l.text = "Wearing a bond ribbon (5 hearts)."
	elif item != "":
		_ribbon_l.text = String(chk.get("reason", "")) if not bool(chk.get("ok", false)) else "A little comfort for a brave walk."
	else:
		_ribbon_l.text = "A bond ribbon at 5 hearts."


## Live cooldown / reason line. {"ok": bool (the button can be pressed), "text"}.
static func skill_state(id: String) -> Dictionary:
	var sk_name := Support.skill_name(id)
	if sk_name == "":
		return {"ok": false, "text": ""}
	var node: Variant = Game.companion_nodes.get(id)
	var rem := Support.remaining(id)
	var range_txt := "works within %d m of you" % int(ItemDB.companion_rules().get("presence_range", 25.0))
	if node is Node and is_instance_valid(node) and (node as Node).has_method("skill_status"):
		var s: Dictionary = (node as Node).call("skill_status")
		if bool(s.get("ok", false)):
			return {"ok": true, "text": "Ready (%s)." % range_txt}
		var reason := String(s.get("reason", ""))
		return {"ok": false, "text": reason if reason != "" else "Not right now."}
	if rem > 0.0:
		return {"ok": false, "text": "%s is recharging (%d s)." % [sk_name, ceili(rem)]}
	var nm := String(ItemDB.creature(id).get("name", id.capitalize()))
	return {"ok": false, "text": "Ready. %s needs to be following you (%s)." % [nm, range_txt]}


## "Home spot: its Companion Bed" / "the Haven clearing" for a companion id.
static func home_text(id: String) -> String:
	var rec := GameState.companion(id)
	var nook := String(rec.get("home_nook", ""))
	if nook != "" and GameState.structures.has(nook):
		var sid := String(GameState.structures[nook].get("id", ""))
		return "Home spot: its %s at the Haven." % ItemDB.structure_display_name(sid)
	return "Home spot: the Haven clearing. Place a Companion Bed or Perch to give it its own."


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	_refresh_skill()


func _on_player_damaged(_amount: float, _source: Node) -> void:
	request_close()


func _on_bond_changed(id: String, _level: int) -> void:
	if id == cid:
		refresh()


func _cmd_button(parent: Control, text: String, cmd: String, variation: String = "") -> Button:
	var b := Kit.button(text, _command.bind(cmd), variation)
	b.custom_minimum_size = Vector2(300, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


## "Following you" / "At the Haven" / ... for a companion id.
static func status_text(id: String) -> String:
	var rec := GameState.companion(id)
	if not bool(rec.get("befriended", false)):
		return "Not yet befriended"
	match String(rec.get("assignment", "home")):
		"follow":
			return "Following you" + (" (staying close)" if Support.mode(id) == "close" else "")
		"wait":
			return "Waiting where you left them"
		"home":
			return "At home in the Haven"
	return ""


func _node() -> Node:
	var node: Variant = Game.companion_nodes.get(cid, null)
	if node is Node and is_instance_valid(node) and (node as Node).has_method("command"):
		return node
	return null


func _command(cmd: String) -> void:
	var node := _node()
	if node != null:
		node.command(cmd)
	else:
		# Companion node missing (e.g. placeholder module): keep state consistent at least.
		match cmd:
			"follow", "home":
				GameState.set_companion_assignment(cid, cmd)
			"wait":
				var pos: Variant = Game.player.global_position if Game.player != null and is_instance_valid(Game.player) else null
				GameState.set_companion_assignment(cid, "wait", Game.area_id, pos)
	request_close()


func _use_skill() -> void:
	var node := _node()
	if node == null:
		_flash_note("%s needs to be here." % String(ItemDB.creature(cid).get("name", cid)))
		return
	var r: Variant = node.command("skill")
	if r is Dictionary and bool((r as Dictionary).get("ok", false)):
		request_close()
		return
	_flash_note(String((r as Dictionary).get("text", "")) if r is Dictionary else "")


func _set_mode(m: String) -> void:
	var node := _node()
	if node != null:
		node.command(m)
	else:
		Support.set_mode(cid, m)
	refresh()


func _give_ribbon() -> void:
	var node := _node()
	var ok := false
	if node != null:
		var r: Variant = node.command("ribbon")
		ok = r is Dictionary and bool((r as Dictionary).get("ok", false))
	else:
		ok = Support.give_ribbon(cid)
	if not ok:
		_flash_note(String(Support.ribbon_check(cid).get("reason", "")))
	refresh()


func _flash_note(t: String) -> void:
	if t == "":
		return
	_note = t
	_note_ms = Time.get_ticks_msec()
	_refresh_skill()


func default_focus() -> Control:
	return first_btn

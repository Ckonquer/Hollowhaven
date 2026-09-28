extends "res://tests/unit/test_companions_fixture.gd"
## Friends panel, HUD badge and controls for companion combat (MP §6.1): the panel shows the passive, the
## attack's purpose, the skill with its live cooldown / reason, the next perk, the Assist / Stay close choice,
## the ribbon and the home spot; its skill button requests the same skill; the badge draws the cooldown ring
## and flashes when ready (a steady glow with reduce_flashing); the controls list and hint tokens know the
## Companion Skill action.

const PanelScript := preload("res://src/ui/panels/companion_panel.gd")
const BadgeScript := preload("res://src/ui/hud/companion_badge.gd")
const ControlsPanel := preload("res://src/ui/panels/controls_panel.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")


func _texts(n: Node, out: Array) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _has(texts: Array, fragment: String) -> bool:
	for t in texts:
		if String(t).contains(fragment):
			return true
	return false


func _button(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).text.begins_with(prefix):
		return n
	for c in n.get_children():
		var b := _button(c, prefix)
		if b != null:
			return b
	return null


func _panel(id: String) -> Control:
	var p: Control = PanelScript.new()
	p.setup({"id": id})
	add_child(p)
	nodes.append(p)
	return p


func test_friends_panel_shows_what_the_friend_does() -> void:
	UiUtil.allow_settings_save = false
	var m := _follower("mochi")
	GameState.give_item("comfort_ribbon", 1)
	var p := _panel("mochi")
	await wait_frames(2)
	var t := _texts(p, [])
	assert_true(_has(t, "Passive: +8% healing"), "passive: %s" % str(t))
	assert_true(_has(t, "Attack: Spore Puff: 4 damage every 2.4 s"), "attack purpose")
	assert_true(_has(t, "Skill: Bloomguard: Restores 18 health over 6 s"), "skill")
	assert_true(_has(t, "Recharge 25 s"), "with its cooldown")
	assert_true(_has(t, "Next at 2 hearts"), "the next practical perk")
	assert_true(_has(t, "Home spot:"), "home spot")
	assert_not_null(_button(p, "Assist"), "Assist")
	assert_not_null(_button(p, "Stay close"), "Stay close")
	var use := _button(p, "Use Bloomguard")
	assert_not_null(use, "a skill button")
	assert_true(use != null and use.text.contains("(%s)" % Settings.action_label("companion_skill")), "naming the key")
	assert_true(use != null and use.disabled, "nothing to heal: disabled with a reason")
	assert_true(_has(_texts(p, []), "You're not hurt."), "the reason is shown")
	# Mode buttons change the saved behaviour.
	_button(p, "Stay close").emit_signal("pressed")
	assert_eq(Support.mode("mochi"), "close")
	assert_true(_has(_texts(p, []), "staying close"))
	# The Comfort Ribbon from the panel.
	var rb := _button(p, "Tie the Comfort Ribbon")
	assert_true(rb != null and not rb.disabled, "ribbon button ready")
	rb.emit_signal("pressed")
	assert_eq(String(GameState.companion("mochi")["ribbon"]), "comfort_ribbon")
	assert_true(_has(_texts(p, []), "Wearing the Comfort Ribbon"))
	# Hurt: the skill button requests the SAME skill (one cooldown) and closes the menu.
	player.health.hp = 40.0
	await wait_seconds(0.35)
	use = _button(p, "Use Bloomguard")
	assert_true(use != null and not use.disabled, "now it can be used")
	var closed: Array = []
	p.close_requested.connect(func() -> void: closed.append(true))
	use.emit_signal("pressed")
	assert_almost(Support.remaining("mochi"), 25.0, 0.05, "cooldown started")
	assert_eq(closed.size(), 1, "the menu steps aside")
	assert_true(String(PanelScript.skill_state("mochi")["text"]).contains("recharging"), str(PanelScript.skill_state("mochi")))


func test_panel_toggles_the_companion_settings() -> void:
	UiUtil.allow_settings_save = false          # never write the player's settings file
	_follower("lumi")
	var p := _panel("lumi")
	await wait_frames(2)
	var aa := _button(p, "Attacks on its own") as CheckButton
	var ac := _button(p, "Uses its skill on its own") as CheckButton
	assert_true(aa != null and aa.button_pressed, "auto attack shown on (the default)")
	assert_true(ac != null and ac.button_pressed, "autocast shown on")
	if aa == null or ac == null:
		return
	aa.button_pressed = false
	assert_false(Support.auto_attack(), "off: support only")
	ac.button_pressed = false
	assert_false(Support.autocast(), "off: the skill waits for Krystal")
	aa.button_pressed = true
	assert_true(Support.auto_attack())


func test_panel_for_a_friend_at_home() -> void:
	_befriend("pebble")
	var p := _panel("pebble")
	await wait_frames(2)
	var t := _texts(p, [])
	assert_true(_has(t, "Stone Bump: 8 damage every 2.4 s, up close"), str(t))
	assert_true(_has(t, "Stoneheart"))
	assert_true(_has(t, "needs to be following you"), "why the skill can't be used from home")
	assert_true(_has(t, "A bond ribbon at 5 hearts."))


func test_badge_cooldown_ring_and_ready_flash() -> void:
	var l := _follower("lumi")
	var b: Control = BadgeScript.new()
	add_child(b)
	nodes.append(b)
	await wait_frames(2)
	assert_true(b.visible)
	assert_eq(String(b.skill_l.text), "[%s] Glimmerstep" % Settings.action_label("companion_skill"), "ready: key + name")
	assert_true(bool(l.use_skill(true)["ok"]))
	b.call("_update_skill")
	assert_almost(float(b.get("_frac")), 1.0, 0.01, "a full ring right after the cast")
	assert_true(String(b.skill_l.text).begins_with("Glimmerstep  24"), String(b.skill_l.text))
	GameState.companion("lumi")["skill_ready_at"] = Support.now() + 12.0
	b.call("_update_skill")
	assert_almost(float(b.get("_frac")), 0.5, 0.01, "half the ring at half the cooldown")
	GameState.companion("lumi")["skill_ready_at"] = 0.0
	Events.companion_skill_ready.emit("lumi")
	assert_true(float(b.flash_strength()) > 0.5, "a ready flash")
	# Reduced flashing: no flash, a steady ring instead.
	Settings.set_value("reduce_flashing", true)
	b.set("_flash", 0.0)
	Events.companion_skill_ready.emit("lumi")
	assert_almost(float(b.flash_strength()), 0.0, 0.0001, "no flash with reduce_flashing")
	assert_true(bool(b.get("_ready_glow")), "a steady glow instead")


## Geometry check (no screenshots in this wave): the Friends panel, with everything it can show (Mochi following
## with a Comfort Ribbon ready to tie, a skill reason, every row), fits the 1920x1080 canvas the UI is laid out
## in (display/window/stretch canvas_items, so a 1600x900 window shows the same layout scaled). The panel has no
## scroll container: anything taller would be cut off.
func test_friends_panel_fits_the_screen() -> void:
	UiUtil.allow_settings_save = false
	var canvas_h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	GameState.give_item("comfort_ribbon", 1)
	for id in ["mochi", "pebble", "lumi"]:
		if id == "mochi":
			_follower(id)
		else:
			_befriend(id)
		var p := _panel(id)
		await wait_frames(3)
		var win: Control = p.get("window")
		var h := win.get_combined_minimum_size().y
		print("    friends panel %s: %.0f px tall (canvas %.0f)" % [id, h, canvas_h])
		assert_true(h <= canvas_h - 60.0, "%s's panel fits on screen with a margin (%.0f px of %.0f)" % [id, h, canvas_h])
		p.queue_free()
		await wait_frames(1)


func test_telemetry_reads_the_companion_skill_state() -> void:
	var l := _follower("lumi")
	await wait_physics(2)
	assert_true(bool(l.use_skill(true)["ok"]))
	var st: Dictionary = l.get_skill_state()
	for k in ["ready", "remaining", "cooldown", "reason", "name", "state", "target", "attacks", "healing", "nav"]:
		assert_true(st.has(k), "key %s" % k)
	assert_false(bool(st["ready"]))
	var tel: Script = load("res://src/qa/qa_telemetry.gd")
	if tel != null and tel.can_instantiate():
		var info: Dictionary = tel.call("companion_skill_info")
		assert_true(info.has("lumi") and (info["lumi"] as Dictionary).has("node"), "qa telemetry picks it up: %s" % str(info))


func test_controls_and_hint_token_know_the_companion_skill() -> void:
	var found := false
	for g in ControlsPanel.GROUPS:
		for item in g[1]:
			if String(item[0]) == "companion_skill":
				found = true
	assert_true(found, "Companion skill listed in the F1 controls")
	var label_fn := func(a: String) -> String: return "<%s>" % a
	assert_eq(UiUtil.fill_tokens("Press {skill}", label_fn), "Press <companion_skill>")
	assert_true(InputMap.has_action("companion_skill"), "the rebindable action exists")

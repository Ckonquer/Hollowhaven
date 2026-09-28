extends CanvasLayer
## Gameplay UI root (layer 50, always processing). Owns the HUD, the panels, overlays (chapter card,
## death, ending, comfort) and the screen fade. Game creates it once when the first area loads.
## API (docs/ARCHITECTURE.md): fade_out(t) / fade_in(t) (awaitable), open(panel, args), close(panel),
## is_open(panel), show_death() (awaitable), show_ending() (awaitable), show_chapter_card(title, sub),
## show_comfort(first_time) (awaitable). Extra: confirm(title, text, buttons) (awaitable -> choice id),
## top_panel(), close_all().
## Handles the UI input actions: inventory, craft, journal, map, pause (Esc closes the top panel
## first), help (F1 controls overlay). Panels call Game.push_ui/pop_ui through here, and full-screen
## panels pause the tree via Game.set_paused.

const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const Kit := preload("res://src/ui/ui_kit.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Hud := preload("res://src/ui/hud/hud.gd")
const Toasts := preload("res://src/ui/hud/toasts.gd")
const QuestBanner := preload("res://src/ui/hud/quest_banner.gd")
const ChapterCard := preload("res://src/ui/screens/chapter_card.gd")
const DeathScreen := preload("res://src/ui/screens/death_screen.gd")
const EndingScreen := preload("res://src/ui/screens/ending_screen.gd")

const PANELS := {
	"inventory": "res://src/ui/panels/inventory_panel.gd",
	"crafting": "res://src/ui/panels/crafting_panel.gd",
	"storage": "res://src/ui/panels/storage_panel.gd",
	"journal": "res://src/ui/panels/journal_panel.gd",
	"map": "res://src/ui/panels/map_panel.gd",
	"companion": "res://src/ui/panels/companion_panel.gd",
	"pause": "res://src/ui/panels/pause_panel.gd",
	"settings": "res://src/ui/panels/settings_panel.gd",
	"controls": "res://src/ui/panels/controls_panel.gd",
	"comfort": "res://src/ui/screens/comfort_screen.gd",
	"confirm": "res://src/ui/screens/confirm_dialog.gd",
}
## Panels that freeze the world while open.
const FULLSCREEN := ["inventory", "crafting", "storage", "journal", "map", "pause", "settings", "controls", "comfort", "confirm"]
## Panels the gameplay hotkeys may switch between.
const GAMEPLAY_PANELS := ["inventory", "crafting", "storage", "journal", "map", "companion", "controls"]
const HOTKEYS := {"inventory": "inventory", "craft": "crafting", "journal": "journal", "map": "map", "help": "controls"}

var root: Control
var hud: Control
var panel_layer: Control
var overlay_layer: Control
var top_layer: Control
var toasts: Control
var quest_banner: Control
var fade_rect: ColorRect
var panels: Dictionary = {}        # name -> panel node
var order: Array = []              # open panel names, oldest first
var _paused_by_ui := false
var _ending: Control = null
var _death: Control = null
var _card: Control = null
var _tw: Dictionary = {}
var _warm: Array = []
var _debug_done := false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "UIRoot"
	root = Control.new()
	root.name = "Root"
	Kit.full_rect(root)
	root.theme = ThemeFactory.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	hud = Hud.new()
	hud.name = "HUD"
	root.add_child(hud)
	overlay_layer = _layer("Overlays")
	# Toasts & quest banners sit above the HUD and overlays but BELOW menus: over a menu they would hide
	# its text (panels give their own feedback, and the banner waits until menus close).
	top_layer = _layer("Top")
	panel_layer = _layer("Panels")
	toasts = Toasts.new()
	var tmc := Kit.margin([34, 34, 34, 150])
	tmc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_layer.add_child(Kit.full_rect(tmc))
	var tv := Kit.vbox(0)
	tv.alignment = BoxContainer.ALIGNMENT_END
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tmc.add_child(tv)
	toasts.size_flags_horizontal = Control.SIZE_SHRINK_END
	tv.add_child(toasts)
	quest_banner = QuestBanner.new()
	top_layer.add_child(quest_banner)
	toasts.quest_banner = quest_banner
	fade_rect = ColorRect.new()
	fade_rect.name = "Fade"
	fade_rect.color = Color(0.07, 0.05, 0.08, 1.0 if Game.mode == "loading" else 0.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(Kit.full_rect(fade_rect))
	Events.area_loaded.connect(_on_area_loaded)
	Events.area_exiting.connect(func(_a: String) -> void: close_all())
	Events.settings_changed.connect(_on_settings_changed)


func _layer(n: String) -> Control:
	var c := Control.new()
	c.name = n
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(Kit.full_rect(c))
	return c


# --- Fades -------------------------------------------------------------------------------------

func fade_out(t: float = 0.45) -> void:
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := Kit.retween(self, _tw, "fade")
	if t <= 0.0:
		tw.kill()
		fade_rect.color.a = 1.0
		return
	tw.tween_property(fade_rect, "color:a", 1.0, t)
	await _wait_tween(tw)


func fade_in(t: float = 0.6) -> void:
	var tw := Kit.retween(self, _tw, "fade")
	if t <= 0.0:
		tw.kill()
		fade_rect.color.a = 0.0
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	tw.tween_property(fade_rect, "color:a", 0.0, t)
	await _wait_tween(tw)
	if _tw.get("fade") == tw:   # a newer fade_out may have taken over meanwhile
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


## True while any fade is under way or the screen is (partly) black. Menus must not open then: the fade
## is drawn above the panels, so a menu opened under it (e.g. Esc early in the bed's sleep fade, a fall
## recovery or "Return to the Haven", all with mode still "playing") would sit hidden. fade_out() blocks
## clicks at once; only the newest fade_in() lets them through again when it ends.
func _fade_busy() -> bool:
	return fade_rect.color.a > 0.01 or fade_rect.mouse_filter == Control.MOUSE_FILTER_STOP


## Waits until `tw` has finished OR was killed by a newer fade. A killed tween never emits `finished`,
## so awaiting that signal could leave a caller (Game.load_area, the bed, the mine lift...) hanging
## forever when two fades overlap.
func _wait_tween(tw: Tween) -> void:
	while tw != null and tw.is_valid() and tw.is_running():
		await get_tree().process_frame


# --- Panels ------------------------------------------------------------------------------------

func open(panel_name: String, args: Dictionary = {}) -> void:
	if panel_name == "comfort" and not panels.has("comfort"):
		show_comfort(bool(args.get("first_time", false)))
		return
	if panels.has(panel_name):
		var existing: Control = panels[panel_name]
		existing.move_to_front()
		order.erase(panel_name)
		order.append(panel_name)
		if existing.has_method("reopen"):
			existing.reopen(args)
		elif existing.has_method("refresh"):
			existing.refresh()
		return
	var p := _instantiate(panel_name, args)
	if p == null:
		return
	panels[panel_name] = p
	order.append(panel_name)
	panel_layer.add_child(p)
	Game.push_ui(panel_name)
	_update_pause()
	_refresh_focus_layers()
	Audio.play_ui("ui_open")


func _instantiate(panel_name: String, args: Dictionary) -> Control:
	var path := String(PANELS.get(panel_name, ""))
	if path == "" or not ResourceLoader.exists(path):
		push_warning("UI: unknown panel '%s'" % panel_name)
		return null
	var s: Script = load(path)
	if s == null or not s.can_instantiate():
		push_error("UI: panel script failed to load: " + path)
		return null
	var p: Control = s.new()
	p.name = panel_name.capitalize().replace(" ", "")
	p.set("panel_id", panel_name)
	p.set("ui_root", self)
	if p.has_method("setup"):
		p.setup(args)
	if p.has_signal("close_requested"):
		p.connect("close_requested", close.bind(panel_name))
	return p


func close(panel_name: String) -> void:
	if not panels.has(panel_name):
		return
	var p: Control = panels[panel_name]
	panels.erase(panel_name)
	order.erase(panel_name)
	if p.has_method("on_close"):
		p.on_close()
	if p.has_method("animate_out_and_free"):
		p.animate_out_and_free()
	else:
		p.queue_free()
	Game.pop_ui(panel_name)
	_update_pause()
	_refresh_focus_layers()
	Audio.play_ui("ui_close")
	if panel_name == "settings":
		UiUtil.save_settings()
	var top := top_panel()
	if top != "":
		var tp: Control = panels[top]
		if tp.has_method("_focus_default"):
			tp.call_deferred("_focus_default")


func close_all() -> void:
	for n in order.duplicate():
		close(String(n))


func is_open(panel_name: String) -> bool:
	return panels.has(panel_name)


func top_panel() -> String:
	return String(order[order.size() - 1]) if not order.is_empty() else ""


func toggle(panel_name: String, args: Dictionary = {}) -> void:
	if is_open(panel_name):
		close(panel_name)
	else:
		open(panel_name, args)


func _update_pause() -> void:
	var need := false
	for n in order:
		if FULLSCREEN.has(n):
			need = true
	if need and not get_tree().paused:
		Game.set_paused(true)
		_paused_by_ui = true
	elif not need and _paused_by_ui:
		_paused_by_ui = false
		Game.set_paused(false)


## Only the top panel can take keyboard focus (arrow keys never wander into a covered menu).
func _refresh_focus_layers() -> void:
	var top := top_panel()
	for n in order:
		var p: Control = panels[n]
		if "focus_behavior_recursive" in p:
			p.set("focus_behavior_recursive", 0 if String(n) == top else 1)
	if "focus_behavior_recursive" in hud:
		hud.set("focus_behavior_recursive", 1 if top != "" else 0)


## Awaitable confirmation card; returns the chosen button id ("cancel" if dismissed).
func confirm(title: String, text: String, buttons: Array = []) -> String:
	var args := {"title": title, "text": text}
	if not buttons.is_empty():
		args["buttons"] = buttons
	if panels.has("confirm"):
		close("confirm")
	open("confirm", args)
	if not panels.has("confirm"):
		return "cancel"
	var dlg: Control = panels["confirm"]
	# A one-argument signal resumes `await` with that argument itself (not an Array).
	var res: Variant = await dlg.chosen
	if res is Array:
		return String(res[0]) if not (res as Array).is_empty() else "cancel"
	return String(res) if (res is String or res is StringName) else "cancel"


# --- Input -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if not event.is_pressed() or event.is_echo():
		return
	if _ending != null or _death != null:
		return
	for n in order:
		var pn: Control = panels[n]
		if pn.has_method("is_capturing_input") and pn.is_capturing_input():
			return
	var top := top_panel()
	if top != "":
		var tp: Control = panels[top]
		if tp.has_method("handle_key") and tp.handle_key(event):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause"):
		if top != "":
			close(top)
			get_viewport().set_input_as_handled()
		elif Game.mode == "playing" and not _fade_busy():
			if not _exit_build_mode():
				open("pause")
			get_viewport().set_input_as_handled()
		return
	for action in HOTKEYS:
		if event.is_action_pressed(action):
			if _hotkey(String(HOTKEYS[action])):
				get_viewport().set_input_as_handled()
			return


## Opens / closes / switches panels for a UI hotkey. Returns true if it did something.
func _hotkey(target: String) -> bool:
	var top := top_panel()
	if top == target:
		close(target)
		return true
	if Game.mode != "playing" or _fade_busy():
		return false
	if top == "":
		open(target)
		return true
	if GAMEPLAY_PANELS.has(top):
		close(top)
		open(target)
		return true
	if target == "controls":
		open(target)   # the help overlay may stack over the pause menu / settings
		return true
	return false


func _exit_build_mode() -> bool:
	var pl: Node = Game.player
	if pl == null or not is_instance_valid(pl):
		return false
	var bm: Variant = pl.get("build_mode_active")
	if not (bm is bool and bm):
		return false
	for n in get_tree().get_nodes_in_group("build_mode"):
		for m in ["end", "exit", "cancel", "stop"]:
			if n.has_method(m):
				n.call(m)
				return true
	return false


# --- Overlays ----------------------------------------------------------------------------------

func show_chapter_card(title: String, subtitle: String = "") -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = ChapterCard.new()
	_card.setup(title, subtitle)
	overlay_layer.add_child(_card)


## ~2.5 s: dims, "Krystal was overwhelmed...", then fades to black (the respawn fades back in).
func show_death() -> void:
	close_all()
	hud.set_cinematic(true)
	_death = DeathScreen.new()
	overlay_layer.add_child(_death)
	await _death.play()
	await fade_out(0.6)
	if _death != null and is_instance_valid(_death):
		_death.queue_free()
	_death = null


## Chapter complete + thank-you + credits; returns when the player chooses to continue.
func show_ending() -> void:
	close_all()
	hud.set_cinematic(true)
	_ending = EndingScreen.new()
	overlay_layer.add_child(_ending)
	await _ending.play()
	_ending = null
	if Game.area_id == "surface":
		Audio.play_music("music_haven", 3.0)
	if Game.mode == "playing" or Game.mode == "cutscene":
		hud.set_cinematic(false)


## Comfort screen (pauses the game while open). Awaitable; returns once the player confirms.
func show_comfort(first_time: bool = false) -> void:
	if panels.has("comfort"):
		var existing: Control = panels["comfort"]
		await existing.confirmed
		return
	var p := _instantiate("comfort", {"first_time": first_time})
	if p == null:
		return
	panels["comfort"] = p
	order.append("comfort")
	panel_layer.add_child(p)
	Game.push_ui("comfort")
	_update_pause()
	_refresh_focus_layers()
	Audio.play_ui("ui_open")
	await p.confirmed


## "Unstuck": fades out, teleports Krystal (and her follower) to a spawn of the current area, fades in.
func teleport_player(spawn_id: String) -> void:
	close_all()
	await fade_out(0.35)
	var pl: Node = Game.player
	if pl != null and is_instance_valid(pl) and Game.area != null and Game.area.has_method("get_spawn"):
		var xf: Transform3D = Game.area.get_spawn(spawn_id)
		pl.teleport(xf)
		for id in Game.companion_nodes:
			var c: Variant = Game.companion_nodes[id]
			if c is Node and is_instance_valid(c) and GameState.active_companion == String(id) and (c as Node).has_method("teleport_near"):
				(c as Node).teleport_near(xf.origin)
	await get_tree().create_timer(0.25).timeout
	await fade_in(0.5)
	Events.notify.emit("Krystal found her way back, safe and sound.", "info")


# --- Misc --------------------------------------------------------------------------------------

func _on_settings_changed(key: String) -> void:
	if key == "arachnophobia":
		for n in panels:
			var p: Control = panels[n]
			if p.has_method("refresh"):
				p.refresh()


func _on_area_loaded(_area_id: String) -> void:
	close_all()
	# Re-show the current quest hint if it was emitted before the UI existed (new game start).
	var step: Dictionary = GameState.quests.current_step()
	var hint := String(GameState.quests.step_string(step, "hint")) if not step.is_empty() else ""
	if hint != "" and hud.hints.has_method("on_hint"):
		hud.hints.on_hint("quest_" + String(step.get("id", "")), hint)
	# Warm the icon cache in the background (one icon per frame).
	_warm = ItemDB.all_item_ids().duplicate()
	if Debug.is_cheat_allowed() and not _debug_done:
		_debug_done = true
		_debug_boot.call_deferred()


func _process(_delta: float) -> void:
	if not _warm.is_empty():
		IconFactory.item_icon(String(_warm.pop_back()))


## Debug/QA only: --ui-open=<panel> [--ui-args=<json>] --ui-demo[=build|combat] --ui-lore=id,id
## --ui-show=death|ending|chapter|comfort
func _debug_boot() -> void:
	if not Debug.is_cheat_allowed():
		return
	for lid in Debug.arg("ui-lore").split(",", false):
		GameState.discover_lore(String(lid))
	await get_tree().create_timer(0.9).timeout
	if Debug.has_arg("ui-demo"):
		hud.demo(Debug.arg("ui-demo", "true"))
	var show := Debug.arg("ui-show", "")
	match show:
		"death":
			show_death()
		"ending":
			show_ending()
		"chapter":
			show_chapter_card("Chapter One", "The Dimming Ward")
		"comfort":
			show_comfort(true)
	if Debug.has_arg("ui-open"):
		var a: Variant = JSON.parse_string(Debug.arg("ui-args", "{}"))
		for pn in Debug.arg("ui-open").split(",", false):
			open(String(pn), a if a is Dictionary else {})

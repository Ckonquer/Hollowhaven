extends CanvasLayer
## Gameplay UI root (layer 50, always processing). Owns the HUD, the panels, overlays (chapter card,
## death, ending, comfort) and the screen fade. Game creates it once when the first area loads.
## API (docs/ARCHITECTURE.md): fade_out(t) / fade_in(t) (awaitable), open(panel, args), close(panel),
## is_open(panel), show_death() (awaitable), show_ending() (awaitable), show_chapter_card(title, sub),
## show_comfort(first_time) (awaitable). Extra: confirm(title, text, buttons) (awaitable -> choice id),
## top_panel(), close_all().
## Handles the UI input actions: inventory, craft, journal, map, wardrobe, pause (Esc closes the top panel
## first), help (F1 controls overlay). Panels call Game.push_ui/pop_ui through here, and full-screen
## panels pause the tree via Game.set_paused.
## Chapter Two: the "wardrobe" panel (hotkey, pause menu, Ward Stone, wardrobe / mirror furniture), the
## "expedition" panel (Expedition Board; full-screen) and the "music_box" panel (Music Box; never pauses), has_panel(name),
## the one-time "Your wardrobe is ready" notice for older saves (tick_wardrobe_notice / show_wardrobe_notice),
## and show_chapter_two_ending() (awaitable; Game._show_chapter_two_ending() prefers it).
## HUD hush (visual QA theme T4): while a chapter card, a full-screen menu or modal card, the ending or the death
## screen is up, the chatter waits: toasts and quest banners hold in their queues with their timers paused (the top
## layer fades out, so nothing lands on the card / ending text or peeks past a menu's edge), the tip card holds
## and re-checks that its tip still applies before it comes back, and during a chapter card the gameplay HUD steps
## aside like a cutscene. hush_reason() / is_hushed(); _sync_hush() applies it (on every change and polled). While an
## area loads behind Game's loading card (src/ui/screens/loading_card.gd, a layer above this one) the hush is "loading".
## Toasts also climb above the dialogue box whenever it would share their corner (_layout_toasts, IN-09), and never
## reach up over the goal card, the day dial or a wide quest banner (toast_top_limit, 2.0.3): the ones that don't fit
## the room left between wait their turn (Toasts.set_room).

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
	"wardrobe": "res://src/ui/panels/wardrobe_panel.gd",
	"expedition": "res://src/ui/panels/expedition_panel.gd",
	"music_box": "res://src/ui/panels/music_box_panel.gd",
}
## Panels that freeze the world while open. Not the Music Box: its song preview must be heard while it is open,
## and a paused tree would silence it (like the companion menu, it keeps the world running).
const FULLSCREEN := ["inventory", "crafting", "storage", "journal", "map", "pause", "settings", "controls", "comfort", "confirm",
	"wardrobe", "expedition"]
## Panels the gameplay hotkeys may switch between.
const GAMEPLAY_PANELS := ["inventory", "crafting", "storage", "journal", "map", "companion", "controls", "wardrobe", "expedition",
	"music_box"]
## Input action -> panel. "wardrobe" (O by default, rebindable) follows the pause-menu Wardrobe's rules: full-screen,
## pauses, and only opens in ordinary play (_hotkey: mode "playing", no fade, over no menu but a gameplay panel).
const HOTKEYS := {"inventory": "inventory", "craft": "crafting", "journal": "journal", "map": "map", "help": "controls",
	"wardrobe": "wardrobe"}
## One-time notice for saves from before the wardrobe existed (MP §4 "Existing save").
const WARDROBE_NOTICE_TITLE := "Your Wardrobe"
const WARDROBE_NOTICE_TEXT := "Your wardrobe is ready. You can change your look without starting over."
const WARDROBE_NOTICE_SAFE_SECONDS := 3.0   # continuous safe, quiet play before it appears
const WARDROBE_NOTICE_POLL := 0.25
## Command-line args (debug boots, screenshots, demos) that switch the notice off; --ui-show=wardrobe_notice
## still shows it on demand.
const NOTICE_OFF_ARGS := ["cams", "shot-dir", "shots", "area", "preview", "player-demo", "no-wardrobe-notice"]
## Toast column (bottom-right): margins [left, top, right, bottom]; the bottom one grows while the dialogue box is up.
const TOAST_MARGINS := [34, 34, 34, 150]
const TOAST_DIALOG_GAP := 18.0     # clearance between the toasts and the dialogue box (its speaker tab included)
const TOAST_LAYOUT_POLL := 0.1
const TOAST_CLEAR_GAP := 14.0      # clearance between the toasts and the goal card / day dial / quest banner above them
## The toasts' top limit never goes lower than this share of the canvas height, so the column always keeps room for a
## few toasts (only a goal card far taller than any real one would reach it).
const TOAST_TOP_CAP := 0.6

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
## The wardrobe notice waits for a safe moment. Off in headless runs and screenshot tooling (tests drive
## tick_wardrobe_notice() directly), like Game.autosave_enabled.
var wardrobe_notice_enabled: bool = true
var _notice_safe_t := 0.0
var _notice_poll_t := 0.0
var _notice_showing := false
var toast_margin: MarginContainer  # the toast column's margins (bottom grows over the dialogue box)
var _hush := ""                    # last applied hush_reason()
var _toast_layout_t := 0.0
var _toast_bottom := -1.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "UIRoot"
	wardrobe_notice_enabled = DisplayServer.get_name() != "headless"
	for a in NOTICE_OFF_ARGS:   # debug boots / screenshot tooling never get a surprise card
		if Debug.has_arg(String(a)):
			wardrobe_notice_enabled = false
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
	var tmc := Kit.margin(TOAST_MARGINS)
	tmc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_layer.add_child(Kit.full_rect(tmc))
	toast_margin = tmc
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
	apply_window_scale()
	get_window().size_changed.connect(apply_window_scale)


## Small windows get slightly larger small print (ThemeFactory.apply_window_scale, visual QA UI-22). Not headless.
func apply_window_scale() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	ThemeFactory.apply_window_scale(float(get_window().size.y))


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
	_sync_hush()
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
	_sync_hush()
	Audio.play_ui("ui_close")
	if panel_name == "settings":
		UiUtil.save_settings()
	if top_panel() != "":
		_focus_top.call_deferred()


## Gives keyboard focus to whatever panel is on top NOW (deferred from close(): a hotkey may have opened
## another panel in the same frame, e.g. switching away from the wardrobe opened over the pause menu).
func _focus_top() -> void:
	var top := top_panel()
	if top == "" or not panels.has(top):
		return
	var tp: Control = panels[top]
	if is_instance_valid(tp) and tp.has_method("_focus_default"):
		tp.call("_focus_default")


func close_all() -> void:
	for n in order.duplicate():
		close(String(n))


func is_open(panel_name: String) -> bool:
	return panels.has(panel_name)


## True when a panel of that name is registered (e.g. the Ward Stone asks for "wardrobe").
func has_panel(panel_name: String) -> bool:
	return PANELS.has(panel_name)


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
	_sync_hush()


## ~2.5 s: dims, "Krystal was overwhelmed...", then fades to black (the respawn fades back in).
func show_death() -> void:
	close_all()
	hud.set_cinematic(true)
	_death = DeathScreen.new()
	overlay_layer.add_child(_death)
	_sync_hush()
	await _death.play()
	await fade_out(0.6)
	if _death != null and is_instance_valid(_death):
		_death.queue_free()
	_death = null
	_sync_hush()


## Chapter complete + thank-you + credits; returns when the player chooses to continue.
func show_ending() -> void:
	await _play_ending({})
	if Audio.music_director_active():
		Audio.release_music("restoration", 3.0)     # the director returns to the Haven's day/night music
	elif Game.area_id == "surface":
		Audio.play_music("music_haven", 3.0)
	_end_ending_cinematic()


## Chapter Two ending (MP section 17): "Chapter Two Complete - The Lanterns of Hallowmere", the ending card,
## credits and "Continue exploring" (EndingScreen variant "chapter_two"). While it shows, input, the UI hotkeys
## and the wardrobe notice are blocked exactly like the Chapter One ending. No music call: the director plays
## the celebration on Events.chapter2_completed (there is no "restoration" request to release). Awaitable;
## returns when the player continues. A second call while it shows just waits for the same ending.
func show_chapter_two_ending() -> void:
	if _ending != null and is_instance_valid(_ending):
		if _ending.has_signal("finished"):
			await Signal(_ending, "finished")
		return
	await _play_ending({"variant": "chapter_two"})
	_end_ending_cinematic()


## Shared by both endings: closes the menus, hides the gameplay HUD, shows the ending overlay and waits for
## the player to continue. `_ending` is set for the whole time (blocks _input and the wardrobe notice).
func _play_ending(params: Dictionary) -> void:
	close_all()
	hud.set_cinematic(true)
	var e := EndingScreen.new()
	if not params.is_empty():
		e.setup(params)
	_ending = e
	overlay_layer.add_child(e)
	_sync_hush()
	await e.play()
	if _ending == e:
		_ending = null
	_sync_hush()


func _end_ending_cinematic() -> void:
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
	_sync_hush()
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
	_sync_hush()   # Game is "playing" again: the loading hush lifts before the quest hint below is re-shown
	# Re-show the current quest hint if it was emitted before the UI existed (new game start).
	var step: Dictionary = GameState.quests.current_step()
	var hint := String(GameState.quests.step_string(step, "hint")) if not step.is_empty() else ""
	if hint != "" and hud.hints.has_method("on_hint"):
		hud.hints.on_hint("quest_" + String(step.get("id", "")), hint)
	# Warm the icon cache in the background (one icon per frame).
	_warm = ItemDB.all_item_ids().duplicate()
	_notice_safe_t = 0.0
	if Debug.is_cheat_allowed() and not _debug_done:
		_debug_done = true
		_debug_boot.call_deferred()


func _process(delta: float) -> void:
	if not _warm.is_empty():
		IconFactory.item_icon(String(_warm.pop_back()))
	if wardrobe_notice_enabled:
		tick_wardrobe_notice(delta)
	_sync_hush()
	_toast_layout_t -= delta
	if _toast_layout_t <= 0.0:
		_toast_layout_t = TOAST_LAYOUT_POLL
		_layout_toasts()


# --- HUD hush (visual QA T4) -----------------------------------------------------------------------------

## Why the HUD's chatter is held right now ("" = free): "loading" (Game's loading card is up while an area loads - the
## area builds in one frozen frame behind it, so nothing may time out there), "ending", "death", "card" (a chapter card)
## or "panel" (a full-screen menu or a modal confirm card, FULLSCREEN). Non-full-screen panels (companion menu, Music
## Box) keep the world, and the toasts, running.
func hush_reason() -> String:
	if Game.mode == "loading" and Game.has_method("loading_card_showing") and bool(Game.loading_card_showing()):
		return "loading"
	if _ending != null and is_instance_valid(_ending):
		return "ending"
	if _death != null and is_instance_valid(_death):
		return "death"
	if _card != null and is_instance_valid(_card) and not _card.is_queued_for_deletion():
		return "card"
	for n in order:
		if FULLSCREEN.has(n):
			return "panel"
	return ""


func is_hushed() -> bool:
	return hush_reason() != ""


## Applies hush_reason() when it changed: toasts and the quest banner hold (the top layer fades out, their timers
## pause), the HUD holds its tip card and, for a chapter card, hides its gameplay widgets. On release everything
## still due plays in order.
func _sync_hush() -> void:
	var h := hush_reason()
	if h == _hush:
		return
	_hush = h
	var held := h != ""
	var tw := Kit.retween(self, _tw, "hush")
	tw.tween_property(top_layer, "modulate:a", 0.0 if held else 1.0, 0.18 if held else 0.35)
	if toasts.has_method("set_held"):
		toasts.set_held(held)
	if quest_banner.has_method("set_held"):
		quest_banner.set_held(held)
	if hud.has_method("set_hush"):
		hud.set_hush(h)


## The toast column's bottom margin: the default, or high enough to clear the dialogue box (and its speaker tab)
## while a line shows and the box reaches into the toasts' corner (at 16:9 it always does: the box is 900+ px wide).
func toast_bottom_margin() -> float:
	var base := float(TOAST_MARGINS[3])
	var dlg: Variant = hud.get("dialog") if hud != null else null
	if not (dlg is Control) or not is_instance_valid(dlg) or root == null:
		return base
	var d := dlg as Control
	if not d.is_visible_in_tree() or d.modulate.a < 0.05 or not (d.has_method("is_showing") and bool(d.call("is_showing"))):
		return base
	var vs := root.size
	var r := d.get_global_rect()
	var column_left := vs.x - float(TOAST_MARGINS[2]) - toasts_max_width()
	if r.end.x <= column_left:
		return base
	var tab_h := 0.0
	var tab: Variant = d.get("speaker_tab")
	if tab is Control and (tab as Control).visible:
		tab_h = (tab as Control).size.y * 0.55
	return maxf(base, vs.y - (r.position.y - tab_h) + TOAST_DIALOG_GAP)


## Width of the widest toast card (Toasts.MAX_TEXT_W text + icon + padding).
func toasts_max_width() -> float:
	return Toasts.MAX_CARD_W


## The canvas y the toast column must stay below: the bottom of the top-right HUD column (the day dial and, while it
## shows, the goal card at its live height) and of a quest banner wide enough to reach the column, plus
## TOAST_CLEAR_GAP; never lower than TOAST_TOP_CAP of the canvas height. The goal card counts while the gameplay HUD
## fades for a cutscene too, so the column does not jump when it comes back.
func toast_top_limit() -> float:
	var vs := root.size
	var column_left := vs.x - float(TOAST_MARGINS[2]) - toasts_max_width()
	var top := float(TOAST_MARGINS[1])
	var blocks: Array = []
	if hud != null:
		for n in ["dial", "tracker"]:
			var c: Variant = hud.get(n)
			if c is Control and is_instance_valid(c) and (c as Control).is_visible_in_tree():
				blocks.append((c as Control).get_global_rect())
	if quest_banner != null and quest_banner.has_method("resting_rect"):
		blocks.append(quest_banner.call("resting_rect"))
	for b in blocks:
		var r: Rect2 = b
		if r.size.y > 0.0 and r.end.x > column_left:
			top = maxf(top, r.end.y + TOAST_CLEAR_GAP)
	return minf(top, vs.y * TOAST_TOP_CAP)


## Height the toast column may use: from its bottom margin (the larger of the target and the one on screen while it
## slides) up to toast_top_limit().
func toast_room() -> float:
	var bottom := toast_bottom_margin()
	if toast_margin != null:
		bottom = maxf(bottom, float(toast_margin.get_theme_constant("margin_bottom")))
	return maxf(0.0, root.size.y - bottom - toast_top_limit())


func _layout_toasts() -> void:
	if toast_margin == null:
		return
	var want := toast_bottom_margin()
	if toasts.has_method("set_room"):
		toasts.set_room(toast_room())
	if is_equal_approx(want, _toast_bottom):
		return
	var first := _toast_bottom < 0.0
	_toast_bottom = want
	var tw := Kit.retween(self, _tw, "toast_margin")
	if first:
		tw.kill()
		toast_margin.add_theme_constant_override("margin_bottom", int(want))
		return
	var from := float(toast_margin.get_theme_constant("margin_bottom"))
	tw.tween_method(func(v: float) -> void: toast_margin.add_theme_constant_override("margin_bottom", int(round(v))),
		from, want, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


# --- Wardrobe notice (existing saves) ------------------------------------------------------------------

## A loaded journey that has never been told about the wardrobe (GameState.wardrobe.notice_shown false;
## new journeys set it when Krystal is styled on the creation screen).
func wardrobe_notice_pending() -> bool:
	if not GameState.active or _notice_showing:
		return false
	var w: Variant = GameState.wardrobe
	return w is Dictionary and not bool((w as Dictionary).get("notice_shown", false))


## A quiet, safe moment: playing, no menu, no fade or overlay (chapter card, death, ending, the Chapter Two
## card other modules add to overlay_layer), no boss, and either free to save here or standing in a safe
## zone (nothing chasing her).
func wardrobe_notice_safe_now() -> bool:
	if not Game.gameplay_input_allowed() or _fade_busy() or _death != null or _ending != null:
		return false
	if overlay_layer != null and overlay_layer.get_child_count() > 0:
		return false
	if Game.has_method("boss_active") and bool(Game.boss_active()):
		return false
	var can: Dictionary = Game.can_manual_save()
	return bool(can.get("ok", false)) or bool(Game.player_in_safe_zone())


## Polled at 4 Hz while enabled: shows the notice after WARDROBE_NOTICE_SAFE_SECONDS of continuous safe
## play. Returns true when it opened the notice.
func tick_wardrobe_notice(delta: float) -> bool:
	if not wardrobe_notice_pending():
		_notice_safe_t = 0.0
		return false
	_notice_poll_t += delta
	if _notice_poll_t < WARDROBE_NOTICE_POLL:
		return false
	var dt := _notice_poll_t
	_notice_poll_t = 0.0
	if not wardrobe_notice_safe_now():
		_notice_safe_t = 0.0
		return false
	_notice_safe_t += dt
	if _notice_safe_t < WARDROBE_NOTICE_SAFE_SECONDS:
		return false
	show_wardrobe_notice()
	return true


## The dismissible "Your wardrobe is ready" card with a button that opens the wardrobe. Marks it shown at
## once (it never comes back, whatever the answer). Awaitable; returns the choice ("open" / "later" /
## "cancel").
func show_wardrobe_notice() -> String:
	if _notice_showing:
		return "cancel"
	_notice_showing = true
	_notice_safe_t = 0.0
	GameState.wardrobe["notice_shown"] = true
	var pick: String = await confirm(WARDROBE_NOTICE_TITLE, WARDROBE_NOTICE_TEXT,
		[["open", "Open the wardrobe", "AccentButton"], ["later", "Maybe later", ""]])
	_notice_showing = false
	if pick == "open" and is_inside_tree():
		open("wardrobe")
	return pick


## Debug/QA only: --ui-open=<panel> [--ui-args=<json>] --ui-demo[=build|combat] --ui-lore=id,id
## --ui-show=death|ending|ending2|chapter|comfort|wardrobe_notice
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
		"ending2":
			show_chapter_two_ending()
		"chapter":
			show_chapter_card("Chapter One", "The Dimming Ward")
		"comfort":
			show_comfort(true)
		"wardrobe_notice":
			show_wardrobe_notice()
	if Debug.has_arg("ui-open"):
		var a: Variant = JSON.parse_string(Debug.arg("ui-args", "{}"))
		for pn in Debug.arg("ui-open").split(",", false):
			open(String(pn), a if a is Dictionary else {})

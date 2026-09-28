extends Control
## In-game HUD: lays out every HUD widget in screen regions that stay put at any aspect ratio.
##   top-left: health & stamina, active companion, onboarding hints
##   top-right: day/time dial, objective tracker
##   top-centre: boss bar
##   bottom-centre: captions, dialog line, interaction prompt, build bar, hotbar
##   bottom-left: FPS (optional)
## Toasts and the quest banner live in the UI root's top layer (they stay visible over menus).
## Everything is mouse-transparent except the hotbar slots.
## Underground areas (UiUtil.is_underground_area: the Below, Tobin's annex, the Hushed Works) tone the
## parchment HUD down a little (apply_area_look).

const Kit := preload("res://src/ui/ui_kit.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const Vitals := preload("res://src/ui/hud/vitals.gd")
const Hotbar := preload("res://src/ui/hud/hotbar.gd")
const Tracker := preload("res://src/ui/hud/tracker.gd")
const DialogBox := preload("res://src/ui/hud/dialog_box.gd")
const Captions := preload("res://src/ui/hud/captions.gd")
const HintCard := preload("res://src/ui/hud/hint_card.gd")
const BossBar := preload("res://src/ui/hud/boss_bar.gd")
const BuildBar := preload("res://src/ui/hud/build_bar.gd")
const DayDial := preload("res://src/ui/hud/day_dial.gd")
const CompanionBadge := preload("res://src/ui/hud/companion_badge.gd")
const Prompt := preload("res://src/ui/hud/prompt.gd")
const ScreenFx := preload("res://src/ui/hud/screen_fx.gd")

const MARGIN := 34

var fx: Control
var vitals: Control
var companion: Control
var hints: Control
var dial: Control
var tracker: Control
var boss: Control
var dialog: Control
var captions: Control
var prompt: Control
var build_bar: Control
var hotbar: Control
var fps_label: Label
## Regions hidden during cutscenes (dialog & captions stay visible).
var gameplay_regions: Array = []
var _prompt_t := 0.0
var _fps_t := 0.0
var _cinematic := false
var _tw: Dictionary = {}


func _ready() -> void:
	Kit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx = ScreenFx.new()
	add_child(fx)
	# --- top-left ---
	var tl := _region(BoxContainer.ALIGNMENT_BEGIN, [MARGIN, 26, MARGIN, MARGIN])
	vitals = Vitals.new()
	_add(tl, vitals, Control.SIZE_SHRINK_BEGIN)
	companion = CompanionBadge.new()
	_add(tl, companion, Control.SIZE_SHRINK_BEGIN)
	tl.add_child(Kit.spacer(0, 10))
	hints = HintCard.new()
	_add(tl, hints, Control.SIZE_SHRINK_BEGIN)
	gameplay_regions.append(tl.get_parent())
	# --- top-right ---
	var tr := _region(BoxContainer.ALIGNMENT_BEGIN, [MARGIN, 24, MARGIN, MARGIN])
	dial = DayDial.new()
	_add(tr, dial, Control.SIZE_SHRINK_END)
	tracker = Tracker.new()
	_add(tr, tracker, Control.SIZE_SHRINK_END)
	gameplay_regions.append(tr.get_parent())
	# --- top-centre ---
	var tc := _region(BoxContainer.ALIGNMENT_BEGIN, [MARGIN, 30, MARGIN, MARGIN])
	boss = BossBar.new()
	_add(tc, boss, Control.SIZE_SHRINK_CENTER)
	# --- bottom-centre: story lines stack above the gameplay widgets ---
	var bc := _region(BoxContainer.ALIGNMENT_END, [MARGIN, MARGIN, MARGIN, 24])
	captions = Captions.new()
	_add(bc, captions, Control.SIZE_SHRINK_CENTER)
	dialog = DialogBox.new()
	_add(bc, dialog, Control.SIZE_SHRINK_CENTER)
	bc.add_child(Kit.spacer(0, 6))
	var gp := Kit.vbox(12)
	gp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(bc, gp, Control.SIZE_SHRINK_CENTER)
	prompt = Prompt.new()
	_add(gp, prompt, Control.SIZE_SHRINK_CENTER)
	build_bar = BuildBar.new()
	_add(gp, build_bar, Control.SIZE_SHRINK_CENTER)
	hotbar = Hotbar.new()
	_add(gp, hotbar, Control.SIZE_SHRINK_CENTER)
	gameplay_regions.append(gp)
	# --- bottom-left ---
	var bl := _region(BoxContainer.ALIGNMENT_END, [18, MARGIN, MARGIN, 14])
	fps_label = Kit.label("", "HudSmall")
	_add(bl, fps_label, Control.SIZE_SHRINK_BEGIN)
	fps_label.visible = bool(Settings.get_value("show_fps"))
	Events.cutscene_changed.connect(set_cinematic)
	Events.settings_changed.connect(_on_settings_changed)
	Events.player_died.connect(func() -> void: set_cinematic(true))
	Events.player_respawned.connect(func() -> void: set_cinematic(false))
	Events.area_loaded.connect(_on_area_loaded)
	apply_area_look(Game.area_id)


func _on_area_loaded(a: String) -> void:
	apply_area_look(a)
	if Game.mode == "playing":
		set_cinematic(false)


## The parchment HUD is toned down a little in the dark places underground (keeps the current alpha).
func apply_area_look(area_id: String) -> void:
	var tint := UiUtil.hud_tint(area_id)
	modulate = Color(tint.r, tint.g, tint.b, modulate.a)


func _region(align: BoxContainer.AlignmentMode, m: Array) -> VBoxContainer:
	var mc := Kit.margin(m)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Kit.full_rect(mc))
	var v := Kit.vbox(12)
	v.alignment = align
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(v)
	return v


func _add(region: VBoxContainer, c: Control, hflag: int) -> void:
	c.size_flags_horizontal = hflag
	region.add_child(c)


func _on_settings_changed(key: String) -> void:
	if key == "show_fps":
		fps_label.visible = bool(Settings.get_value("show_fps"))


## Hides gameplay widgets (bars, tracker, hotbar, prompt) with a fade; story lines stay visible.
func set_cinematic(on: bool) -> void:
	if on == _cinematic:
		return
	_cinematic = on
	var tw := Kit.retween(self, _tw, "cine")
	tw.set_parallel(true)
	for r in gameplay_regions:
		tw.tween_property(r, "modulate:a", 0.0 if on else 1.0, 0.5)


func is_cinematic() -> bool:
	return _cinematic


func _process(delta: float) -> void:
	_prompt_t -= delta
	if _prompt_t <= 0.0:
		_prompt_t = 0.08
		_update_prompt()
	if fps_label.visible:
		_fps_t -= delta
		if _fps_t <= 0.0:
			_fps_t = 0.5
			fps_label.text = "%d FPS" % int(Engine.get_frames_per_second())


func _update_prompt() -> void:
	var p: Dictionary = {}
	var pl: Node = Game.player
	if Game.mode == "playing" and not Game.is_ui_open() and not _cinematic and pl != null and is_instance_valid(pl):
		var building := false
		var bm: Variant = pl.get("build_mode_active")
		if bm is bool:
			building = bm
		if not building and pl.has_method("get_prompt"):
			var r: Variant = pl.get_prompt()
			if r is Dictionary:
				p = r
	prompt.set_prompt(p)


## Debug/QA: fills HUD widgets with sample content for screenshots. Debug builds only.
## variant: "true" (story & toasts), "build" (build mode bar), "combat" (low health, damage, companion).
func demo(variant: String = "true") -> void:
	if not Debug.is_cheat_allowed():
		return
	match variant:
		"build":
			Events.build_mode_changed.emit(true)
			Events.build_selection_changed.emit("workbench")
			Events.build_placement_state.emit(false, "Too close to the Ward Stone")
		"combat":
			for id in ItemDB.creature_ids():
				if GameState.is_befriended(String(id)):
					GameState.set_companion_assignment(String(id), "follow")
					GameState.add_bond(String(id), 30)
					break
			GameState.player["hp"] = 22.0
			var h: Variant = Game.player.get("health") if Game.player != null else null
			if h is Node:
				(h as Node).call("set_hp", 22.0)
			GameState.player["stamina"] = 35.0
			Events.player_damaged.emit(12.0, null)
			Events.screen_flash.emit(Color(1, 0.9, 0.7, 0.5), 0.6)
			prompt.set_prompt({"text": "Light the brazier", "action": "interact", "enabled": false, "reason": "You need your lantern"})
		_:
			prompt.set_prompt({"text": "Pick up Wood", "action": "interact"})
			Events.hint.emit("demo_hint", "Press {craft} to open crafting. Select the Stone Axe and press Craft.")
			Events.say.emit("Ward Stone", "Light kept, home kept. The seed sleeps below; the stone remembers.", 30.0)
			Events.caption.emit("[distant pickaxe strikes]")
			Events.notify.emit("Backpack full! 2 Stone dropped nearby.", "warn")
			Events.notify.emit("Mochi's bond grew! (2/5)", "bond")
			Events.item_added.emit("wood", 3)
			Events.item_added.emit("berries", 2)
			Events.notify.emit("New goal: A Timid Friend", "quest")
			Events.boss_health_changed.emit("weaver_matron", 170.0, 240.0)

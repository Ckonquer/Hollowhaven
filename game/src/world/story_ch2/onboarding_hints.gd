extends Node
## First-time onboarding hints for the Chapter Two systems (module D4). ONE instance lives under the Game
## autoload for the whole session (hook for Game.wire_session_systems(): attach(self), idempotent; headless runs
## never step it by themselves, tests call tick()). It only LISTENS to
## Events, "arms" a hint when its moment comes and later emits it through Events.hint, where the HUD hint card
## (src/ui/hud/hint_card.gd) shows it and remembers it in the GameState flag "hint_<id>" (once per save; the
## Settings "Show tips again" button clears those flags like every other hint). Nothing else is written: no
## story flag, no reward, no quest state.
##
## Rules (all checked when a hint is about to be shown, never per frame):
##   * each id at most once per save: an id whose flag "hint_<id>" is set is never armed or emitted again; when
##     no hint card is listening (fallback UI) this module sets that flag itself after emitting
##   * Settings "show_hints" off: nothing is armed or emitted (armed hints are dropped, not marked)
##   * never while: not playing (title, loading, death screen, cutscenes - Game.mode), a menu / pause / fade is
##     up (Game.gameplay_input_allowed), a boss encounter is active (Game.boss_active), inside an Echo Trial
##     (TRIAL_AREAS: a remembered boss fight, and nothing is written there), an ordinary fight is on
##     (Events.combat_state_changed from the music director's threat monitor), the horror director is in
##     anticipation / encounter or held by an authored scene, within HORROR_QUIET seconds of any
##     Events.horror_event (director events and authored moments), outside a safe zone in a horror-director area
##     (the Below, the Hushed Works), while the "Your wardrobe is ready" card is still due, or while the HUD
##     hint card is still showing / queueing another tip (one tip at a time, never stacked behind boss tips)
##   * the moment must stay calm for CALM_SECONDS, and two of these hints are at least MIN_GAP seconds apart
##   * a hint may also wait for its area ("where"), a follower, or some minutes of play (new journeys start quietly)
##   * hints made redundant by play (a furnace already used, the invitation already accepted...) are dropped
## Timers only run while the game is unpaused (process_mode PAUSABLE); the work runs every STEP_SECONDS.
## Key names use the HUD's {token} system (src/ui/ui_util.gd TOKEN_ACTIONS). The build-mode keys (undo, recolour)
## use their {undo} / {recolor} tokens once Settings binds the actions (pass-2 D03: rebindable build_undo Z,
## build_recolor P, build_variant N); without the action the label is read from build_mode.gd key_label() instead.
## Texts are arachnophobia-neutral (nothing spider-like is named) and every statement is checked against the code.
## Echo Trials (pass-2 P49): ONE generic hint "ob_echo_trial" for every echo stone. Its "where" is the keyword
## "echo_origin": the area Krystal is in is the origin of a trial whose story fight is won (data/trials.gd: the Below
## after weaver_defeated, the manor after ch2_velour_defeated, the Hushed Works after ch2_choir_defeated; each trial
## opens right after its boss is defeated - lead decision L07, no ch2_trials_open gate). Armed on arrival there, and
## live when a Chapter Two boss falls (ECHO_LIVE_FLAGS; Chapter One's return home is never interrupted by it);
## dropped once any trial has a clear.
##
## Public API:
##   static attach(parent: Node) -> Node     creates the single instance under `parent` (idempotent)
##   arm(id, delay := 0.0) -> bool            queue a hint (false: unknown, already shown, hints off, no journey)
##   tick(dt) -> String                       one step (tests drive it); returns the id emitted or ""
##   suppression_reason() -> String           "" when a hint may appear now, else why not
##   is_shown(id) -> bool / armed_ids() -> Array / hint_text(id) -> String / static build_key(action, token)

const UiUtil := preload("res://src/ui/ui_util.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const TrialsData := preload("res://data/trials.gd")

const NODE_NAME := "OnboardingHints"
const GROUP := "onboarding_hints"
const FLAG_PREFIX := "hint_"                  # hint_card.gd's once-per-save memory
const BUILD_MODE_SCRIPT := "res://src/building/build_mode.gd"
const BUILD_CH2_HINT := "build_controls_ch2"  # build_mode.gd's own first-entry tip (names the undo key)

const STEP_SECONDS := 0.5
const CALM_SECONDS := 2.5
const MIN_GAP := 25.0
const HORROR_QUIET := 30.0
const HORROR_STATES := ["anticipation", "encounter"]
const OUTDOOR := ["surface", "hallowmere_reach"]
const TRIAL_AREAS := ["echo_trial"]           # Echo Trials (every trial runs in this one area)
const UNDO_AFTER_PLACEMENTS := 3              # pieces placed this session before the undo tip
const WARDROBE_MIN_PLAY := 300.0              # play_seconds: a new journey is styled at creation, told later
const OPTIONAL_MIN_PLAY := 600.0
const COMPANION_MENU_AFTER_SKILL := 90.0
## "where" keywords besides a real area id: "" anywhere, "outdoor" (OUTDOOR), "echo_origin" (see the header).
const WHERE_KEYWORDS := ["", "outdoor", "echo_origin"]
## Chapter Two boss flags that arm the echo trial hint the moment they are set (the stone appears at once).
const ECHO_LIVE_FLAGS := ["ch2_velour_defeated", "ch2_choir_defeated"]
const ECHO_LIVE_DELAY := 30.0

## id -> {"where": "" (anywhere) | area id | "outdoor" | "echo_origin", "text"}. Texts marked "%s" are completed by
## hint_text().
const HINTS := {
	"ob_ch2_invitation": {"where": "surface",
		"text": "The Ward Stone in your Haven has a new inscription. Read it with {interact} whenever you like: nothing changes until you choose to follow the lantern road."},
	"ob_wardrobe": {"where": "outdoor",
		"text": "Change Krystal's look any time: press {wardrobe}, or {pause} > Wardrobe, or build a Wardrobe or Vanity Mirror at the Workbench. Clothes are only for looks: your armor still protects you."},
	"ob_reach_home": {"where": "hallowmere_reach",
		"text": "The waygate where you arrived always leads home to Hollowhaven Woods. Your Haven stays just as you left it."},
	"ob_lantern_road": {"where": "outdoor",
		"text": "Lit arches are safe spots on the Lantern Road. Press {interact} at any lit arch to travel between them or home to the Haven. At home, the Ward Stone can send you back."},
	"ob_echo_trial": {"where": "echo_origin",
		"text": "An echo stone waits by the lantern or candles before each great fight you have won. Press {interact} there to replay that fight as a memory, for a reward. Nothing on your journey changes."},
	"ob_companion_skill": {"where": "", "text": ""},   # built by companion_skill_text() (reads the two companion settings)
	"ob_equipment": {"where": "",
		"text": "New gear! Open your backpack ({inventory}) and drag armor or a charm onto the Equipped column, or double-click it. The stats card shows what it adds."},
	"ob_wand": {"where": "",
		"text": "The Sparkseed Wand flicks a spark at foes from a distance. Select it on your hotbar and press {attack}; each spark uses a little stamina."},
	"ob_storage": {"where": "",
		"text": "Backpack full: the rest waits safely on the ground. The Loom sews a bigger backpack, and a storage chest can grow to 40 slots from its own menu."},
	"ob_furnace": {"where": "",
		"text": "Ore can become bars now: build a Furnace at the Workbench and queue a few batches. They keep smelting while you play."},
	"ob_loom": {"where": "",
		"text": "Your Loom also sews bigger backpacks (40, then 48 slots) and mixes dyes: new colours for clothes in the Wardrobe and for furniture in build mode."},
	"ob_recolour": {"where": "",
		"text": "New dye! In build mode ({build}), point at a piece and press %s to recolour it; press again for the next colour. It's free and changes nothing else."},
	"ob_stairs": {"where": "",
		"text": "Stairs lead up! Add Upper Floor tiles at the top. Each tile needs a full wall, window, doorway or porch post under an edge, or a held-up neighbour."},
	"ob_undo": {"where": "",
		"text": "Placed a piece in the wrong spot? In build mode, press %s to take back your last piece with a full refund (press it twice to be sure)."},
	"ob_crops": {"where": "",
		"text": "Pumpkin seeds grow in a Crop Plot or Sturdy Planter, just like sweetroot. Pumpkins take the longest, and every harvest gives seeds back."},
	"ob_companion_menu": {"where": "",
		"text": "Press {interact} on a friend for their menu: Assist or Stay close in fights, their skill, a home spot and more. {companion} still asks them to follow or wait."},
	"ob_mastery": {"where": "",
		"text": "A mastery grew! Gathering, hearthcraft and wayfinding rise with ordinary play and bring small bonuses. See them in your Journal ({journal}) > Mastery."},
	"ob_chest_crafting": {"where": "",
		"text": "Crafting tip: tick \"Also use nearby chests\" in the crafting menu ({craft}) to use ingredients from your chests close by."},
	"ob_expedition_board": {"where": "outdoor",
		"text": "New at the Workbench: the Expedition Board. Place it at home and press {interact} there to set out on a Lanternwake Expedition, one of three hand-made routes through Hallowmere Reach."},
	"ob_optional": {"where": "surface",
		"text": "Your Journal ({journal}) has an Optional tab: little side stories and things to make, whenever you like."},
}

## Emission priority (first = most urgent). Every HINTS id exactly once (tested).
const ORDER := ["ob_ch2_invitation", "ob_reach_home", "ob_lantern_road", "ob_echo_trial", "ob_companion_skill",
	"ob_equipment", "ob_wand", "ob_storage", "ob_furnace", "ob_loom", "ob_recolour", "ob_stairs", "ob_undo",
	"ob_crops", "ob_wardrobe", "ob_companion_menu", "ob_mastery", "ob_chest_crafting", "ob_expedition_board",
	"ob_optional"]

## Items whose arrival (picked up, crafted, given) arms a hint.
const ITEM_TRIGGERS := {"copper_ore": "ob_furnace", "iron_ore": "ob_furnace", "sparkseed_wand": "ob_wand",
	"pumpkin_seeds": "ob_crops"}
const GEAR_CATEGORIES := ["armor", "charm"]
const STRUCTURE_TRIGGERS := {"wood_stairs": "ob_stairs", "loom": "ob_loom"}
## Build-mode keys without a Settings action (older settings code) and without a build-mode label: the wording used.
const BUILD_KEY_FALLBACK := {"build_undo": "the Undo key on the build bar", "build_recolor": "the Recolour key on the build bar"}

## Steps by itself every STEP_SECONDS (off in headless runs: tests call tick()).
var auto_tick: bool = DisplayServer.get_name() != "headless"
var last_emitted: String = ""
var emitted_count: int = 0

var _armed: Dictionary = {}            # id -> seconds of play left before it may be shown
var _calm_t := 0.0
var _gap := 0.0
var _horror_quiet := 0.0
var _horror_state := ""
var _in_combat := false                # Events.combat_state_changed (ordinary fights)
var _acc := 0.0
var _placed := 0                       # pieces placed this session (undo tip)


## Creates the single instance under `parent` (the Game autoload) or returns the existing one. Idempotent, so
## Game.wire_session_systems() may call it again (the test runner re-wires between suites).
static func attach(parent: Node) -> Node:
	if parent == null:
		return null
	for c in parent.get_children():
		if c.is_in_group(GROUP) and not c.is_queued_for_deletion():
			return c
	var s: Variant = load("res://src/world/story_ch2/onboarding_hints.gd")
	if not (s is Script):
		return null
	var n: Node = (s as Script).new()
	n.name = NODE_NAME
	parent.add_child(n)
	return n


func _ready() -> void:
	name = NODE_NAME
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(GROUP)
	# Headless runs (the unit-test runner) never step by themselves: tests drive tick(), and no other suite ever
	# sees an onboarding hint or a hint_ob_* flag appear on its own (like Game.autosave_enabled).
	set_process(auto_tick)
	for pair in _connections():
		var sig: Signal = pair[0]
		if not sig.is_connected(pair[1]):
			sig.connect(pair[1])


func _exit_tree() -> void:
	for pair in _connections():
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _connections() -> Array:
	return [[Events.area_loaded, _on_area_loaded], [Events.area_exiting, _on_area_exiting],
		[Events.game_loaded, _on_game_loaded], [Events.settings_changed, _on_settings_changed],
		[Events.flag_set, _on_flag_set], [Events.item_added, _on_item_added], [Events.crafted, _on_crafted],
		[Events.structure_placed, _on_structure_placed], [Events.item_overflow_dropped, _on_overflow],
		[Events.companion_attacked, _on_companion_attacked], [Events.companion_skill_used, _on_skill_used],
		[Events.companion_skill_ready, _on_skill_ready], [Events.companion_befriended, _on_befriended],
		[Events.mastery_changed, _on_mastery_changed], [Events.arch_lit, _on_arch_lit],
		[Events.appearance_changed, _on_appearance_changed], [Events.horror_event, _on_horror_event],
		[Events.horror_state_changed, _on_horror_state], [Events.combat_state_changed, _on_combat_state],
		[Events.player_died, _on_player_died]]


func _process(delta: float) -> void:
	_acc += delta
	if _acc < STEP_SECONDS:
		return
	var dt := _acc
	_acc = 0.0
	tick(dt)


# --- Public API ----------------------------------------------------------------------------------------------

## Queues a hint to be shown once its moment is calm (and `delay` seconds of unpaused play have passed). Returns
## false for unknown ids, hints already shown in this save, hints off, or no journey loaded.
func arm(id: String, delay: float = 0.0) -> bool:
	if not HINTS.has(id) or not GameState.active or not hints_on() or is_shown(id):
		return false
	var d := maxf(0.0, delay)
	if _armed.has(id):
		_armed[id] = minf(float(_armed[id]), d)
	else:
		_armed[id] = d
	return true


## True once this save has shown (or been offered) the hint.
func is_shown(id: String) -> bool:
	return _truthy(GameState.get_flag(FLAG_PREFIX + id))


func armed_ids() -> Array:
	return _armed.keys()


func hints_on() -> bool:
	return _truthy(Settings.get_value("show_hints"))


## One step: counts down timers, then shows at most one armed hint when the moment allows. Returns its id or "".
func tick(dt: float) -> String:
	if not GameState.active or Game.mode == "title" or Game.mode == "boot":
		_reset_session()
		return ""
	if not hints_on():
		_armed.clear()
		_calm_t = 0.0
		return ""
	_horror_quiet = maxf(0.0, _horror_quiet - dt)
	_gap = maxf(0.0, _gap - dt)
	if not _armed.has("ob_wardrobe") and _notice_shown() and not is_shown("ob_wardrobe"):
		arm("ob_wardrobe", 5.0)       # the one-time "Your wardrobe is ready" card was answered (existing saves)
	if _armed.is_empty():
		return ""
	if Game.mode == "playing":
		for id in _armed:
			_armed[id] = maxf(0.0, float(_armed[id]) - dt)
	if suppression_reason() != "":
		_calm_t = 0.0
		return ""
	_calm_t += dt
	if _calm_t < CALM_SECONDS or _gap > 0.0:
		return ""
	var pick := _pick()
	if pick == "":
		return ""
	return _emit(pick)


## "" when a hint may appear right now; otherwise the reason it may not.
func suppression_reason() -> String:
	if not GameState.active:
		return "inactive"
	if not hints_on():
		return "hints_off"
	if Game.mode == "cutscene":
		return "cutscene"
	if Game.mode != "playing":
		return "not_playing"
	if Game.ui == null or not is_instance_valid(Game.ui):
		return "no_ui"
	if not Game.gameplay_input_allowed():
		return "busy"
	if Game.boss_active():
		return "boss"
	if TRIAL_AREAS.has(Game.area_id):
		return "trial"
	if _in_combat:
		return "combat"
	if _horror_quiet > 0.0 or HORROR_STATES.has(_horror_state):
		return "horror"
	var d: Variant = Game.director
	if is_instance_valid(d) and d is Node:        # validity first: `is` on a freed director errors
		if (d as Node).has_method("get_state") and HORROR_STATES.has(String((d as Node).call("get_state"))):
			return "horror"
		if (d as Node).has_method("is_held") and bool((d as Node).call("is_held")):
			return "horror"
	if Game.DIRECTOR_AREAS.has(Game.area_id) and not Game.in_safe_zone:
		return "unsafe"
	# The "Your wardrobe is ready" card comes first (only where the UI actually shows it: not headless / QA boots).
	if Game.ui.has_method("wardrobe_notice_pending") and _truthy(Game.ui.get("wardrobe_notice_enabled")) \
			and bool(Game.ui.call("wardrobe_notice_pending")):
		return "notice"
	if _card_busy():
		return "card"
	return ""


## The HUD hint card (ui_root.hud.hints) is showing or queueing a tip: wait for it to be free.
func _card_busy() -> bool:
	var hud: Variant = Game.ui.get("hud")
	if not is_instance_valid(hud) or not (hud is Node):
		return false
	var card: Variant = (hud as Node).get("hints")
	if not is_instance_valid(card) or not (card is Node):
		return false
	if (card as Node).has_method("is_showing") and bool((card as Node).call("is_showing")):
		return true
	return (card as Node).has_method("queued_count") and int((card as Node).call("queued_count")) > 0


## The text of a hint as it is emitted (tokens are filled in by the HUD).
func hint_text(id: String) -> String:
	match id:
		"ob_companion_skill":
			return companion_skill_text(_truthy(Settings.get_value("companion_auto_attack")),
				_truthy(Settings.get_value("companion_autocast")))
		"ob_recolour":
			return String(HINTS[id]["text"]) % build_key("build_recolor", "recolor")
		"ob_undo":
			return String(HINTS[id]["text"]) % build_key("build_undo", "undo")
	var h: Variant = HINTS.get(id, {})
	return String((h as Dictionary).get("text", "")) if h is Dictionary else ""


## The companion support hint, worded for the two companion settings (Settings > Gameplay).
static func companion_skill_text(auto_attack: bool, autocast: bool) -> String:
	var lead := "Friends now help in fights" if auto_attack else "Friends now support you"
	var use := "They use it when it helps, or press {skill} yourself." if autocast else "Press {skill} to use it."
	return "%s, and each has a special skill: Mochi heals, Pebble shields, Lumi quickens your step. %s The ring round their portrait shows when it's ready." % [lead, use]


## A build-mode key for hint text: the HUD token once the integrator adds it (and the action exists), else the
## key build mode really listens to (build_mode.gd key_label), else a description of where to find it.
static func build_key(action: String, token: String) -> String:
	if UiUtil.TOKEN_ACTIONS.has(token) and InputMap.has_action(action):
		return "{%s}" % token
	var label := ""
	if ResourceLoader.exists(BUILD_MODE_SCRIPT):
		var s: Variant = load(BUILD_MODE_SCRIPT)
		if s is Script and (s as Script).has_method("key_label"):
			label = String((s as Script).call("key_label", action))
	if label == "" or label == "-" or label == "?":
		return String(BUILD_KEY_FALLBACK.get(action, "its key on the build bar"))
	return label


# --- Choosing and emitting -------------------------------------------------------------------------------------

func _pick() -> String:
	var drop: Array = []
	var pick := ""
	for id in ORDER:
		if not _armed.has(id):
			continue
		if is_shown(id):
			drop.append(id)
			continue
		if float(_armed[id]) > 0.0 or not _where_ok(id) or _waiting(id):
			continue
		if _obsolete(id):          # checked last: only for a hint that could otherwise be shown now
			drop.append(id)
			continue
		pick = id
		break
	for id in drop:
		_armed.erase(id)
	return pick


func _emit(id: String) -> String:
	_armed.erase(id)
	var text := hint_text(id)
	if text.strip_edges() == "":
		return ""
	Events.hint.emit(id, text)
	var flag := FLAG_PREFIX + id
	if not _truthy(GameState.get_flag(flag)):
		GameState.set_flag(flag, true)     # no hint card listening (fallback UI): still offered once per save
	_gap = MIN_GAP
	_calm_t = 0.0
	last_emitted = id
	emitted_count += 1
	if id == "ob_companion_skill":
		arm("ob_companion_menu", COMPANION_MENU_AFTER_SKILL)
	return id


func _where_ok(id: String) -> bool:
	var w := String((HINTS[id] as Dictionary).get("where", ""))
	if w == "":
		return true
	if w == "outdoor":
		return OUTDOOR.has(Game.area_id)
	if w == "echo_origin":
		return echo_stone_here(Game.area_id)
	return Game.area_id == w


## True when `area_id` is the origin of an echo trial whose story fight is won (its echo stone stands there).
static func echo_stone_here(area_id: String) -> bool:
	for id in TrialsData.ORDER:
		var t: Dictionary = TrialsData.trial(String(id))
		var origin: Variant = t.get("origin", {})
		if not (origin is Dictionary) or String((origin as Dictionary).get("area", "")) != area_id:
			continue
		if _truthy(GameState.get_flag(String(t.get("requires_flag", "")))):
			return true
	return false


## True once any echo trial has been cleared (the stones need no more introduction).
static func any_trial_cleared() -> bool:
	var trials: Variant = GameState.trials
	if not (trials is Dictionary):
		return false
	for id in trials:
		var r: Variant = (trials as Dictionary)[id]
		if r is Dictionary and int((r as Dictionary).get("clears", 0)) > 0:
			return true
	return false


## Made redundant by play: dropped without being marked.
func _obsolete(id: String) -> bool:
	match id:
		"ob_ch2_invitation":
			return not GameState.chapter2.is_available() or GameState.chapter2.is_active()
		"ob_furnace":
			return is_shown("furnace_queue") or GameState.count_structures("furnace") > 0
		"ob_expedition_board":
			return GameState.count_structures("expedition_board") > 0
		"ob_undo":
			# build_mode.gd already told her the undo key on entering build mode (its own tip "build_controls_ch2").
			return is_shown(BUILD_CH2_HINT)
		"ob_echo_trial":
			return any_trial_cleared()
		"ob_optional":
			return (GameState.optional_goals.pending_goals() as Array).is_empty()
	return false


## Not yet: keeps the hint armed.
func _waiting(id: String) -> bool:
	match id:
		"ob_companion_skill", "ob_companion_menu":
			return not _has_follower()
		"ob_wardrobe":
			return _play_seconds() < WARDROBE_MIN_PLAY
		"ob_optional":
			return _play_seconds() < OPTIONAL_MIN_PLAY
	return false


func _reset_session() -> void:
	_armed.clear()
	_calm_t = 0.0
	_gap = 0.0
	_horror_quiet = 0.0
	_horror_state = ""
	_in_combat = false
	_placed = 0


# --- Triggers --------------------------------------------------------------------------------------------------

func _on_area_loaded(area_id: String) -> void:
	_horror_state = ""
	_in_combat = false         # the music director clears its threat on leaving an area without a signal
	_calm_t = 0.0
	if not GameState.active:
		return
	match area_id:
		"surface":
			if GameState.chapter2.is_available() and not GameState.chapter2.is_active():
				arm("ob_ch2_invitation", 3.0)
			if _truthy(GameState.get_flag("ch2_choir_defeated")):
				arm("ob_expedition_board", 20.0)
			arm("ob_optional", 120.0)
		"hallowmere_reach":
			arm("ob_reach_home", 3.0)
			if _any_arch_lit():
				arm("ob_lantern_road", 20.0)
	if echo_stone_here(area_id):
		arm("ob_echo_trial", 3.0)
	if _has_follower():
		arm("ob_companion_skill", 45.0)
	if _owns_dye():
		arm("ob_recolour", 30.0)
	if _any_mastery_rank():
		arm("ob_mastery", 60.0)
	if _notice_shown():
		arm("ob_wardrobe", 20.0)


func _on_area_exiting(_area_id: String) -> void:
	_horror_state = ""
	_in_combat = false


func _on_game_loaded() -> void:
	_reset_session()


func _on_settings_changed(key: String) -> void:
	if key == "show_hints" and not hints_on():
		_armed.clear()


func _on_flag_set(flag_name: String, _value: Variant) -> void:
	if flag_name.begins_with(FLAG_PREFIX) or not GameState.active:
		return
	match flag_name:
		"chapter_one_complete":
			arm("ob_ch2_invitation", 20.0)
		"ch2_choir_defeated":
			arm("ob_expedition_board", 30.0)
	if ECHO_LIVE_FLAGS.has(flag_name):
		arm("ob_echo_trial", ECHO_LIVE_DELAY)      # waits for the stone's area ("echo_origin") and a calm moment


func _on_item_added(item_id: String, _count: int) -> void:
	if not GameState.active or item_id == "":
		return
	if ITEM_TRIGGERS.has(item_id):
		arm(String(ITEM_TRIGGERS[item_id]), 1.0)
	if ItemDB.has_item(item_id) and GEAR_CATEGORIES.has(String(ItemDB.item(item_id).get("cat", ""))):
		arm("ob_equipment", 1.0)


func _on_crafted(recipe_id: String, item_id: String, count: int) -> void:
	if not GameState.active:
		return
	if recipe_id.begins_with("dye:"):
		arm("ob_recolour", 1.0)
	_on_item_added(item_id, count)
	if not GameState.storages.is_empty():
		arm("ob_chest_crafting", 4.0)


func _on_structure_placed(_uid: String, structure_id: String) -> void:
	if not GameState.active:
		return
	if STRUCTURE_TRIGGERS.has(structure_id):
		arm(String(STRUCTURE_TRIGGERS[structure_id]), 1.0)
	_placed += 1
	if _placed >= UNDO_AFTER_PLACEMENTS:
		arm("ob_undo", 2.0)


func _on_overflow(_item_id: String, _count: int, _pos: Vector3) -> void:
	arm("ob_storage", 1.0)


func _on_companion_attacked(_companion_id: String, _target: Node) -> void:
	arm("ob_companion_skill", 0.0)


func _on_skill_used(_companion_id: String, _skill_id: String) -> void:
	arm("ob_companion_skill", 0.0)
	arm("ob_companion_menu", 20.0)


func _on_skill_ready(_companion_id: String) -> void:
	arm("ob_companion_skill", 0.0)


func _on_befriended(_companion_id: String) -> void:
	arm("ob_companion_skill", 30.0)


func _on_mastery_changed(_track: String, _xp: int, rank: int) -> void:
	if rank >= 1:
		arm("ob_mastery", 3.0)


func _on_arch_lit(_arch_id: String) -> void:
	arm("ob_lantern_road", 6.0)


func _on_appearance_changed() -> void:
	if Game.mode == "playing":
		arm("ob_wardrobe", 5.0)


func _on_horror_event(_event_id: String, _data: Dictionary) -> void:
	_horror_quiet = HORROR_QUIET
	_calm_t = 0.0


func _on_horror_state(state: String) -> void:
	_horror_state = state


func _on_combat_state(in_combat: bool) -> void:
	_in_combat = in_combat
	if in_combat:
		_calm_t = 0.0


func _on_player_died() -> void:
	_in_combat = false         # the music director clears its threat on death without a signal
	_calm_t = 0.0


# --- State helpers ---------------------------------------------------------------------------------------------

func _has_follower() -> bool:
	var c := GameState.active_companion
	return c != "" and GameState.companions.has(c) and GameState.is_befriended(c)


func _notice_shown() -> bool:
	var w: Variant = GameState.wardrobe
	return w is Dictionary and _truthy((w as Dictionary).get("notice_shown", false))


func _owns_dye() -> bool:
	var w: Variant = GameState.wardrobe
	if not (w is Dictionary):
		return false
	var p: Variant = (w as Dictionary).get("palettes", [])
	return p is Array and not (p as Array).is_empty()


func _any_mastery_rank() -> bool:
	for t in GameState.MASTERY_TRACKS:
		if ItemDB.mastery_rank(String(t)) >= 1:
			return true
	return false


func _any_arch_lit() -> bool:
	for id in Reach.ARCH_ORDER:
		if _truthy(GameState.get_flag("ch2_arch_" + String(id))):
			return true
	return false


func _play_seconds() -> float:
	var v: Variant = GameState.stats.get("play_seconds", 0.0)
	return float(v) if (v is float or v is int) else 0.0


## Flags may hold any JSON value; compare by type first (Godot raises on e.g. String == bool).
static func _truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v) != 0
		TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v) != ""
	return true

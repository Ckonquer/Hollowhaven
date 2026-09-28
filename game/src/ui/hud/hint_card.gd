extends PanelContainer
## Onboarding hints (Events.hint): shown once per id (remembered in GameState flags "hint_<id>" so they
## never repeat after loading), key tokens like {interact} become highlighted key labels, can be turned
## off with Settings "show_hints". Queued; each stays long enough to read.
## Visual QA (T4, UI-02, IN-09): `held` (the UI root's hush, through hud.set_hush: a chapter card, a full-screen menu
## or modal card, the ending) fades the card out and pauses it, and new tips wait in the queue. A Chapter Two
## onboarding tip ("ob_*") is re-checked with the OnboardingHints node before it is shown, when it comes back from a
## hold and every RECHECK_SECONDS while it shows: a tip that play has made redundant (the Ward Stone invitation once
## Chapter Two is accepted) is dropped instead of shown stale.
## Fight tips (FIGHT_TIP_PREFIXES: the bosses' and elites' own tips) must not lag behind the fight (final 2.0.1 run: ten
## Crossing Matron tips in 75 s, each 7-13 s long, spilled past her defeat and over the Chapter One ending): a newer
## fight tip replaces an older one still waiting in the queue and cuts the one on screen short after
## FIGHT_TIP_MIN_SECONDS, and when the encounter ends (won, reset or left: Events.boss_encounter_changed false,
## boss_defeated, area_exiting, or its health bar hidden - boss_health_changed hp < 0, the Knotted Elder's only end
## event) the fight tips go at once. A fight tip dropped unshown gets its once-per-save flag back, so a later attempt
## still teaches it.
## Priorities (tip_priority; 2.0.3, native 2.0.2 run: the Quarry Warden's attack tells "tell_quarry_warden_*" queued like
## ordinary tips, showed 15 s late behind two quest tips and lingered 9 s past its defeat, and "the shell is open"
## waited behind them and was dropped unshown): 3 = a fight's openings ("strike now!", OPENING_SUFFIXES), 2 = its other
## instructions, 1 = an elite's attack tells (TELL_PREFIX: the Warden's and the Knotted Elder's data tells), 0 = every
## other tip. A tip queues behind the tips of its own or a higher priority, so fight tips go ahead of ordinary ones; a
## newer fight tip replaces queued fight tips of its own or a lower priority only (a tell never pushes out a waiting
## instruction); the tip on screen - an ordinary one too - makes room after FIGHT_TIP_MIN_SECONDS for a waiting fight tip
## of at least its own priority (an opening for an instruction too; a tell never cuts an instruction short), and after
## only OPENING_MIN_SECONDS for a waiting opening (its window lasts a few seconds). A fight tip cut before
## FIGHT_TIP_MIN_SECONDS gets its flag back (its next emission teaches it); an ordinary tip cut with more than half of its
## reading time left goes back to the head of the ordinary tips and shows that rest once the fight tips are through.
## AFTER_FIGHT_TIPS come from a fight but explain its end (the Warden walking back to its bench, emitted in the same
## frame as its encounter ends): ordinary tips, never dropped by it.

const Kit := preload("res://src/ui/ui_kit.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")

const RECHECK_SECONDS := 0.5
const FIGHT_TIP_PREFIXES := ["boss_", "velour_", "choir_", "hint_quarry_warden_", "tell_quarry_warden_",
	"tell_knotted_elder_"]
const TELL_PREFIX := "tell_"          # enemy_base.announce_tell ids ("tell_<enemy>_<attack>"): a fight's attack tells
const OPENING_SUFFIXES := ["_exposed", "_stuck", "_scorched", "_snapped", "_stranded"]   # "strike now!" windows
const AFTER_FIGHT_TIPS := ["hint_quarry_warden_bench"]   # emitted as its encounter ends: must outlive it
const FIGHT_TIP_MIN_SECONDS := 4.0
const OPENING_MIN_SECONDS := 1.0
const OPENING := 3                    # tip_priority of an opening
const ONBOARDING_GROUP := "onboarding_hints"

var text_l: RichTextLabel
var _queue: Array = []
var _time_left := 0.0
var _full_time := 0.0                 # the reading time the tip on screen started with
var _showing := false
var _tw: Dictionary = {}
var _current_id := ""
var _current_text := ""
var _recheck_t := 0.0
var _shown_t := 0.0                   # seconds the tip on screen has been readable (not held)
var held := false


func _ready() -> void:
	theme_type_variation = "HudCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 470
	var h := Kit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	var ic := Kit.icon_rect(IconFactory.icon("ui_hint", Color.WHITE, 96), 54)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := Kit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := Kit.label("TIP", "Tiny")
	t.add_theme_color_override("font_color", ThemeFactory.ACCENT.darkened(0.2))
	v.add_child(t)
	text_l = Kit.rich("", 370)
	text_l.add_theme_font_size_override("normal_font_size", 22)
	text_l.add_theme_font_size_override("bold_font_size", 22)
	v.add_child(text_l)
	visible = false
	modulate.a = 0.0
	Events.hint.connect(on_hint)
	Events.boss_encounter_changed.connect(func(_id: String, active: bool) -> void:
		if not active:
			drop_fight_tips())
	Events.boss_defeated.connect(func(_id: String) -> void: drop_fight_tips())
	Events.boss_health_changed.connect(func(_id: String, hp: float, _max_hp: float) -> void:
		if hp < 0.0:
			drop_fight_tips())      # its bar hidden: the fight is over (the Knotted Elder's only end event)
	Events.area_exiting.connect(func(_id: String) -> void: drop_fight_tips())
	Events.settings_changed.connect(func(k: String) -> void:
		if k == "show_hints" and not bool(Settings.get_value("show_hints")):
			_queue.clear()
			_hide())


## Formats hint text: tokens -> accent-coloured bold key labels (BBCode).
static func format_hint(text: String, label_fn: Callable) -> String:
	var safe := UiUtil.bb_escape(text)
	var open := "[color=#%s][b]" % ThemeFactory.ACCENT.darkened(0.2).to_html(false)
	return UiUtil.fill_tokens(safe, label_fn, open, "[/b][/color]")


## Returns true if the hint was accepted for display (not shown before and hints enabled).
func on_hint(hint_id: String, text: String) -> bool:
	if not bool(Settings.get_value("show_hints")) or text.strip_edges() == "":
		return false
	var flag := "hint_" + hint_id
	if GameState.get_flag(flag):
		return false
	for q in _queue:
		if String(q["id"]) == hint_id:
			return false
	GameState.set_flag(flag, true)
	var p := tip_priority(hint_id)
	if p > 0:
		_drop_queued_fight_tips(p)     # the newest fight tip matters now (a tell never replaces an instruction)
	_enqueue({"id": hint_id, "text": text}, p, false)
	if not _showing and not held:
		_next()
	return true


static func is_fight_tip(hint_id: String) -> bool:
	if AFTER_FIGHT_TIPS.has(hint_id):
		return false
	for p in FIGHT_TIP_PREFIXES:
		if hint_id.begins_with(String(p)):
			return true
	return false


## 3 (OPENING) = a fight's "strike now" window (OPENING_SUFFIXES: boss_stuck, boss_crossing_exposed, choir_exposed,
## hint_quarry_warden_exposed ...), 2 = a fight's other instructions (boss_*, velour_*, choir_*, hint_quarry_warden_*),
## 1 = an elite's attack tell (tell_quarry_warden_*, tell_knotted_elder_*), 0 = any other tip.
static func tip_priority(hint_id: String) -> int:
	if not is_fight_tip(hint_id):
		return 0
	if hint_id.begins_with(TELL_PREFIX):
		return 1
	for s in OPENING_SUFFIXES:
		if hint_id.ends_with(String(s)):
			return OPENING
	return 2


## Queues `entry` (priority `p`) behind every queued tip of a higher priority and - unless `ahead_of_equals` - of the
## same priority, ahead of the rest.
func _enqueue(entry: Dictionary, p: int, ahead_of_equals: bool) -> void:
	var at := _queue.size()
	for i in _queue.size():
		var qp := tip_priority(String((_queue[i] as Dictionary)["id"]))
		if qp < p or (ahead_of_equals and qp == p):
			at = i
			break
	_queue.insert(at, entry)


## The fight is over (won, reset or left): its tips no longer apply. Queued ones are dropped unshown (flag given back),
## the one on screen leaves now (or, while the card is held, never comes back).
func drop_fight_tips() -> void:
	_drop_queued_fight_tips(OPENING)
	if not _showing or not is_fight_tip(_current_id):
		return
	_showing = false
	_current_id = ""
	if held:
		_hide()
		return
	var tw := Kit.retween(self, _tw, "fade")
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		if not _showing:
			_next())


## Drops the queued fight tips of priority `max_priority` or lower (flags given back).
func _drop_queued_fight_tips(max_priority: int) -> void:
	var keep: Array = []
	for q in _queue:
		var id := String((q as Dictionary)["id"])
		var p := tip_priority(id)
		if p > 0 and p <= max_priority:
			GameState.set_flag("hint_" + id, false)
		else:
			keep.append(q)
	_queue = keep


## True when an onboarding tip ("ob_*") no longer applies: asks the OnboardingHints node (group "onboarding_hints")
## through its public is_obsolete(id) when it has one, else its own redundancy check. Other tips never go stale here.
func is_obsolete(hint_id: String) -> bool:
	if not hint_id.begins_with("ob_") or not is_inside_tree():
		return false
	var ob := get_tree().get_first_node_in_group(ONBOARDING_GROUP)
	if ob == null:
		return false
	for m in ["is_obsolete", "_obsolete"]:
		if ob.has_method(m):
			return bool(ob.call(m, hint_id))
	return false


## Hold (true) or release the card (UI root hush via hud.set_hush). Held: fades out and pauses; released: the tip
## comes back unless it went stale meanwhile, or the next queued tip shows.
func set_held(on: bool) -> void:
	if on == held:
		return
	held = on
	if on:
		if _showing:
			var tw := Kit.retween(self, _tw, "fade")
			tw.tween_property(self, "modulate:a", 0.0, 0.2)
		return
	if _showing:
		if is_obsolete(_current_id):
			_showing = false
			_next()
		else:
			var tw2 := Kit.retween(self, _tw, "fade")
			tw2.tween_property(self, "modulate:a", 1.0, 0.3)
	elif not _queue.is_empty():
		_next()


func current_id() -> String:
	return _current_id if _showing else ""


func _next() -> void:
	while not _queue.is_empty() and is_obsolete(String((_queue[0] as Dictionary)["id"])):
		_queue.pop_front()
	if _queue.is_empty() or held:
		_hide()
		return
	var h: Dictionary = _queue.pop_front()
	_showing = true
	_current_id = String(h["id"])
	_current_text = String(h["text"])
	_recheck_t = RECHECK_SECONDS
	_shown_t = 0.0
	visible = true
	text_l.text = format_hint(_current_text, Callable(UiUtil, "settings_label"))
	# a tip cut short for a fight tip comes back for the rest of its reading time ("time")
	_time_left = float(h["time"]) if h.has("time") else clampf(5.0 + float(_current_text.length()) * 0.06, 7.0, 13.0)
	_full_time = _time_left
	Audio.play_ui("ui_notify", -8.0)
	var tw := Kit.retween(self, _tw, "fade")
	tw.tween_property(self, "modulate:a", 1.0, 0.3)


func _hide() -> void:
	_showing = false
	var tw := Kit.retween(self, _tw, "fade")
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void:
		if not _showing:
			visible = false)


## The highest tip_priority waiting in the queue (0 when none or only ordinary tips wait).
func _waiting_priority() -> int:
	var best := 0
	for q in _queue:
		best = maxi(best, tip_priority(String((q as Dictionary)["id"])))
	return best


## Seconds the tip on screen stays before it makes room for the best waiting tip, or -1.0 when nothing waiting may cut
## it short: a waiting fight tip of at least its priority (an opening on screen: an instruction too - its window is
## over by then; a tell never cuts an instruction or an opening) after FIGHT_TIP_MIN_SECONDS, an opening after
## OPENING_MIN_SECONDS (its window is short; whatever led to it - the pounce, the charge - is over).
func _room_after() -> float:
	var wp := _waiting_priority()
	var cp := tip_priority(_current_id)
	if wp < clampi(cp, 1, 2):
		return -1.0
	return OPENING_MIN_SECONDS if wp == OPENING and cp < OPENING else FIGHT_TIP_MIN_SECONDS


## The tip on screen leaves for a waiting fight tip. An ordinary tip with more than half of its reading time left goes
## back to the head of the ordinary tips, to show that rest once the fight tips are through; a fight tip cut before
## FIGHT_TIP_MIN_SECONDS (by an opening) counts as unread: its flag is given back for its next emission.
func _make_room() -> void:
	if tip_priority(_current_id) == 0:
		if _time_left > _full_time * 0.5:
			_enqueue({"id": _current_id, "text": _current_text, "time": _time_left}, 0, true)
	elif _shown_t < FIGHT_TIP_MIN_SECONDS:
		GameState.set_flag("hint_" + _current_id, false)
	_time_left = 0.0


func is_showing() -> bool:
	return _showing


func queued_count() -> int:
	return _queue.size()


func _process(delta: float) -> void:
	if not _showing or held or Game.is_ui_open():
		return
	_recheck_t -= delta
	if _recheck_t <= 0.0:
		_recheck_t = RECHECK_SECONDS
		if is_obsolete(_current_id):
			_time_left = 0.0     # redundant now: leave early (the next tip follows as usual)
	_shown_t += delta
	_time_left -= delta
	var room := _room_after()
	if room >= 0.0 and _shown_t >= room and _time_left > 0.0:
		_make_room()             # a fight tip that may cut this one short is waiting: make room for it
	if _time_left <= 0.0:
		var tw := Kit.retween(self, _tw, "fade")
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
		_showing = false
		tw.tween_callback(func() -> void:
			if not _showing:
				_next())

extends "res://src/ui/panels/panel_base.gd"
## Music Box panel (MP 18.3), opened by the Music Box furnishing (args {"uid", "source": the box node}).
## Lists the songs Krystal has heard in safe places (src/audio/music_box.gd: discovered cues, catalogue order)
## by title with where each belongs, a Play button per song (a one-pass preview through the music director's
## low-priority "musicbox" context), Stop, and a Favourite toggle per song (favourites get a little extra,
## bounded weight in the Haven's day / night rotation). Everything is text, so it works with the sound off:
## the "Now playing" line names the song and a note says the sound is muted.
## Not full-screen and never pauses: the preview has to be heard while the panel is open, and the world keeps
## living around it (like the Friends panel, it closes when Krystal is hurt). Closing the panel does not stop
## the song; Stop, leaving the house, or any higher-priority music does. Play says so when the song can't
## start right now (a boss, a fight, a horror silence or an authored scene has the music). Polls the preview
## state twice a second (no per-frame work).

const MusicBox := preload("res://src/audio/music_box.gd")
const MapView := preload("res://src/ui/widgets/map_view.gd")

const TEXT_W := 560.0
const LIST_H := 400.0
const POLL_S := 0.5
const INTRO_TEXT := "Songs you have heard in safe places. Play one here, or mark favourites to hear them a little more often at home."
const QUIET_TEXT := "The music box is quiet."
const MUTED_TEXT := "The sound is off, so the music box shows each song's name instead."
const MORE_TEXT := "Explore, rest at home and visit safe places to hear more songs."
const FAILED_TEXT := "That song can't play right now."

var source: Node = null
var _had_source := false
var _now_l: Label
var _stop_btn: Button
var _mute_l: Label
var _note_l: Label
var _count_l: Label
var _list: VBoxContainer
var _rows: Dictionary = {}        # cue -> {"play": Button, "fav": CheckButton}
var _first_play: Button
var _shown: Array = []
var _poll := 0.0
var _state_key := ""


func setup(p_args: Dictionary) -> void:
	super.setup(p_args)
	dim_background = false
	title = "Music Box"
	window_min = Vector2(780, 0)
	_set_source(p_args.get("source"))


func reopen(p_args: Dictionary) -> void:
	args = p_args
	_set_source(p_args.get("source"))
	refresh()


func _set_source(s: Variant) -> void:
	source = s if s is Node and is_instance_valid(s) else null
	_had_source = source != null


func _build() -> void:
	body.add_child(Kit.wrap_label(INTRO_TEXT, "Small", TEXT_W + 120.0))
	var now := Kit.hbox(12)
	_now_l = Kit.wrap_label(QUIET_TEXT, "", TEXT_W)
	_now_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now.add_child(_now_l)
	_stop_btn = Kit.button("Stop", _on_stop)
	_stop_btn.name = "Stop"
	now.add_child(_stop_btn)
	body.add_child(now)
	_mute_l = Kit.wrap_label(MUTED_TEXT, "Small", TEXT_W + 120.0)
	body.add_child(_mute_l)
	_note_l = Kit.wrap_label("", "Small", TEXT_W + 120.0)
	_note_l.visible = false
	body.add_child(_note_l)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(TEXT_W + 140.0, LIST_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = Kit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	body.add_child(scroll)
	_count_l = Kit.label("", "Small")
	body.add_child(_count_l)
	_rebuild_list()
	# Like the Friends menu: the world keeps running but Krystal is held still while the panel is open, so it
	# steps aside the moment she is hurt (a bound-method connection is dropped when the panel is freed).
	Events.player_damaged.connect(_on_player_damaged)


func _rebuild_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	_first_play = null
	_shown = MusicBox.discovered()
	for cue in _shown:
		_list.add_child(_row(String(cue)))
	if _shown.size() <= MusicBox.STARTER_CUES.size():
		_list.add_child(Kit.wrap_label(MORE_TEXT, "Small", TEXT_W))


func _row(cue: String) -> Control:
	var card := Kit.panel("Inset")
	card.name = "Song_" + cue
	var h := Kit.hbox(12)
	card.add_child(h)
	var v := Kit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label(MusicBox.title(cue), "Subheading"))
	v.add_child(Kit.label(location_text(cue), "Small"))
	h.add_child(v)
	var play := Kit.button("Play", _on_play.bind(cue))
	play.name = "Play_" + cue
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(play)
	var fav := CheckButton.new()
	fav.name = "Fav_" + cue
	fav.text = "Favourite"
	fav.tooltip_text = "Favourites play a little more often at home (never instead of the Haven's own songs)."
	fav.add_theme_font_size_override("font_size", 20)
	fav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fav.button_pressed = MusicBox.is_favourite(cue)
	fav.toggled.connect(_on_fav.bind(cue))
	Kit.hook_sounds(fav)
	h.add_child(fav)
	_rows[cue] = {"play": play, "fav": fav}
	if _first_play == null:
		_first_play = play
	return card


## Where a song belongs, for the list ("Krystal's Haven", "Pumpkintide Orchard, after dark"...). Place names come
## from the map (arachnophobia-aware for rooms); the first place it was heard is the fallback.
static func location_text(cue: String) -> String:
	var h := MusicBox.home_of(cue)
	var place := _place(String(h["area"]), String(h["zone"]))
	if place == "":
		place = String(MusicBox.CONTEXT_PLACES.get(String(h["context"]), ""))
	if place == "":
		var at := MusicBox.heard_at(cue)
		place = _place(String(at.get("area", "")), String(at.get("zone", "")))
	if place == "":
		place = "Somewhere along the way"
	if bool(h["night"]):
		place += ", after dark"
	return place


static func _place(area: String, zone: String) -> String:
	var p := MapView.place_name(zone, area) if zone != "" else ""
	if p == "" and area != "":
		p = MapView.area_name(area)
	return p


## The "Now playing" line (text, so it works with the sound off).
static func now_text() -> String:
	var cue := MusicBox.preview_cue()
	if cue == "":
		return QUIET_TEXT
	return "Now playing: %s (%s)" % [MusicBox.title(cue), location_text(cue)]


func refresh() -> void:
	if _now_l == null:
		return
	if MusicBox.discovered() != _shown:
		_rebuild_list()
	var playing := MusicBox.preview_cue()
	_now_l.text = now_text()
	_stop_btn.disabled = playing == ""
	_mute_l.visible = MusicBox.music_muted()
	for cue in _rows:
		var r: Dictionary = _rows[cue]
		var play: Button = r["play"]
		play.text = "Playing" if String(cue) == playing else "Play"
		var fav: CheckButton = r["fav"]
		fav.set_pressed_no_signal(MusicBox.is_favourite(String(cue)))
	var favs := MusicBox.favourites().size()
	var found := "%d of %d songs found" % [_shown.size(), MusicBox.eligible_cues().size()]
	_count_l.text = found + ("  -  %d favourite%s" % [favs, "" if favs == 1 else "s"] if favs > 0 else "")
	_state_key = playing + ("|m" if _mute_l.visible else "")


func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_S:
		return
	_poll = 0.0
	if _had_source and not is_instance_valid(source):
		request_close()               # the box was dismantled while the panel was open
		return
	var key := MusicBox.preview_cue() + ("|m" if MusicBox.music_muted() else "")
	if key != _state_key or MusicBox.discovered().size() != _shown.size():
		refresh()


func _on_play(cue: String) -> void:
	var ok := MusicBox.preview(cue, source if is_instance_valid(source) else null)
	_note_l.text = "" if ok else FAILED_TEXT
	_note_l.visible = not ok
	refresh()


func _on_stop() -> void:
	if MusicBox.preview_cue() != "":
		MusicBox.stop_preview()
		Events.caption.emit(MusicBox.CAPTION_STOP)
	refresh()


func _on_player_damaged(_amount: float, _source: Node) -> void:
	request_close()


func _on_fav(on: bool, cue: String) -> void:
	MusicBox.set_favourite(cue, on)
	refresh()


## Row controls for a song (tests / QA): {"play": Button, "fav": CheckButton} or {}.
func row(cue: String) -> Dictionary:
	return _rows.get(cue, {})


func default_focus() -> Control:
	return _first_play if _first_play != null else _stop_btn

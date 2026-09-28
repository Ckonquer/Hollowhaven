extends "res://src/building/structure.gd"
## Music Box (data interact "music", MP 18.3): a restrained home feature. Interacting opens the Music Box panel
## (src/ui/panels/music_box_panel.gd via Game.open_panel("music_box", panel_args())): the songs Krystal has heard
## in safe places (src/audio/music_box.gd), a Play preview and Favourite toggles for the Haven rotation.
## While a preview started from this box plays, the little star dancer on top turns, and twice a second the box
## checks that Krystal is still at home (MusicBox.should_stop: the box's own area - the Haven, or the Reach
## outpost - and the Haven zone or within HOUSE_RADIUS of the box, not fainted); otherwise it stops the preview. Boss / horror / combat / authored
## music end a preview inside the music director; the dancer then stops too. Dismantling the box stops its
## preview. Until the panel is registered in the UI root it falls back to winding: a soft chime, a caption
## (for players without sound) and a short spin. Only processes while the dancer turns.

const MusicBox := preload("res://src/audio/music_box.gd")

const PANEL := "music_box"
const PLAY_SECONDS := 14.0       # the wind-up fallback
const SPIN_SPEED := 1.6          # rad/s
const CHECK_S := 0.5             # preview checks (house, still playing) - throttled, never per frame

## Tests: {"area", "zone", "pos": Vector3, "mode"} replace what Game reports for the house check.
var where_override: Dictionary = {}

var _left := 0.0
var _previewing := false
var _check_t := 0.0


func _setup_behaviour() -> void:
	set_process(false)
	MusicBox.init()          # discovery listener (idempotent; normally wired once per session by Game)


func is_playing() -> bool:
	return _left > 0.0 or _previewing


## True while a preview started from this box is playing.
func is_previewing() -> bool:
	return _previewing


func get_interaction(_player: Node) -> Dictionary:
	if panel_available():
		return {"text": "Open the music box", "enabled": true}
	return {"text": "Let it rest" if is_playing() else "Wind the music box", "enabled": true}


func interact(_player: Node) -> void:
	if panel_available():
		Game.open_panel(PANEL, panel_args())
		return
	if _left > 0.0:
		_left = 0.0
		return
	_left = PLAY_SECONDS
	set_process(true)
	if is_inside_tree():
		Audio.play_3d("checkpoint_light", global_position + Vector3.UP * 0.4, -6.0)
	Events.caption.emit("A music box plays a little tune")


## Arguments the panel is opened with (the box itself is the preview source).
func panel_args() -> Dictionary:
	return {"uid": uid, "source": self}


func panel_available() -> bool:
	var ui: Variant = Game.ui
	return is_instance_valid(ui) and ui is Node and (ui as Node).has_method("has_panel") \
			and bool((ui as Node).call("has_panel", PANEL))


## MusicBox.preview() calls this on the box a preview was started from.
func on_preview_started(_cue: String) -> void:
	_previewing = true
	_check_t = 0.0
	set_process(true)


func _process(delta: float) -> void:
	var spinner: Variant = parts.get("spinner")
	if spinner is Node3D:
		(spinner as Node3D).rotation.y += SPIN_SPEED * delta
	if _left > 0.0:
		_left = maxf(_left - delta, 0.0)
	if _previewing:
		_check_t += delta
		if _check_t >= CHECK_S:
			_check_t = 0.0
			check_preview()
	if not is_playing():
		set_process(false)


## The throttled check while a preview from this box plays. False once it is over (ended by other music,
## finished, started from another box - or stopped here because Krystal left the house).
func check_preview() -> bool:
	if not _previewing:
		return false
	if MusicBox.preview_cue() == "" or MusicBox.preview_source() != self:
		_previewing = false
		return false
	if left_home():
		MusicBox.stop_preview()
		Events.caption.emit(MusicBox.CAPTION_LEFT)
		_previewing = false
		return false
	return true


## Krystal is no longer at home (or fainted). "Home" is measured from where this box stands (its saved
## area: the Haven, or the Reach outpost), so a box at the outpost plays while she stays beside it.
func left_home() -> bool:
	var w := _where()
	if String(w["mode"]) == "dead":
		return true
	return MusicBox.should_stop(String(w["area"]), String(w["zone"]), w["pos"],
			global_position if is_inside_tree() else position, home_area())


## The area this box stands in (its GameState record; the surface Haven for a box without one).
func home_area() -> String:
	var a: Variant = record().get("area", "")
	return String(a) if (a is String or a is StringName) and String(a) != "" else MusicBox.HOUSE_AREA


func _where() -> Dictionary:
	var here := global_position if is_inside_tree() else position
	var w := {"area": String(Game.area_id), "zone": String(Game.zone_id), "pos": here, "mode": String(Game.mode)}
	var p: Variant = Game.player
	if is_instance_valid(p) and p is Node3D and (p as Node3D).is_inside_tree():
		w["pos"] = (p as Node3D).global_position
	for k in where_override:
		w[k] = where_override[k]
	return w


func play_remove_and_free() -> void:
	if _previewing and MusicBox.preview_source() == self:
		MusicBox.stop_preview()
		Events.caption.emit(MusicBox.CAPTION_STOP)
	_previewing = false
	super.play_remove_and_free()

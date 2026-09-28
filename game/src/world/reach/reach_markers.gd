extends Node3D
## High-visibility wayfinding markers of Hallowmere Reach (Settings "high_visibility_cues"): a bold, outlined,
## gently bobbing diamond (reach_interactable.gd make_marker: shape + outline, never colour alone) over each
## way in, out and onward that the region owns:
##   * every Lantern Road arch until it is lit (flag ch2_arch_<id>)
##   * the mirror waygate home (always)
##   * the top of the Bellhouse stair once it is revealed (ch2_lamps_linked); at its bottom the service gate
##     while it is shut, then the way down in the tower passage once ch2_service_gate_open is recorded
##   * the refuge hatch once the shortcut is open (ch2_refuge_shortcut)
## Follows the setting and the flags live; no processing at all while every marker is hidden.
##   var m = ReachMarkers.new(); add_child(m); m.add_marker("arch_commons", pos, func() -> bool: ...); m.refresh()

const Interactable := preload("res://src/world/reach/reach_interactable.gd")

const SCALE := 1.6
const BOB := 0.12

var entries: Array = []          # [{id, marker: Node3D, y: float, cond: Callable}]
var _t := 0.0


func _ready() -> void:
	name = "HiVisMarkers"
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	if not Events.flag_set.is_connected(_on_flag_set):
		Events.flag_set.connect(_on_flag_set)
	refresh()


## Adds a marker at `pos` (this node's space) shown while the setting is on and `cond` holds (no cond = always).
func add_marker(id: String, pos: Vector3, cond: Callable = Callable()) -> Node3D:
	var m := Interactable.make_marker()
	m.name = "Marker_" + id
	m.scale = Vector3.ONE * SCALE
	m.position = pos
	m.visible = false
	add_child(m)
	entries.append({"id": id, "marker": m, "y": pos.y, "cond": cond})
	return m


func marker(id: String) -> Node3D:
	for e in entries:
		if String(e["id"]) == id:
			return e["marker"]
	return null


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" or key == "":
		refresh()


func _on_flag_set(_flag: String, _value: Variant) -> void:
	if Interactable.hi_vis_on():
		refresh()


func refresh() -> void:
	var on := Interactable.hi_vis_on()
	var any := false
	for e in entries:
		var cond: Callable = e["cond"]
		var vis := on and (not cond.is_valid() or bool(cond.call()))
		(e["marker"] as Node3D).visible = vis
		any = any or vis
	set_process(any)


func _process(delta: float) -> void:
	_t += delta
	var bob := sin(_t * 2.0) * BOB
	for e in entries:
		var m: Node3D = e["marker"]
		if m.visible:
			m.position.y = float(e["y"]) + bob
			m.rotation.y = _t * 0.9

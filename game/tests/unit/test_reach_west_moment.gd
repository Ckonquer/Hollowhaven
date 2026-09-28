extends "res://tests/unit/test_reach_west_fixture.gd"
## "The Pumpkin That Turned" (MP §14, module C2): the once-per-save state machine and its Gentle / Standard /
## Intense variants; it never attacks and is nobody's crop.

const MomentScript := preload("res://src/world/reach/west/pumpkin_moment.gd")

var _captions: Array = []
var _horror: Array = []


func before_each() -> void:
	_captions = []
	_horror = []
	_horror_data = []
	Events.caption.connect(_on_caption)
	Events.horror_event.connect(_on_horror)


func after_each() -> void:
	Events.caption.disconnect(_on_caption)
	Events.horror_event.disconnect(_on_horror)
	await super.after_each()


func _on_caption(t: String) -> void:
	_captions.append(t)


var _horror_data: Array = []


func _on_horror(id: String, d: Dictionary) -> void:
	_horror.append(id)
	_horror_data.append(d)


func _moment(intensity: int) -> Node3D:
	var m: Node3D = MomentScript.new()
	var p: Vector2 = Data.MOMENT["pos"]
	m.setup({"pos": Vector3(p.x, 0.0, p.y), "face_yaw": MomentScript.face_yaw_to(p, Data.MOMENT["face_to"]),
		"turned_yaw": MomentScript.face_yaw_to(p, Data.MOMENT["turned_to"])})
	m.intensity_override = intensity
	add_child(m)
	_hosts.append(m)
	return m


func _at(d: float) -> Vector3:
	var p: Vector2 = Data.MOMENT["pos"]
	return Vector3(p.x + d, 0.0, p.y)


func test_standard_turns_unseen_once_then_teaches_the_twitch() -> void:
	fresh_state()
	var m: Node3D = await _moment(1)
	assert_eq(m.phase, "watch")
	assert_almost(m.pumpkin.rotation.y, m.face_yaw, 0.001, "faces the lane at first")
	assert_eq(m.check(_at(20.0), false), "", "not seen while off screen")
	assert_eq(m.check(_at(20.0), true), "seen")
	assert_true(flag(Data.FLAG_MOMENT_SEEN))
	assert_eq(m.check(_at(25.0), true), "", "still here")
	assert_eq(m.check(_at(40.0), false), "left")
	assert_eq(m.check(_at(20.0), true), "", "Standard never turns while watched")
	assert_eq(m.check(_at(20.0), false), "turn", "turned while she looked away")
	assert_true(flag(Data.FLAG_MOMENT_TURNED))
	assert_almost(m.pumpkin.rotation.y, m.turned_yaw, 0.001, "now faces the other way")
	assert_true(absf(wrapf(m.turned_yaw - m.face_yaw, -PI, PI)) > deg_to_rad(90.0), "a clearly different direction")
	assert_eq(_horror, ["authored:pumpkin_turned"], "announced once as an authored moment")
	var hp: Variant = (_horror_data.back() as Dictionary).get("pos") if not _horror_data.is_empty() else null
	assert_true(hp is Vector3 and Vector2((hp as Vector3).x, (hp as Vector3).z).distance_to(Data.MOMENT["pos"]) < 0.1,
		"the event carries the pumpkin's position (a sheltering companion looks at the real pumpkin)")
	assert_eq(m.check(_at(15.0), true), "", "Standard: no notice beat")
	assert_eq(m.check(_at(5.0), true), "twitch", "close up, the stem twitches twice")
	assert_true(flag(Data.FLAG_MOMENT_TWITCH))
	assert_true(_captions.size() >= 1 and String(_captions.back()).contains("twitches twice"), "captioned (works muted)")
	assert_eq(m.phase, "done")
	for d in [40.0, 20.0, 5.0]:
		for vis in [true, false]:
			assert_eq(m.check(_at(d), vis), "", "nothing more ever happens")
	assert_eq(_horror.size(), 1)
	assert_eq(m.events, ["seen", "left", "turn", "twitch"])


func test_gentle_is_playful_and_captioned() -> void:
	fresh_state()
	var m: Node3D = await _moment(0)
	m.check(_at(10.0), true)
	m.check(_at(40.0), true)
	assert_eq(m.check(_at(20.0), false), "turn")
	assert_true(m.pending_notice, "Gentle keeps a playful notice for when she looks")
	var n0 := _captions.size()
	assert_eq(m.check(_at(20.0), true), "notice")
	assert_eq(_captions.size(), n0 + 1, "a caption says what happened")
	assert_true(String(_captions.back()).contains("shuffled"), "playful wording")
	await wait_seconds(0.9)
	assert_almost(m.pumpkin.position.y, 0.6, 0.02, "the little hop lands back on the bale")
	assert_eq(m.check(_at(6.0), true), "twitch")


func test_intense_turns_quietly_while_watched_from_afar() -> void:
	fresh_state()
	var m: Node3D = await _moment(2)
	m.turn_seconds = 0.3
	m.check(_at(10.0), true)
	m.check(_at(40.0), true)
	var n0 := _captions.size()
	assert_eq(m.check(_at(10.0), true), "", "Intense: not up close (keeps its distance rule)")
	assert_eq(m.check(_at(22.0), true), "turn_watched", "the distant face turns while she watches")
	assert_true(flag(Data.FLAG_MOMENT_TURNED))
	assert_eq(_captions.size(), n0, "silent: no caption, no sound, no volume spike")
	await wait_seconds(0.9)
	assert_almost(wrapf(m.pumpkin.rotation.y - m.turned_yaw, -PI, PI), 0.0, 0.01, "then holds perfectly still, turned")
	var r: float = m.pumpkin.rotation.y
	await wait_seconds(0.3)
	assert_almost(m.pumpkin.rotation.y, r, 0.0001, "still")
	# Intense fallback: if she is already close and not looking, it simply is turned.
	fresh_state()
	var m2: Node3D = await _moment(2)
	m2.check(_at(10.0), true)
	m2.check(_at(40.0), true)
	assert_eq(m2.check(_at(10.0), false), "turn")


func test_once_per_save_and_rebuilt_from_flags() -> void:
	fresh_state()
	var m: Node3D = await _moment(1)
	m.check(_at(10.0), true)
	# Reloading the area after she saw it counts as having left.
	var m2: Node3D = await _moment(1)
	assert_eq(m2.phase, "return", "seen before: ready to turn on return")
	assert_eq(m2.check(_at(20.0), false), "turn")
	# Another reload: already turned, built turned, never turns again.
	var m3: Node3D = await _moment(1)
	assert_eq(m3.phase, "turned")
	assert_almost(m3.pumpkin.rotation.y, m3.turned_yaw, 0.001, "built already turned")
	for d in [40.0, 20.0, 12.0]:
		for vis in [true, false]:
			var ev: String = m3.check(_at(d), vis)
			assert_false(ev.begins_with("turn"), "never turns twice")
	assert_eq(_horror.size(), 1, "one authored turn per save")
	m3.check(_at(4.0), true)
	var m4: Node3D = await _moment(1)
	assert_eq(m4.phase, "done")
	# Save round trip keeps it.
	var dict: Dictionary = GameState.to_dict()
	fresh_state()
	GameState.from_dict(dict)
	var m5: Node3D = await _moment(1)
	assert_eq(m5.phase, "done", "survives save/load")


func test_it_is_harmless_and_nobodys_crop() -> void:
	fresh_state()
	var m: Node3D = await _moment(2)
	var hurt := [0]
	var cb := func(_a: float, _s: Node) -> void:
		hurt[0] += 1
	Events.player_damaged.connect(cb)
	m.turn_seconds = 0.05
	m.check(_at(10.0), true)
	m.check(_at(40.0), true)
	m.check(_at(20.0), true)
	m.check(_at(2.0), true)
	await wait_frames(3)
	Events.player_damaged.disconnect(cb)
	assert_eq(hurt[0], 0, "never damages")
	for n in [m] + m.find_children("*", "", true, false):
		assert_false((n as Node).is_in_group("enemy"), "never an enemy")
		assert_false((n as Node).is_in_group("structure"), "not a structure")
		assert_false((n as Node).is_in_group("interactable"), "no crop / harvest prompt")
		assert_false((n as Node).is_in_group("harvestable"), "not harvestable")
	assert_null(m.get("health"), "no health: nothing to fight")
	assert_true((Data.MOMENT["pos"] as Vector2).distance_to(Data.OUTPOST_CENTER) > 40.0, "far from any player build area")

extends Node
## Audio manager. Buses: Master > Music, Ambience, SFX, UI. Volumes follow Settings.
## Sounds are looked up by NAME in res://assets/audio/{sfx,ui,music,ambience}/<name>.(ogg|wav).
## Variants: <name>_1, <name>_2, ... are picked at random automatically.
## Missing sounds never crash: a warning is printed once and the call is ignored.
##
## API (stable - other systems call these):
##   Audio.play_sfx(name, volume_db := 0.0, pitch_var := 0.06)            non-positional SFX
##   Audio.play_ui(name, volume_db := 0.0)                                  UI bus
##   Audio.play_3d(name, pos, volume_db := 0.0, pitch_var := 0.06, max_distance := 30.0) -> Node
##   Audio.play_music(name, fade := 2.0) / Audio.stop_music(fade := 2.0)
##   Audio.play_ambience(name, fade := 3.0, layer := 0) / Audio.stop_ambience(fade := 3.0, layer := -1)
##   Audio.duck_ambience(db, seconds)      temporarily lowers ambience (director "silence" event)
##   Audio.has_sound(name) -> bool

const DIRS := ["sfx", "ui", "ambience", "music"]
const BUSES := ["Music", "Ambience", "SFX", "UI"]

var _cache: Dictionary = {}          # name -> Array[AudioStream]
var _warned: Dictionary = {}
var _music_player: AudioStreamPlayer
var _music_name := ""
var _amb_players: Array = []         # two layers
var _amb_names: Array = ["", ""]
var _pool: Array = []
var _duck_db := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		add_child(p)
		_amb_players.append(p)
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	Events.settings_changed.connect(func(_k): apply_volumes())
	apply_volumes()


func _setup_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	# Gentle limiter on master to prevent clipping.
	var master := AudioServer.get_bus_index("Master")
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(master, lim)


func apply_volumes() -> void:
	_set_bus("Master", Settings.get_value("master_volume"))
	_set_bus("Music", Settings.get_value("music_volume"))
	_set_bus("Ambience", Settings.get_value("ambience_volume"), _duck_db)
	_set_bus("SFX", Settings.get_value("sfx_volume"))
	_set_bus("UI", Settings.get_value("ui_volume"))


func _set_bus(bus: String, linear: float, extra_db: float = 0.0) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var l := clampf(float(linear), 0.0, 1.0)
	AudioServer.set_bus_mute(idx, l <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(max(l, 0.0001)) + extra_db)


func has_sound(name: String) -> bool:
	return not _streams(name).is_empty()


func _streams(name: String) -> Array:
	if _cache.has(name):
		return _cache[name]
	var found := []
	for d in DIRS:
		for ext in ["ogg", "wav"]:
			var base := "res://assets/audio/%s/%s" % [d, name]
			if ResourceLoader.exists("%s.%s" % [base, ext]):
				found.append(load("%s.%s" % [base, ext]))
			for i in range(1, 9):
				var v := "%s_%d.%s" % [base, i, ext]
				if ResourceLoader.exists(v):
					found.append(load(v))
	_cache[name] = found
	return found


func _pick(name: String) -> AudioStream:
	var arr := _streams(name)
	if arr.is_empty():
		if not _warned.has(name):
			_warned[name] = true
			push_warning("Audio: missing sound '%s'" % name)
		return null
	return arr[randi() % arr.size()]


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[randi() % _pool.size()]


func play_sfx(name: String, volume_db: float = 0.0, pitch_var: float = 0.06) -> void:
	var s := _pick(name)
	if s == null:
		return
	var p := _free_player()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_ui(name: String, volume_db: float = 0.0) -> void:
	var s := _pick(name)
	if s == null:
		return
	var p := _free_player()
	p.stream = s
	p.bus = "UI"
	p.volume_db = volume_db
	p.pitch_scale = 1.0
	p.play()


## Positional one-shot. The player node frees itself when finished.
func play_3d(name: String, pos: Vector3, volume_db: float = 0.0, pitch_var: float = 0.06, max_distance: float = 30.0) -> Node:
	var s := _pick(name)
	if s == null:
		return null
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		play_sfx(name, volume_db, pitch_var)
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 6.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	tree.current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


func play_music(name: String, fade: float = 2.0) -> void:
	if name == _music_name and _music_player.playing:
		return
	var s := _pick(name)
	_music_name = name
	var tw := create_tween()
	if _music_player.playing:
		tw.tween_property(_music_player, "volume_db", -40.0, fade * 0.5)
	tw.tween_callback(func():
		_music_player.stream = s
		if s:
			_music_player.volume_db = -40.0
			_music_player.play())
	tw.tween_property(_music_player, "volume_db", 0.0, fade * 0.5)


func stop_music(fade: float = 2.0) -> void:
	_music_name = ""
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -40.0, fade)
	tw.tween_callback(_music_player.stop)


func play_ambience(name: String, fade: float = 3.0, layer: int = 0) -> void:
	layer = clampi(layer, 0, 1)
	if _amb_names[layer] == name and _amb_players[layer].playing:
		return
	_amb_names[layer] = name
	var p: AudioStreamPlayer = _amb_players[layer]
	var s := _pick(name)
	var tw := create_tween()
	if p.playing:
		tw.tween_property(p, "volume_db", -40.0, fade * 0.5)
	tw.tween_callback(func():
		p.stream = s
		if s:
			p.volume_db = -40.0
			p.play())
	tw.tween_property(p, "volume_db", 0.0, fade * 0.5)


func stop_ambience(fade: float = 3.0, layer: int = -1) -> void:
	for i in 2:
		if layer == -1 or layer == i:
			_amb_names[i] = ""
			var p: AudioStreamPlayer = _amb_players[i]
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -40.0, fade)
			tw.tween_callback(p.stop)


func duck_ambience(db: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v): _duck_db = v; apply_volumes(), 0.0, db, 1.5)
	tw.tween_interval(max(seconds - 3.0, 0.5))
	tw.tween_method(func(v): _duck_db = v; apply_volumes(), db, 0.0, 1.5)

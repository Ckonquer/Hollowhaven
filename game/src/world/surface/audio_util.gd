extends RefCounted
## Small helpers for positional looping sounds that must degrade gracefully when a sound is missing.

## Finds a generated sound file by name (ambience/sfx/music folders), or null.
static func find_audio(sound_name: String) -> AudioStream:
	for d in ["ambience", "sfx", "music", "ui"]:
		for ext in ["ogg", "wav"]:
			for suffix in ["", "_1"]:
				var p := "res://assets/audio/%s/%s%s.%s" % [d, sound_name, suffix, ext]
				if ResourceLoader.exists(p):
					return load(p)
	return null


## A looping AudioStreamPlayer3D for `sound_name`, or null if the sound doesn't exist (yet).
static func make_loop(sound_name: String, bus: String = "Ambience", volume_db: float = -6.0, max_distance: float = 18.0) -> AudioStreamPlayer3D:
	var s := find_audio(sound_name)
	if s == null:
		return null
	s = s.duplicate()
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * float(w.mix_rate))
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	p.max_distance = max_distance
	p.unit_size = 4.0
	p.autoplay = true
	return p

extends Node3D
## The Borrowed Choir's body: a slowly turning hoop of dark wood around an EMPTY centre, hung with cracked
## bells, three carved wooden masks looking outward, harvest ribbons and a few dim motes that light nothing.
## Built once from Mat / Kit (shared caches); animation only moves nodes (no per-frame allocations).
## Visual contract (duck typed, like the other enemy visuals): set_state(name, length), body_height(),
## fall_apart() (defeat: masks and ribbons drop harmlessly and fade, the bells go quiet).
## States: "veiled" (idle sway, out of reach), "tele" (the hoop spins up, bells swing wide, ribbons flare out),
## "exposed" (it sags: masks slip askew, bells hang limp, motes sink - a readable opening), "shriek" (a fast
## jangling spin), "hidden", "defeat".

const Art := preload("res://src/enemies/choir/choir_art.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const HOOP_Y := 1.7
const HOOP_R := 0.9
const BELLS := 5
const MASKS := 3
const RIBBONS := 7
const MOTES := 4

var state_name: String = "veiled"
var _t: float = 0.0
var _hoop: Node3D
var _bells: Array = []
var _bell_phase: Array = []
var _masks: Array = []
var _ribbons: Array = []
var _motes: Array = []
var _spin: float = 0.25
var _falling: bool = false


func _ready() -> void:
	_build()


func _build() -> void:
	_hoop = Node3D.new()
	_hoop.name = "Hoop"
	add_child(_hoop)
	_hoop.position = Vector3(0, HOOP_Y, 0)
	Kit.add(_hoop, Kit.torus(HOOP_R - 0.08, HOOP_R + 0.06, Art.wood_mat()), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.6, 1.0))
	# four little struts meeting at nothing: the centre stays empty on purpose
	for i in 4:
		var ang := TAU * float(i) / 4.0
		Kit.add(_hoop, Kit.box(Vector3(0.05, 0.05, 0.45), Art.wood_mat()), Vector3(cos(ang) * (HOOP_R - 0.25), 0.28, sin(ang) * (HOOP_R - 0.25)), Vector3(35.0, -rad_to_deg(ang) + 90.0, 0))
	for i in BELLS:
		var ang := TAU * (float(i) + 0.3) / float(BELLS)
		var drop := 0.35 + 0.12 * float(i % 3)
		var b := Art.bell(_hoop, Vector3(cos(ang) * HOOP_R, -drop, sin(ang) * HOOP_R), 0.9 + 0.12 * float(i % 2))
		_bells.append(b)
		_bell_phase.append(float(i) * 1.37)
	for i in MASKS:
		var ang := TAU * float(i) / float(MASKS)
		var m := Art.mask(_hoop, Vector3(cos(ang) * (HOOP_R + 0.12), -0.25, sin(ang) * (HOOP_R + 0.12)), 90.0 - rad_to_deg(ang), 1.05)
		_masks.append(m)
	for i in RIBBONS:
		var ang := TAU * (float(i) + 0.6) / float(RIBBONS)
		var c: Color = Art.RIBBONS[i % Art.RIBBONS.size()]
		var r := Art.ribbon(_hoop, Vector3(cos(ang) * HOOP_R, -0.05, sin(ang) * HOOP_R), 0.9 + 0.25 * float(i % 3), c)
		_ribbons.append(r)
	for i in MOTES:
		_motes.append(Art.mote(self, Vector3(0, HOOP_Y, 0), 0.06, 0.8))


func body_height() -> float:
	return HOOP_Y + 0.4


func set_state(s: String, _length: float = 0.0) -> void:
	state_name = s
	visible = s != "hidden"
	match s:
		"shriek":
			_spin = 2.6
		"tele":
			_spin = 0.9
		"exposed":
			_spin = 0.08
		_:
			_spin = 0.25


## tests/preview hook: --preview=res://src/enemies/choir/choir_visual.gd --preview-anim=veiled|tele|exposed|shriek|defeat
func play_anim(anim: String) -> void:
	if anim == "defeat":
		set_state("defeat")
		fall_apart(-HOOP_Y)
	else:
		set_state(anim)


func _process(delta: float) -> void:
	if not visible or _falling:
		return
	_t += delta
	_hoop.rotation.y += _spin * delta
	var sag := 1.0 if state_name == "exposed" else 0.0
	var flare := 1.0 if state_name == "tele" or state_name == "shriek" else 0.0
	_hoop.rotation.z = sin(_t * 0.7) * 0.06 + sag * 0.22
	_hoop.rotation.x = sin(_t * 0.55) * 0.05 + sag * 0.12
	for i in _bells.size():
		var b: Node3D = _bells[i]
		var ph: float = _bell_phase[i]
		var amp := 0.12 + flare * 0.45 - sag * 0.1
		b.rotation.z = sin(_t * (1.3 + flare * 3.0) + ph) * amp
		b.rotation.x = cos(_t * (1.1 + flare * 2.6) + ph) * amp * 0.6
	for i in _masks.size():
		var m: Node3D = _masks[i]
		m.rotation.x = sag * (0.45 + 0.1 * float(i)) + sin(_t * 0.9 + float(i)) * 0.04
		m.rotation.z = sag * (0.3 if i % 2 == 0 else -0.35)
	for i in _ribbons.size():
		var r: Node3D = _ribbons[i]
		r.rotation.z = sin(_t * 1.1 - float(i) * 0.6) * (0.14 + flare * 0.5) * (1.0 - sag * 0.8)
		r.rotation.x = cos(_t * 0.8 - float(i) * 0.5) * 0.08 + flare * 0.35
	for i in _motes.size():
		var m2: MeshInstance3D = _motes[i]
		var ang := _t * 0.6 + TAU * float(i) / float(_motes.size())
		var rr := 0.35 + 0.1 * sin(_t * 0.8 + float(i))
		m2.position = Vector3(cos(ang) * rr, HOOP_Y - 0.1 + sin(_t * 1.3 + float(i)) * 0.12 - sag * 0.8, sin(ang) * rr)


## Defeat: the masks and ribbons fall harmlessly to the floor (`floor_local_y` below this node) and fade; the
## bells stop. Visual only (no collision, no damage). Returns the tween (null outside the tree).
func fall_apart(floor_local_y: float = 0.0) -> Tween:
	_falling = true
	if not is_inside_tree():
		return null
	var tw := create_tween().set_parallel(true)
	var k := 0
	for m in _masks:
		var n: Node3D = m
		n.top_level = true           # keeps its world pose; the hoop's own shrink no longer drags it
		var g := n.global_position
		var target_y := global_position.y + floor_local_y + 0.12
		tw.tween_property(n, "global_position", Vector3(g.x, target_y, g.z), 1.1 + 0.2 * float(k)).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "rotation", Vector3(-PI * 0.5, n.rotation.y + 0.6 * float(k), 0.0), 1.1)
		tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.9).set_delay(2.8)       # then it crumbles away
		k += 1
	for r in _ribbons:
		var n2: Node3D = r
		n2.top_level = true
		var g2 := n2.global_position
		tw.tween_property(n2, "global_position", Vector3(g2.x, global_position.y + floor_local_y + 0.9, g2.z), 1.6 + 0.1 * float(k % 4)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(n2, "rotation", Vector3(PI * 0.5, 0.0, 0.3), 1.6)
		tw.tween_property(n2, "scale", Vector3.ONE * 0.01, 0.9).set_delay(2.8)
		k += 1
	for b in _bells:
		(b as Node3D).rotation = Vector3.ZERO
	for m2 in _motes:
		tw.tween_property(m2, "position:y", HOOP_Y + 2.5, 2.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hoop, "scale", Vector3.ONE * 0.01, 1.4).set_delay(1.6).set_trans(Tween.TRANS_SINE)
	return tw

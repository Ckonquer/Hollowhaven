extends Node3D
## Phase B "Stolen rhythm": the two protection layers the Choir wraps round itself (MP §13.3 "each resonator
## weakens a protection layer"). Outer layer = a turning ring of cracked bells on a thin iron hoop; inner layer =
## a counter-turning ring of masks and ribbons. Each woken resonator drops one layer (bells tumble silent and
## fade), both down = the Choir is exposed. Visual only (no collision, no damage).
##   layers.set_count(2) / drop_one() / count()

const Art := preload("res://src/enemies/choir/choir_art.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")

const OUTER_R := 2.3
const INNER_R := 1.5
const OUTER_BELLS := 8
const INNER_MASKS := 5
const Y := 1.6

var _rings: Array = []           # [outer, inner] Node3D
var _count: int = 0
var _t: float = 0.0


func _ready() -> void:
	var outer := Node3D.new()
	outer.name = "OuterBells"
	add_child(outer)
	outer.position = Vector3(0, Y, 0)
	Kit.add(outer, Kit.torus(OUTER_R - 0.03, OUTER_R + 0.03, Mat.toon(Color("3b3238"))), Vector3(0, 0.45, 0))
	for i in OUTER_BELLS:
		var a := TAU * float(i) / float(OUTER_BELLS)
		Art.bell(outer, Vector3(cos(a) * OUTER_R, 0.3, sin(a) * OUTER_R), 0.8)
	var inner := Node3D.new()
	inner.name = "InnerMasks"
	add_child(inner)
	inner.position = Vector3(0, Y - 0.2, 0)
	for i in INNER_MASKS:
		var a2 := TAU * (float(i) + 0.5) / float(INNER_MASKS)
		Art.mask(inner, Vector3(cos(a2) * INNER_R, 0.1, sin(a2) * INNER_R), 90.0 - rad_to_deg(a2), 0.8)
		Art.ribbon(inner, Vector3(cos(a2 + 0.3) * INNER_R, 0.3, sin(a2 + 0.3) * INNER_R), 1.1, Art.RIBBONS[i % Art.RIBBONS.size()])
	_rings = [outer, inner]
	set_count(0)


func count() -> int:
	return _count


func set_count(n: int) -> void:
	_count = clampi(n, 0, 2)
	for i in _rings.size():
		var r: Node3D = _rings[i]
		r.visible = _stands(i)
		r.scale = Vector3.ONE
		r.position.y = Y if i == 0 else Y - 0.2
	visible = _count > 0
	set_process(_count > 0)


## One layer falls (outer first). Returns the layers left.
func drop_one() -> int:
	if _count <= 0:
		return 0
	var r: Node3D = _rings[0] if _count == 2 else _rings[1]
	_count -= 1
	if is_inside_tree():
		var tw := create_tween().set_parallel(true)
		tw.tween_property(r, "position:y", r.position.y - 1.4, 0.8).set_ease(Tween.EASE_IN)
		tw.tween_property(r, "scale", Vector3.ONE * 0.05, 0.8).set_delay(0.3)
		tw.chain().tween_callback(_after_drop.bind(r))
	else:
		_after_drop(r)
	return _count


## Outer (0) stands only with both layers up; the inner (1) with at least one.
func _stands(i: int) -> bool:
	return _count >= 2 if i == 0 else _count >= 1


func _after_drop(r: Node3D) -> void:
	r.visible = _stands(_rings.find(r))
	r.scale = Vector3.ONE
	r.position.y = Y if r == _rings[0] else Y - 0.2
	visible = _count > 0


## Which layer nodes are standing (tests / visual checks): [outer, inner] visibility after drops.
func standing() -> Array:
	return [_stands(0), _stands(1)]


func _process(delta: float) -> void:
	_t += delta
	if _rings.size() == 2:
		(_rings[0] as Node3D).rotation.y += delta * 0.5
		(_rings[1] as Node3D).rotation.y -= delta * 0.7

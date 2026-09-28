extends RefCounted
## Camera-only blockers (visual QA theme T1): physics layer 10 (bit value 512), which ONLY the third-person camera
## rig (camera_rig.gd COLLISION_MASK) collides with. Nothing else uses this layer: the player, companions and
## enemies (mask world|structure), interaction probes (16), combat / sight rays (explicit masks) and the building
## tools all ignore it, so a blocker never changes gameplay. Visual-only props that the camera must not fly into
## (a waygate lintel, the top of a Lantern Road arch, a lift roof, a pale door) get one: the spring arm pulls in
## in front of them instead of parking the camera inside the prop.
##   var body := CameraBlock.add_box(prop, Vector3(0, 2.9, 0), Vector3(4.3, 1.1, 1.0))   # local to `prop`
##   CameraBlock.add_box(prop, centre2, size2, Basis(), body)                              # more boxes, same body
## Keep blockers clear of the space Krystal walks through (her pivot must never start inside one).

const LAYER := 512
const NAME := "CameraBlock"

static var _shapes: Dictionary = {}


## A BoxShape3D of that size, shared by every blocker of the same size (shapes are resources).
static func box_shape(size: Vector3) -> BoxShape3D:
	var key := "%.3f|%.3f|%.3f" % [size.x, size.y, size.z]
	var s: Variant = _shapes.get(key)
	if s is BoxShape3D:
		return s
	var b := BoxShape3D.new()
	b.size = size
	_shapes[key] = b
	return b


## Adds a camera-only box (centre / size / basis local to `parent`). Creates the StaticBody3D when `body` is null
## and returns the body the box was added to.
static func add_box(parent: Node3D, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY, body: StaticBody3D = null) -> StaticBody3D:
	var b := body
	if b == null:
		b = StaticBody3D.new()
		b.name = NAME
		b.collision_layer = LAYER
		b.collision_mask = 0
		parent.add_child(b)
	var cs := CollisionShape3D.new()
	cs.shape = box_shape(size)
	cs.transform = Transform3D(basis, center)
	b.add_child(cs)
	return b

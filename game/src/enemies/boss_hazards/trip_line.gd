extends Node3D
## A visible trip-line stretched low (0.32 m) between two FIXED floor anchors of the Matron's arena
## (arachnophobia: a pale root runner). Life: FORMING (a faint line tightens between the anchors,
## harmless) -> ACTIVE (walking through it snags Krystal: a small bounded slow + a little damage, and
## the line snaps; jumping clears it) -> fades after `life` s. Krystal can CUT it with any attack
## (it is a hittable in group "enemy": health 1, `can_be_hit_by` = Krystal only) or BURN it by holding
## her lit lantern close for BURN_TIME. The hazard field applies the snag, the slow and the caps.
##   var l = TripLine.new(); l.setup({"a": Vector3, "b": Vector3, "tele": 1.2, "life": 12.0, "alt": false})

signal cut(how: String)

const Art := preload("res://src/enemies/boss_hazards/hazard_art.gd")
const Health := preload("res://src/combat/health.gd")

const HEIGHT := 0.32
const FADE := 0.4
const BURN_DIST := 1.6
const BURN_TIME := 0.5

var kind := "trip"
var a := Vector3.ZERO
var b := Vector3.ZERO
var tele: float = 1.2
var life: float = 12.0
var alt := false
var t: float = 0.0
var active := false
var fading: float = -1.0
var cut_by: String = ""
var health: Node
var hit_radius: float = 0.35
var hit_color := Color(0.92, 0.9, 0.98)
var focus := Vector3.ZERO           # Krystal's position (set by the field): attacks aim at the nearest point
var chord: Array = []               # [post index, post index] (set by the field)

var high_vis := false               # Settings "high_visibility_cues" (the field toggles it live)

var _burn_t: float = 0.0
var _mi: MeshInstance3D
var _glow: MeshInstance3D
var _bold: MeshInstance3D           # bold cream line over it with high_vis (also while it forms)


func setup(p: Dictionary) -> void:
	var pa: Variant = p.get("a")
	if pa is Vector3:
		a = pa
	var pb: Variant = p.get("b")
	if pb is Vector3:
		b = pb
	tele = maxf(float(p.get("tele", tele)), 0.0)
	life = float(p.get("life", life))
	alt = bool(p.get("alt", alt))
	var c: Variant = p.get("chord")
	if c is Array:
		chord = c
	hit_color = Art.ROOT if alt else Art.SILK


func _ready() -> void:
	top_level = true
	global_transform = Transform3D(Basis.IDENTITY, (a + b) * 0.5)
	add_to_group("enemy")
	set_meta("boss_hazard", true)     # auto-aim may rank it below real enemies (integrator note)
	health = Health.new()
	health.name = "Health"
	health.max_hp = 1.0
	add_child(health)
	health.damaged.connect(_on_damaged)
	high_vis = Art.high_vis()
	_build()
	if tele <= 0.0:
		_activate()


# --- Combat contract -----------------------------------------------------------------------------

## Only Krystal cuts lines (companions keep their attention on the Matron).
func can_be_hit_by(source: Node) -> bool:
	if fading >= 0.0:
		return false
	return source == null or (is_instance_valid(source) and source.is_in_group("player"))


func is_threatening() -> bool:
	return false


func get_aim_point() -> Vector3:
	return nearest_point(focus) + Vector3.UP * HEIGHT


func hit_flash(_d: float = 0.1) -> void:
	pass


func knockback(_dir: Vector3, _force: float) -> void:
	pass


func _on_damaged(_amount: float, source: Node, _dir: Vector3) -> void:
	if source != null and is_instance_valid(source) and not source.is_in_group("player"):
		health.set_hp(health.max_hp)      # not Krystal's blow (a companion ignoring can_be_hit_by): no cut
		return
	snap("attack")


# --- Queries -------------------------------------------------------------------------------------------

func is_active() -> bool:
	return active and fading < 0.0


func is_live() -> bool:
	return fading < 0.0


func is_done() -> bool:
	return fading >= FADE


func remaining() -> float:
	return maxf(tele + life - t, 0.0) if fading < 0.0 else 0.0


func distance_to(pos: Vector3) -> float:
	return seg_dist(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(pos.x, pos.z))


func nearest_point(pos: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.x * ab.x + ab.z * ab.z
	if l2 < 0.0001:
		return a
	var k := clampf(((pos.x - a.x) * ab.x + (pos.z - a.z) * ab.z) / l2, 0.0, 1.0)
	return a + ab * k


static func seg_dist(p0: Vector2, p1: Vector2, p: Vector2) -> float:
	var d := p1 - p0
	var l2 := d.length_squared()
	if l2 < 0.000001:
		return p.distance_to(p0)
	var k := clampf((p - p0).dot(d) / l2, 0.0, 1.0)
	return p.distance_to(p0 + d * k)


# --- Life ------------------------------------------------------------------------------------------------

func tick(delta: float, target_pos: Vector3, has_target: bool, lantern: bool) -> void:
	t += delta
	focus = target_pos
	if fading >= 0.0:
		fading += delta
		var k := clampf(fading / FADE, 0.0, 1.0)
		if _mi != null:
			_mi.transparency = k
		if _glow != null:
			_glow.transparency = k
		return
	if not active:
		var k := clampf(t / maxf(tele, 0.01), 0.0, 1.0)
		if _mi != null:
			_mi.transparency = 1.0 - lerpf(0.15, 0.95, k)
		if _glow != null:
			_glow.transparency = 1.0 - Art.pulse_alpha(t, 0.2, 0.7, 8.0)
		if t >= tele:
			_activate()
		return
	if has_target and lantern and distance_to(target_pos) <= BURN_DIST:
		_burn_t += delta
		if _burn_t >= BURN_TIME:
			snap("lantern")
			return
	else:
		_burn_t = maxf(_burn_t - delta, 0.0)
	if t >= tele + life:
		snap("expired")


## Ends the line: "attack" (cut), "lantern" (burned), "snag" (Krystal walked through it), "expired",
## "cleared" (phase transition / reset). Idempotent.
func snap(how: String) -> void:
	if fading >= 0.0:
		return
	cut_by = how
	fading = 0.0
	remove_from_group("enemy")
	_apply_high_vis()
	var mid := (a + b) * 0.5 + Vector3.UP * HEIGHT
	match how:
		"attack":
			Audio.play_3d("dir_root_creak" if alt else "dir_web_rustle", mid, -3.0, 0.15, 25.0)
		"lantern":
			Audio.play_3d("lantern_on", mid, -6.0, 0.1, 25.0)
			Events.caption.emit("[the pale root shrivels in the lantern light]" if alt else "[the thread shrivels in the lantern light]")
	if how != "cleared" and how != "expired":
		cut.emit(how)


func _activate() -> void:
	active = true
	if _mi != null:
		_mi.transparency = 0.0
	if _glow != null:
		_glow.transparency = 0.55


# --- Visuals -------------------------------------------------------------------------------------------

func set_alt(on: bool) -> void:
	if on == alt:
		return
	alt = on
	hit_color = Art.ROOT if alt else Art.SILK
	for c in get_children():
		if c != health:
			c.queue_free()
	_mi = null
	_glow = null
	_bold = null
	_build()
	if active and _mi != null:
		_mi.transparency = 0.0


## Settings "high_visibility_cues": a bold line along it while it is live (forming or active).
func set_high_vis(on: bool) -> void:
	high_vis = on
	_apply_high_vis()


func bold_visible() -> bool:
	return _bold != null and is_instance_valid(_bold) and _bold.visible


func _apply_high_vis() -> void:
	if _bold != null and is_instance_valid(_bold):
		_bold.visible = high_vis and fading < 0.0


func _build() -> void:
	var lift := Vector3.UP * HEIGHT
	_mi = Art.line(self, Art.strand_mat(alt))
	Art.place_line(_mi, a + lift, b + lift, 0.035 if alt else 0.02)
	_mi.transparency = 0.85
	# A faint wider glow along the line so it stays readable against the floor in the dark.
	_glow = Art.line(self, Art.warn_mat(alt))
	Art.place_line(_glow, a + lift * 0.9, b + lift * 0.9, 0.07)
	_glow.transparency = 0.8
	_bold = Art.line(self, Art.bold_mat())
	Art.place_line(_bold, a + lift * 1.05, b + lift * 1.05, 0.045)
	_apply_high_vis()

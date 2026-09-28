extends Node3D
## A narrow, telegraphed web fan on the floor (arachnophobia: a drifting pale veil of root seeds).
## Life: TELEGRAPH (a warm sector outline grows on the floor and follows Krystal for the first half,
## then locks) -> ACTIVE (a pale sheet: anyone standing in it is SLOWED, never rooted; the hazard field
## applies the bounded slow) -> fades out after `life` seconds (or earlier when the field needs room).
##   var f = WebFan.new(); f.setup({"apex": Vector3, "dir": Vector3, "half_deg": 12.0, "length": 7.0,
##       "tele": 1.2, "life": 7.0, "slow": 0.6, "alt": false}); field.add_child(f)
## Pure geometry for tests: WebFan.sector_contains(apex, dir, half_deg, r0, r1, pos).

const Art := preload("res://src/enemies/boss_hazards/hazard_art.gd")

const R0 := 0.5                 # the sheet starts a little in front of the apex
const TRACK_FRAC := 0.5         # follows Krystal for the first half of the telegraph, then locks
const FADE := 0.45

var kind := "fan"
var apex := Vector3.ZERO
var dir := Vector3.FORWARD
var half_deg: float = 12.0
var length: float = 7.0
var tele: float = 1.2
var life: float = 7.0
var slow_mult: float = 0.6
var alt := false
var t: float = 0.0
var active := false
var fading: float = -1.0

var _tele_mi: MeshInstance3D
var _sheet: Node3D
var _sheet_mi: MeshInstance3D
var _strands: Array = []
var _motes: CPUParticles3D
var high_vis := false             # Settings "high_visibility_cues" (the field toggles it live)
var _bold: Array = []             # bold outline strands (both edges + the far arc), shown with high_vis


func setup(p: Dictionary) -> void:
	var a: Variant = p.get("apex")
	if a is Vector3:
		apex = a
	var d: Variant = p.get("dir")
	if d is Vector3:
		_set_dir(d)
	half_deg = float(p.get("half_deg", half_deg))
	length = maxf(float(p.get("length", length)), R0 + 1.0)
	tele = maxf(float(p.get("tele", tele)), 0.0)
	life = float(p.get("life", life))
	slow_mult = clampf(float(p.get("slow", slow_mult)), 0.1, 1.0)
	alt = bool(p.get("alt", alt))


func _ready() -> void:
	top_level = true
	high_vis = Art.high_vis()
	_build()
	_place()
	if tele <= 0.0:
		_activate()


# --- Queries ---------------------------------------------------------------------------------------

func is_active() -> bool:
	return active and fading < 0.0


func is_live() -> bool:
	return fading < 0.0


func is_done() -> bool:
	return fading >= FADE


func remaining() -> float:
	return maxf(tele + life - t, 0.0) if fading < 0.0 else 0.0


## Is `pos` (flat) inside the active sheet?
func contains(pos: Vector3) -> bool:
	return is_active() and sector_contains(apex, dir, half_deg, R0, length, pos)


static func sector_contains(p_apex: Vector3, p_dir: Vector3, p_half_deg: float, r0: float, r1: float, pos: Vector3) -> bool:
	var off := Vector2(pos.x - p_apex.x, pos.z - p_apex.z)
	var dist := off.length()
	if dist < r0 or dist > r1:
		return false
	var f := Vector2(p_dir.x, p_dir.z)
	if f.length_squared() < 0.0001:
		return false
	return rad_to_deg(absf(f.normalized().angle_to(off / dist))) <= p_half_deg


# --- Life --------------------------------------------------------------------------------------------

func tick(delta: float, target_pos: Vector3, has_target: bool) -> void:
	t += delta
	if fading >= 0.0:
		fading += delta
		var k := clampf(fading / FADE, 0.0, 1.0)
		if _sheet_mi != null:
			_sheet_mi.transparency = k
		if _tele_mi != null:
			_tele_mi.transparency = maxf(_tele_mi.transparency, k)
		if _motes != null:
			_motes.emitting = false
		return
	if not active:
		if has_target and t < tele * TRACK_FRAC:
			var to := Vector3(target_pos.x - apex.x, 0.0, target_pos.z - apex.z)
			if to.length_squared() > 0.04:
				_set_dir(to)
				_place()
		if _tele_mi != null:
			var k := clampf(t / maxf(tele, 0.01), 0.0, 1.0)
			_tele_mi.scale = Vector3.ONE * lerpf(0.55, 1.0, k)
			_tele_mi.transparency = 1.0 - Art.pulse_alpha(t, 0.35, 0.8, 9.0 + 8.0 * k) * lerpf(0.6, 1.0, k)
		if t >= tele:
			_activate()
	elif t >= tele + life:
		expire()


func expire() -> void:
	if fading < 0.0:
		fading = 0.0
		_apply_high_vis()


## Settings "high_visibility_cues": bold outline of the whole wedge while it is live (warning + sheet).
func set_high_vis(on: bool) -> void:
	high_vis = on
	_apply_high_vis()


func bold_visible() -> bool:
	return not _bold.is_empty() and is_instance_valid(_bold[0]) and (_bold[0] as Node3D).visible


func _apply_high_vis() -> void:
	for mi in _bold:
		if is_instance_valid(mi):
			(mi as Node3D).visible = high_vis and fading < 0.0


func _activate() -> void:
	active = true
	if _tele_mi != null:
		_tele_mi.visible = false
	if _sheet != null:
		_sheet.visible = true
	Audio.play_3d("dir_root_creak" if alt else "dir_web_rustle", apex + dir * length * 0.5, -4.0, 0.1, 30.0)


func _set_dir(d: Vector3) -> void:
	var f := Vector3(d.x, 0.0, d.z)
	if f.length_squared() > 0.0001:
		dir = f.normalized()


func _place() -> void:
	if not is_inside_tree():
		return
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), apex + Vector3.UP * 0.03)


# --- Visuals -----------------------------------------------------------------------------------------

func set_alt(on: bool) -> void:
	if on == alt:
		return
	alt = on
	for c in get_children():
		c.queue_free()
	_strands.clear()
	_tele_mi = null
	_sheet = null
	_sheet_mi = null
	_motes = null
	_build()
	if active:
		_tele_mi.visible = false
		_sheet.visible = true


func _build() -> void:
	_tele_mi = MeshInstance3D.new()
	_tele_mi.mesh = Art.sector_mesh(half_deg, R0, length)
	_tele_mi.material_override = Art.warn_mat(alt)
	_tele_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tele_mi.transparency = 0.6
	add_child(_tele_mi)
	_sheet = Node3D.new()
	_sheet.visible = false
	add_child(_sheet)
	_sheet_mi = MeshInstance3D.new()
	_sheet_mi.mesh = Art.sector_mesh(half_deg, R0, length)
	_sheet_mi.material_override = Art.sheet_mat(alt)
	_sheet_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet_mi.position.y = 0.01
	_sheet.add_child(_sheet_mi)
	var smat := Art.strand_mat(alt)
	var h := deg_to_rad(half_deg)
	if alt:
		# Pale root runners along the edges and drifting seed motes above the veil.
		for s in [-1.0, 0.0, 1.0]:
			var a: float = h * float(s) * 0.85
			var mi := Art.line(_sheet, smat)
			var tip := Vector3(sin(a) * length, 0.04, -cos(a) * length)
			_line_local(mi, Vector3(sin(a) * R0, 0.04, -cos(a) * R0), tip, 0.03)
			_strands.append(mi)
		_motes = Art.motes(_sheet, Color(0.9, 0.97, 0.85, 0.7), Vector3(tan(h) * length * 0.5, 0.2, length * 0.45), 14)
		_motes.position = Vector3(0, 0.3, -length * 0.55)
	else:
		# Radial silk strands plus two cross arcs (short chords) so it reads as a web sheet.
		for s in [-1.0, -0.33, 0.33, 1.0]:
			var a: float = h * float(s)
			var mi := Art.line(_sheet, smat)
			_line_local(mi, Vector3(sin(a) * R0, 0.03, -cos(a) * R0), Vector3(sin(a) * length, 0.03, -cos(a) * length), 0.012)
			_strands.append(mi)
		for rr in [0.45, 0.8]:
			var r: float = lerpf(R0, length, float(rr))
			var mi := Art.line(_sheet, smat)
			_line_local(mi, Vector3(sin(-h) * r, 0.03, -cos(-h) * r), Vector3(sin(h) * r, 0.03, -cos(h) * r), 0.01)
			_strands.append(mi)
	# High-visibility outline (on the fan root, so it shows the exact final wedge from the first warning
	# frame and stays over the sheet): both edges and the far arc as bold cream strands.
	_bold.clear()
	var bm := Art.bold_mat()
	for s in [-1.0, 1.0]:
		var a: float = h * float(s)
		var mi := Art.line(self, bm)
		_line_local(mi, Vector3(sin(a) * R0, 0.05, -cos(a) * R0), Vector3(sin(a) * length, 0.05, -cos(a) * length), 0.03)
		_bold.append(mi)
	var arc := Art.line(self, bm)
	_line_local(arc, Vector3(sin(-h) * length, 0.05, -cos(-h) * length), Vector3(sin(h) * length, 0.05, -cos(h) * length), 0.03)
	_bold.append(arc)
	_apply_high_vis()


## Local-space line (the fan node is rotated; strands live in its frame).
static func _line_local(mi: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var d := b - a
	var l := d.length()
	var y := d / maxf(l, 0.001)
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x * radius, y * l, z * radius), (a + b) * 0.5)

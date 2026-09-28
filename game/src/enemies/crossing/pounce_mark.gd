extends Node3D
## The Crossing Matron's pounce telegraph (MP 13.2): exactly where she will land, readable with the sound
## muted. One node per boss (top_level child: freed with her), re-used for every pounce.
##   ring     the landing ring (radius = the hit test, crossing_rules.POUNCE_RADIUS) over a dark shadow disc
##            that deepens as the wind-up runs; a DELAYED pounce pulses at half speed (a different rhythm) and
##            is a DOUBLE ring (a faint inner ring from the start - still readable with reduce_flashing)
##   final    the delayed pounce's FINAL PREPARATION: an inner ring snaps in bright and solid, the outer ring
##            firms up and a vertical strand (arachnophobia: a pale root tendril) drops from her to the mark
##   feint    (Intense) a brief shiver of the ring at the ordinary pounce time - never the final look
## Looks: silk (warm red ring) / arachnophobia (pale-gold ring with leaf notches instead of any leggy
## shadow). Settings high_visibility_cues: a bold cream outline ring (shape + brightness, never colour
## alone). Settings reduce_flashing: no pulsing - the ring firms up steadily. Nothing is allocated per frame
## (per-instance materials are created once; only their colours change).
##   var m = PounceMark.new(); boss.add_child(m); m.show_mark(pos, 2.2, false, alt); m.set_progress(k)
##   m.final_tell(top); m.hide_mark(); m.footprint() -> {"visible", "center", "radius", "delayed", "final"}

const HitFx := preload("res://src/combat/hit_fx.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const RING_SILK := Color(0.95, 0.32, 0.24)
const RING_ALT := Color(0.98, 0.84, 0.46)
const FINAL_SILK := Color(1.0, 0.86, 0.72)
const FINAL_ALT := Color(1.0, 0.97, 0.82)
const STRAND_SILK := Color(0.93, 0.91, 0.98)
const STRAND_ALT := Color("cdbfa3")
const BOLD := Color("fff1c9")
const Y := 0.05
const FEINT_TIME := 0.35         # the Intense feint shiver (crossing_rules.FEINT_GAP keeps it clear of the final tell)

var center := Vector3.ZERO
var radius: float = 2.2
var delayed := false
var final := false
var alt := false
var high_vis := false
var progress: float = 0.0

var _t: float = 0.0
var _feint_t: float = -1.0
var _disc: MeshInstance3D
var _ring: MeshInstance3D
var _inner: MeshInstance3D
var _bold: MeshInstance3D
var _notches: Node3D
var _strand: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _inner_mat: StandardMaterial3D
var _strand_mat: StandardMaterial3D
var _top := Vector3.ZERO


func _ready() -> void:
	top_level = true
	_build()
	high_vis = bool(Settings.get_value("high_visibility_cues"))
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)
	hide_mark()


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		high_vis = bool(Settings.get_value("high_visibility_cues"))
		_apply_parts()


# --- Public API ---------------------------------------------------------------------------------------------

func show_mark(at: Vector3, r: float, is_delayed: bool, is_alt: bool) -> void:
	center = at
	radius = maxf(r, 0.3)
	delayed = is_delayed
	final = false
	progress = 0.0
	_t = 0.0
	_feint_t = -1.0
	set_alt(is_alt)
	global_transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * Y)
	scale = Vector3.ONE
	_disc.scale = Vector3(radius, 1.0, radius)
	_ring.scale = Vector3(radius, 0.3, radius)
	_inner.scale = Vector3(radius, 0.3, radius)
	_bold.scale = Vector3(radius, 0.3, radius)
	_notches.scale = Vector3(radius, 1.0, radius)
	visible = true
	set_process(true)
	_apply_parts()
	_update_look()


## 0..1 of the wind-up.
func set_progress(k: float) -> void:
	progress = clampf(k, 0.0, 1.0)


## The delayed pounce's final preparation (visible half of the tell; the boss plays the sound + caption).
## `top` = where the strand hangs from (her body).
func final_tell(top: Vector3) -> void:
	final = true
	_top = top
	_apply_parts()
	_update_strand()


## Keeps the final strand attached to her while she coils.
func set_strand_top(top: Vector3) -> void:
	_top = top
	if final:
		_update_strand()


## Intense: a small false shiver of the ring at the ordinary pounce time (the true final tell still follows).
func feint() -> void:
	_feint_t = 0.0


func hide_mark() -> void:
	visible = false
	final = false
	delayed = false
	set_process(false)
	if _strand != null:
		_strand.visible = false


func is_showing() -> bool:
	return visible


func footprint() -> Dictionary:
	return {"visible": visible, "center": center, "radius": radius, "delayed": delayed, "final": final, "alt": alt}


func strand_visible() -> bool:
	return _strand != null and _strand.visible


func bold_visible() -> bool:
	return _bold != null and _bold.visible and visible


func set_alt(on: bool) -> void:
	alt = on
	if _notches != null:
		_notches.visible = on and visible
	_update_look()


# --- Animation ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _feint_t >= 0.0:
		_feint_t += delta
		if _feint_t > FEINT_TIME:
			_feint_t = -1.0
	_update_look()
	if final:
		_update_strand()


func _update_look() -> void:
	if _ring_mat == null:
		return
	var k := progress
	var s: float
	if HitFx.reduce_flashing():
		s = lerpf(0.35, 0.8, k) + (0.15 if final else 0.0)      # steady, firming up: no strobe
	else:
		# Delayed pounce: half the pulse rate at first (a different rhythm), then the solid final.
		var rate := (4.0 + 8.0 * k) if delayed else (8.0 + 14.0 * k)
		var pulse := 0.5 + 0.5 * sin(_t * rate)
		s = 0.3 + 0.45 * k + 0.25 * pulse * (1.0 - 0.5 * k)
		if final:
			s = maxf(s, 0.9)
	var rc := RING_ALT if alt else RING_SILK
	_ring_mat.albedo_color = Color(rc.r, rc.g, rc.b, clampf(s, 0.0, 1.0))
	_disc_mat.albedo_color = Color(0.03, 0.01, 0.05, lerpf(0.22, 0.6, k))
	var fc := FINAL_ALT if alt else FINAL_SILK
	# a delayed pounce shows a faint inner ring from the start (a DOUBLE ring: a shape cue that survives
	# reduce_flashing, which removes the slower pulse); the final preparation snaps it bright and solid
	_inner_mat.albedo_color = Color(fc.r, fc.g, fc.b, 0.95 if final else (0.28 if delayed else 0.0))
	# the ring contracts a touch as the final preparation lands (a shape change, not only a colour change)
	var shrink := 0.92 if final else 1.0
	if _feint_t >= 0.0 and not HitFx.reduce_flashing():
		shrink *= 1.0 + 0.06 * sin(_feint_t * 40.0)
	_ring.scale = Vector3(radius * shrink, 0.3, radius * shrink)


func _update_strand() -> void:
	if _strand == null:
		return
	var a := _top
	var b := center + Vector3.UP * 0.1
	var d := a - b
	var l := d.length()
	if l < 0.05 or not final:
		_strand.visible = false
		return
	_strand.visible = true
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var w := 0.035 if alt else 0.02
	_strand.global_transform = Transform3D(Basis(x * w, y * l, z * w), (a + b) * 0.5)
	_strand_mat.albedo_color = STRAND_ALT if alt else STRAND_SILK


func _apply_parts() -> void:
	if _inner == null:
		return
	_inner.visible = final or delayed
	_bold.visible = high_vis
	_notches.visible = alt
	if not final and _strand != null:
		_strand.visible = false


# --- Building ------------------------------------------------------------------------------------------------------

func _build() -> void:
	_disc_mat = _unshaded(Color(0.03, 0.01, 0.05, 0.4))
	_ring_mat = _unshaded(RING_SILK)
	_inner_mat = _unshaded(FINAL_SILK)
	_strand_mat = _unshaded(STRAND_SILK)
	_strand_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_disc = _part(Kit.cylinder(1.0, 1.0, 0.02, _disc_mat, 32))
	_ring = _part(Kit.torus(0.9, 1.0, _ring_mat))
	_ring.position.y = 0.02
	_inner = _part(Kit.torus(0.42, 0.52, _inner_mat))
	_inner.position.y = 0.03
	_bold = _part(Kit.torus(1.04, 1.16, Mat.glow(BOLD, 1.3)))
	_bold.position.y = 0.03
	for m in [_ring, _inner, _bold]:
		(m as MeshInstance3D).scale = Vector3(1.0, 0.3, 1.0)
	# arachnophobia: little leaf notches around the ring (a garden-like mark, never a leggy shadow)
	_notches = Node3D.new()
	_notches.name = "Notches"
	add_child(_notches)
	var leaf := Mat.glow(Color("d9f2c4"), 0.8)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var n := Kit.sphere(0.07, leaf, 5, 8)
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit.add(_notches, n, Vector3(cos(a) * 1.08, 0.03, sin(a) * 1.08), Vector3(0, -rad_to_deg(a), 0), Vector3(1.6, 0.4, 0.7))
	_strand = MeshInstance3D.new()
	_strand.name = "Strand"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_strand.mesh = cyl
	_strand.material_override = _strand_mat
	_strand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_strand.top_level = true
	add_child(_strand)
	_strand.visible = false


func _part(mi: MeshInstance3D) -> MeshInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	add_child(mi)
	return mi


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.render_priority = 1
	m.albedo_color = c
	return m


func inner_visible() -> bool:
	return _inner != null and _inner.visible and visible

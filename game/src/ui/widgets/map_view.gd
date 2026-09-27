extends Control
## Painted storybook map of Hollowhaven Woods, drawn with _draw from data/world_layout.gd:
## soft terrain regions, the forest border, the winding stream with its crossings, Mirror Pond,
## little trees, dashed footpaths, landmark stickers with names, friends, the player's arrow (from
## the camera yaw) and a pulsing ring on the current objective's landmark.

const Layout := preload("res://data/world_layout.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const ThemeFactory := preload("res://src/ui/theme_factory.gd")
const Palette := preload("res://src/art/palette.gd")

const H := 118.0
const REGIONS := {
	"haven": [Color("c7e39a"), 1.25],
	"glade": [Color("a9d37d"), 1.0],
	"quarry": [Color("d9d2c3"), 1.0],
	"ruin": [Color("c9c3dc"), 1.0],
	"mine_mouth": [Color("a8927e"), 1.3],
	"meadow": [Color("eadf8f"), 1.1],
	"old_oak": [Color("7fae57"), 1.2],
	"thicket": [Color("6f9a4f"), 1.1],
}
const ICONS := {"haven": "map_house", "glade": "map_glade", "quarry": "map_quarry", "ruin": "map_ruin",
	"mine_mouth": "map_mine", "pond": "map_pond", "meadow": "map_flower", "old_oak": "map_oak", "thicket": "map_thorn"}
const PATHS := [["haven", "glade"], ["haven", "meadow"], ["haven", "old_oak"], ["old_oak", "thicket"], ["old_oak", "ruin"],
	["haven", "@1", "quarry"], ["haven", "@0", "mine_mouth"], ["haven", "@2", "pond"]]

var target_id: String = ""
var show_player: bool = true
var _t := 0.0
var _trees: Array = []
var _stream: PackedVector2Array


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stream = _spline(Layout.STREAM_POINTS, 10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240517
	var tries := 0
	while _trees.size() < 150 and tries < 2000:
		tries += 1
		var p := Vector2(rng.randf_range(-106, 106), rng.randf_range(-106, 106))
		if _near_stream(p, 9.0) or _in_landmark(p, 0.85):
			continue
		_trees.append([p, rng.randf_range(3.2, 5.2), rng.randi() % 3])


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		queue_redraw()


func map_rect() -> Rect2:
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	return rect.grow(-16.0)


func to_map(w: Vector2) -> Vector2:
	return UiUtil.world_to_map(w, map_rect(), H)


func _draw() -> void:
	var side := minf(size.x, size.y)
	var outer := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var r := map_rect()
	var scale := r.size.x / (H * 2.0)
	draw_style_box(ThemeFactory.box(Color("efdcb4"), 24, 3, ThemeFactory.BORDER_DARK, 0, 8, Vector2(0, 4), Color(0.2, 0.1, 0.1, 0.25)), outer)
	draw_style_box(ThemeFactory.box(Color("bcd98d"), 18), r)
	# soft terrain regions
	for id in REGIONS:
		var lm: Dictionary = Layout.LANDMARKS.get(id, {})
		if lm.is_empty():
			continue
		var c := to_map(lm["pos"])
		var rad := float(lm["radius"]) * float(REGIONS[id][1]) * scale
		_soft_disc(c, rad, REGIONS[id][0])
	# rocky cliffs around the mine
	var mm: Vector2 = Layout.LANDMARKS["mine_mouth"]["pos"]
	for k in 7:
		var off := Vector2(cos(float(k) * 0.9 - 2.4), sin(float(k) * 0.9 - 2.4)) * (12.0 + float(k % 3) * 3.0)
		var cc := to_map(mm + off)
		draw_circle(cc, (5.0 + float(k % 3)) * scale, Color("8f7d6a"), true, -1.0, true)
	# footpaths
	for path in PATHS:
		var pts := PackedVector2Array()
		for node in path:
			pts.append(to_map(_path_point(String(node))))
		for i in pts.size() - 1:
			draw_dashed_line(pts[i], pts[i + 1], Color(Palette.DIRT_DARK, 0.75), 3.0, 9.0, true, true)
	# stream
	var sp := PackedVector2Array()
	for p in _stream:
		sp.append(to_map(p))
	var sw := maxf(Layout.STREAM_WIDTH * scale * 1.5, 8.0)
	draw_polyline(sp, Palette.WATER_DEEP, sw + 5.0, true)
	draw_polyline(sp, Palette.WATER, sw, true)
	draw_polyline(sp, Color(1, 1, 1, 0.45), maxf(sw * 0.22, 1.5), true)
	# pond
	var pond: Vector2 = Layout.LANDMARKS["pond"]["pos"]
	var pc := to_map(pond)
	var pr := float(Layout.LANDMARKS["pond"]["radius"]) * scale * 0.95
	_ellipse(pc, Vector2(pr * 1.2, pr * 0.9), Palette.WATER, Palette.WATER_DEEP)
	_ellipse(pc + Vector2(-pr * 0.2, -pr * 0.15), Vector2(pr * 0.5, pr * 0.3), Color(1, 1, 1, 0.3), Color(0, 0, 0, 0))
	# crossings
	for cr in Layout.STREAM_CROSSINGS:
		var cp := to_map(cr)
		var dir := _stream_dir(cr)
		var n := Vector2(-dir.y, dir.x)
		var a := cp - n * (sw * 0.95)
		var b := cp + n * (sw * 0.95)
		draw_line(a, b, ThemeFactory.INK, 9.0, true)
		draw_line(a, b, Palette.WOOD, 6.0, true)
	# trees
	var tree_cols := [Palette.FOLIAGE, Palette.FOLIAGE_DARK, Palette.FOLIAGE_LIGHT.darkened(0.08)]
	for t in _trees:
		var tp := to_map(t[0])
		var tr := float(t[1]) * scale * 0.9
		draw_circle(tp + Vector2(1.5, 2.0), tr, Color(0.2, 0.3, 0.15, 0.25), true, -1.0, true)
		draw_circle(tp, tr, tree_cols[int(t[2])], true, -1.0, true)
		draw_arc(tp, tr, 0.0, TAU, 12, Color(0.22, 0.35, 0.2, 0.7), 1.2, true)
	# forest border frame
	var frame := ThemeFactory.box(Color(0, 0, 0, 0), 18, 16, Color("5f8a45"))
	frame.draw_center = false
	draw_style_box(frame, r)
	var perim := r.grow(-16.0)
	var step := 26.0
	var x := perim.position.x
	while x <= perim.end.x:
		draw_circle(Vector2(x, perim.position.y), 10.0, Color("5f8a45"), true, -1.0, true)
		draw_circle(Vector2(x, perim.end.y), 10.0, Color("5f8a45"), true, -1.0, true)
		x += step
	var y := perim.position.y
	while y <= perim.end.y:
		draw_circle(Vector2(perim.position.x, y), 10.0, Color("5f8a45"), true, -1.0, true)
		draw_circle(Vector2(perim.end.x, y), 10.0, Color("5f8a45"), true, -1.0, true)
		y += step
	# objective pulse (under the sticker)
	if target_id != "" and Layout.LANDMARKS.has(target_id):
		var tc := to_map(Layout.LANDMARKS[target_id]["pos"])
		for k in 2:
			var ph := fmod(_t * 0.7 + float(k) * 0.5, 1.0)
			var rr := 26.0 + ph * 34.0
			draw_arc(tc, rr, 0.0, TAU, 48, Color(ThemeFactory.ACCENT, 0.85 * (1.0 - ph)), 4.0, true)
	# friends
	for cid in Game.companion_nodes:
		var cn: Variant = Game.companion_nodes[cid]
		if cn is Node3D and is_instance_valid(cn):
			var p3: Vector3 = (cn as Node3D).global_position
			var cpos := _clamp_in(to_map(Vector2(p3.x, p3.z)), r)
			draw_circle(cpos, 13.0, ThemeFactory.PAPER_LIGHT, true, -1.0, true)
			draw_texture_rect(IconFactory.portrait(String(cid)), Rect2(cpos - Vector2(12, 12), Vector2(24, 24)), false)
			draw_arc(cpos, 13.0, 0.0, TAU, 24, ThemeFactory.INK, 2.0, true)
	# landmarks
	var f := ThemeFactory.font("heading")
	for id in Layout.LANDMARKS:
		var lm: Dictionary = Layout.LANDMARKS[id]
		var c := to_map(lm["pos"])
		var isz := 58.0 if id == "haven" else 50.0
		var icon_id := String(ICONS.get(id, "unknown"))
		draw_texture_rect(IconFactory.icon(icon_id, Color.WHITE, 96), Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false)
		var name := String(lm["name"])
		var fs := 22 if id != "haven" else 24
		var tw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := Vector2(c.x - tw * 0.5, c.y + isz * 0.5 + 18.0)
		lp.x = clampf(lp.x, r.position.x + 20.0, r.end.x - tw - 20.0)
		draw_string_outline(f, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color("f7ecd6"))
		draw_string(f, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ThemeFactory.INK)
	# player
	if show_player and Game.player != null and is_instance_valid(Game.player) and Game.player is Node3D:
		var pp: Vector3 = (Game.player as Node3D).global_position
		var mp := _clamp_in(to_map(Vector2(pp.x, pp.z)), r)
		var ang := UiUtil.map_heading(_facing())
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(mp, 20.0 + pulse * 4.0, Color(Palette.K_JACKET, 0.22), true, -1.0, true)
		draw_arrow(mp, ang)
	# compass
	var cc2 := Vector2(r.end.x - 52.0, r.position.y + 58.0)
	draw_circle(cc2, 30.0, Color(ThemeFactory.PAPER_LIGHT, 0.92), true, -1.0, true)
	draw_arc(cc2, 30.0, 0.0, TAU, 32, ThemeFactory.INK, 2.5, true)
	draw_colored_polygon(PackedVector2Array([cc2 + Vector2(0, -24), cc2 + Vector2(8, 2), cc2 + Vector2(-8, 2)]), ThemeFactory.ACCENT)
	draw_colored_polygon(PackedVector2Array([cc2 + Vector2(0, 24), cc2 + Vector2(8, 2), cc2 + Vector2(-8, 2)]), ThemeFactory.INK_SOFT)
	draw_string(f, cc2 + Vector2(-8, -34), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ThemeFactory.INK)


func draw_arrow(pos: Vector2, ang: float) -> void:
	var fwd := Vector2(cos(ang), sin(ang))
	var right := Vector2(-fwd.y, fwd.x)
	var tip := pos + fwd * 20.0
	var back := pos - fwd * 12.0
	var pts := PackedVector2Array([tip, pos - fwd * 8.0 + right * 13.0, back, pos - fwd * 8.0 - right * 13.0])
	var outline := PackedVector2Array([tip, pos - fwd * 8.0 + right * 13.0, back, pos - fwd * 8.0 - right * 13.0, tip])
	draw_colored_polygon(pts, Palette.K_JACKET)
	draw_polyline(outline, ThemeFactory.INK, 3.0, true)
	draw_circle(pos, 3.0, ThemeFactory.CREAM, true, -1.0, true)


func _facing() -> Vector3:
	var pl: Node = Game.player
	if pl != null and pl.has_method("get_camera"):
		var cam: Variant = pl.get_camera()
		if cam is Camera3D and is_instance_valid(cam):
			return -(cam as Camera3D).global_transform.basis.z
	var vp := get_viewport()
	if vp != null and vp.get_camera_3d() != null:
		return -vp.get_camera_3d().global_transform.basis.z
	if pl is Node3D:
		return -(pl as Node3D).global_transform.basis.z
	return Vector3.FORWARD


func _clamp_in(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x + 18.0, r.end.x - 18.0), clampf(p.y, r.position.y + 18.0, r.end.y - 18.0))


func _soft_disc(c: Vector2, rad: float, col: Color) -> void:
	for i in 4:
		var k := 1.0 - float(i) * 0.16
		draw_circle(c, rad * k, Color(col, 0.28 + 0.12 * float(i)), true, -1.0, true)


func _ellipse(c: Vector2, rr: Vector2, fill: Color, line: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * float(i) / 40.0
		pts.append(c + Vector2(cos(a) * rr.x, sin(a) * rr.y))
	draw_colored_polygon(pts, fill)
	if line.a > 0.0:
		pts.append(pts[0])
		draw_polyline(pts, line, 3.0, true)


func _path_point(node: String) -> Vector2:
	if node.begins_with("@"):
		return Layout.STREAM_CROSSINGS[int(node.substr(1))]
	return Layout.LANDMARKS[node]["pos"]


func _near_stream(p: Vector2, d: float) -> bool:
	for i in _stream.size() - 1:
		if Geometry2D.get_closest_point_to_segment(p, _stream[i], _stream[i + 1]).distance_to(p) < d:
			return true
	var pond: Vector2 = Layout.LANDMARKS["pond"]["pos"]
	return p.distance_to(pond) < 16.0


func _in_landmark(p: Vector2, k: float) -> bool:
	for id in Layout.LANDMARKS:
		var lm: Dictionary = Layout.LANDMARKS[id]
		if p.distance_to(lm["pos"]) < float(lm["radius"]) * k + 6.0:
			return true
	return false


func _stream_dir(at: Vector2) -> Vector2:
	var best := 1e9
	var dir := Vector2.DOWN
	for i in _stream.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(at, _stream[i], _stream[i + 1])
		var d := q.distance_to(at)
		if d < best:
			best = d
			dir = (_stream[i + 1] - _stream[i]).normalized()
	return dir


static func _spline(points: Array, samples: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	if n < 2:
		return out
	for i in n - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, n - 1)]
		for s in samples:
			var t := float(s) / float(samples)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[n - 1])
	return out

extends PanelContainer
## Parchment surface: themed rounded panel + subtle paper grain (shader) + a dashed "stitch" line
## inset from the border, and an optional title ribbon that straddles the top edge.
##   var p := preload("res://src/ui/widgets/parchment_panel.gd").new()
##   p.set_ribbon("Backpack")

const ThemeFactory := preload("res://src/ui/theme_factory.gd")

var stitch: bool = true
var stitch_inset: float = 12.0
var stitch_color: Color = Color(0.55, 0.38, 0.28, 0.42)
var ribbon: PanelContainer = null
var ribbon_label: Label = null
var grain: bool = true


func _ready() -> void:
	if grain:
		material = ThemeFactory.paper_material()
	sort_children.connect(_place_ribbon)
	resized.connect(queue_redraw)


## Adds (or retitles) the ribbon. The panel's top margin grows so content clears it.
func set_ribbon(text: String) -> void:
	if ribbon == null:
		ribbon = PanelContainer.new()
		ribbon.theme_type_variation = "Ribbon"
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ribbon_label = Label.new()
		ribbon_label.theme_type_variation = "RibbonTitle"
		ribbon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ribbon.add_child(ribbon_label)
		add_child(ribbon)
		var sb: StyleBoxFlat = ThemeFactory.parchment_style().duplicate()
		sb.content_margin_top = 52
		add_theme_stylebox_override("panel", sb)
	ribbon_label.text = text
	queue_sort()


func _place_ribbon() -> void:
	if ribbon == null:
		return
	var ms := ribbon.get_combined_minimum_size()
	ribbon.size = ms
	ribbon.position = Vector2(round((size.x - ms.x) * 0.5), round(-ms.y * 0.45))


func _draw() -> void:
	if not stitch or size.x < 60.0 or size.y < 60.0:
		return
	var r := Rect2(Vector2(stitch_inset, stitch_inset), size - Vector2(stitch_inset, stitch_inset) * 2.0)
	var rad := 15.0
	var pts := _rounded_rect_points(r, rad, 6)
	_dashed(pts, 11.0, 8.0, stitch_color, 2.0)


static func _rounded_rect_points(r: Rect2, rad: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
		[Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
	]
	for c in corners:
		var center: Vector2 = c[0]
		var a0: float = c[1]
		for i in seg + 1:
			var a := a0 + (PI * 0.5) * float(i) / float(seg)
			out.append(center + Vector2(cos(a), sin(a)) * rad)
	out.append(out[0])
	return out


func _dashed(pts: PackedVector2Array, dash: float, gap: float, col: Color, width: float) -> void:
	var on := true
	var remain := dash
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg_len := a.distance_to(b)
		var t := 0.0
		while t < seg_len:
			var step := minf(remain, seg_len - t)
			var p0 := a.lerp(b, t / seg_len)
			var p1 := a.lerp(b, (t + step) / seg_len)
			if on:
				draw_line(p0, p1, col, width, true)
			t += step
			remain -= step
			if remain <= 0.001:
				on = not on
				remain = dash if on else gap

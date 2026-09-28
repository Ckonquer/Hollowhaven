extends RefCounted
## Seasonal decor (spec 7.1, Settings "seasonal_decor", default off): a few pumpkins and ribbon stakes along the
## Hollowhaven Woods dirt paths (data/c1x_layout.gd SEASONAL_*). Only decoration: no colliders, no interaction,
## nothing persistent, never inside the Haven build area (the legacy circle or any Chapter Two "extra" region,
## checked again here at runtime) and never in the house. Built lazily the first time the setting is on; toggling
## the setting (Events.settings_changed) shows / hides it live.
##   SeasonalDecor.build(area)
## Decor node (group "c1x_seasonal_decor"): refresh(), built: bool, piece_positions() -> Array[Vector2].

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")


static func build(area: Node3D) -> void:
	if area == null:
		return
	var parent := Common.sub_root(area, "SeasonalDecor")
	var decor := Decor.new()
	decor.name = "Decor"
	decor.area = area
	parent.add_child(decor)


class Decor extends Node3D:
	const L := preload("res://data/c1x_layout.gd")
	const Common := preload("res://src/world/surface/c1x/common.gd")
	const SETTING := "seasonal_decor"
	const RIBBON_CYCLE := ["pumpkin", "lavender", "sunflower", "rose"]

	var area: Node = null
	var built := false
	var _positions: Array = []

	func _ready() -> void:
		add_to_group("c1x_seasonal_decor")
		if not Events.settings_changed.is_connected(_on_settings_changed):
			Events.settings_changed.connect(_on_settings_changed)
		refresh()

	func _on_settings_changed(key: String) -> void:
		if key == SETTING or key == "":
			refresh()

	## Shows the decor when the setting is on (building it the first time), hides it otherwise.
	func refresh() -> void:
		var on := bool(Settings.get_value(SETTING))
		if on and not built:
			_build_now()
		visible = on

	## World XZ of every piece actually placed (after the build-area filter).
	func piece_positions() -> Array:
		return _positions.duplicate()

	func _build_now() -> void:
		built = true
		var xforms: Array = []
		for i in L.SEASONAL_PUMPKINS.size():
			var e: Array = L.SEASONAL_PUMPKINS[i]
			var p: Vector2 = e[0]
			if Common.in_build_area(p, L.SEASONAL_BUILD_MARGIN):
				continue
			var yaw := deg_to_rad(float(e[1]))
			var n := clampi(int(e[2]), 1, 3)
			for k in n:
				# a small cluster: the first pumpkin at the spot, the others beside it along the path
				var side := Vector2(cos(yaw), -sin(yaw)) * (0.55 * float(k))
				var q := p + side
				var s := 1.0 - 0.18 * float(k)
				xforms.append(Transform3D(Basis(Vector3.UP, yaw + float(k) * 0.9).scaled(Vector3.ONE * s), Common.ground(area, q, -0.02)))
			_positions.append(p)
		if not xforms.is_empty():
			var mm := Common.Props.multimesh(Common.pumpkin_mesh(0), Common.prop_material(0.014), xforms, "Pumpkins", 90.0, true)
			add_child(mm)
		for i in L.SEASONAL_RIBBONS.size():
			var e: Array = L.SEASONAL_RIBBONS[i]
			var p: Vector2 = e[0]
			if Common.in_build_area(p, L.SEASONAL_BUILD_MARGIN):
				continue
			var col: Color = Common.RIBBON_COLORS[RIBBON_CYCLE[i % RIBBON_CYCLE.size()]]
			var r := Common.ribbon_marker(col, i, false)
			r.name = "c1x_path_ribbon_%d" % i
			Common.place(self, r, area, p, float(e[1]), -0.02)
			_positions.append(p)

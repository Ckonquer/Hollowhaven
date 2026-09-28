extends RefCounted
## Lantern Moth dusk pocket (MP 7/12 "optional dusk pocket"; spec 7.1): a few pale moonbells on Mirror Pond's
## quiet east shore where Lantern Moths gather ONLY at dusk and at night (data/c1x_layout.gd MOTH_HOURS, wrapping
## midnight). Far from the Haven and the peaceful Berry Glade (more than the moths' leash + zone radius away).
## Spawner c1x_sp_moths (NEW id) through the shared EnemySpawner/EnemyFactory; built only when the lantern_moth
## script is available (another module builds it). It never pops in within view (layout "out_of_view": at dusk
## the moths gather somewhere her camera does not see). The Pocket node gates the spawner by the clock once a second:
##   awake  -> the spawner runs normally (its own 45 m / safe-zone / cooldown rules)
##   asleep -> the spawner stops at once (no new moth by day); living ones stay while one of them is in a
##             fight, then flutter off (a small sparkle puff where each one was).
## The moonbells glow softly while the pocket is awake (a steady material swap, never flashing): their bell caps
## light up (a glow shell) and a small unshadowed moonlight-blue lamp lifts the shore around them.
##   MothPocket.build(area)
## Pocket node (group "c1x_moth_pocket"): spawner, is_awake() -> bool, update() (one gate step), hour_override
## (tests; < 0 = the game clock), attach_spawner(node) (tests / late creation).

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")


static func build(area: Node3D) -> void:
	if area == null:
		return
	var parent := Common.sub_root(area, "MothPocket")
	var pocket := Pocket.new()
	pocket.name = "Pocket"
	Common.place(parent, pocket, area, L.MOTH_SPAWNER["pos"], 0.0)
	var xforms: Array = []
	for i in L.MOTH_BLOOMS.size():
		var b: Vector2 = L.MOTH_BLOOMS[i]
		var g := Common.ground(area, b, -0.02)
		xforms.append(Transform3D(Basis(Vector3.UP, float(i) * 1.7).scaled(Vector3.ONE * (0.9 + 0.08 * float(i % 3))), g - pocket.global_position))
	pocket.build_blooms(xforms)
	var sp := Common.make_spawner(parent, area, L.MOTH_SPAWNER)
	if sp != null:
		sp.setup(L.spawner_extras(L.MOTH_SPAWNER))     # out_of_view: moths never pop in where she is looking
		pocket.attach_spawner(sp)


class Pocket extends Node3D:
	const L := preload("res://data/c1x_layout.gd")
	const Common := preload("res://src/world/surface/c1x/common.gd")
	const Fx := preload("res://src/world/common/fx.gd")
	const TICK := 1.0

	var spawner: Node3D = null
	var hour_override: float = -1.0
	var awake := false
	var blooms: MultiMeshInstance3D = null
	var glow_caps: MultiMeshInstance3D = null
	var halos: MultiMeshInstance3D = null
	var glow_light: OmniLight3D = null
	var _t := 0.0

	func _ready() -> void:
		add_to_group("c1x_moth_pocket")
		_t = TICK

	func build_blooms(xforms: Array) -> void:
		blooms = Common.Props.multimesh(Common.moonbell_mesh(), Common.moonbell_material(false), xforms, "Moonbells", 70.0, false)
		add_child(blooms)
		glow_caps = Common.Props.multimesh(Common.moonbell_glow_mesh(), Common.moonbell_glow_material(), xforms, "MoonbellGlow", 90.0, false)
		add_child(glow_caps)
		var hx: Array = []
		for x in xforms:
			hx.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.9), (x as Transform3D).origin + Vector3(0, 0.5, 0)))
		halos = Common.Props.multimesh(Common.halo_quad(), Common.moonbell_halo_material(), hx, "MoonbellHalos", 90.0, false)
		add_child(halos)
		var centre := Vector3.ZERO
		for x in xforms:
			centre += (x as Transform3D).origin
		centre /= maxf(float(xforms.size()), 1.0)
		glow_light = OmniLight3D.new()
		glow_light.name = "MoonbellLight"
		glow_light.light_color = Common.MOONBELL_GLOW
		glow_light.light_energy = 1.4
		glow_light.omni_range = 5.5
		glow_light.shadow_enabled = false
		glow_light.distance_fade_enabled = true
		glow_light.distance_fade_begin = 45.0
		glow_light.distance_fade_length = 10.0
		glow_light.position = centre + Vector3(0, 0.8, 0)
		add_child(glow_light)
		_apply_blooms()

	func attach_spawner(sp: Node3D) -> void:
		spawner = sp
		update()

	func is_awake() -> bool:
		var h := hour_override if hour_override >= 0.0 else GameState.hour()
		return L.is_moth_time(h)

	func _process(delta: float) -> void:
		_t += delta
		if _t < TICK:
			return
		_t = 0.0
		update()

	## One gate step: wakes / sleeps the spawner and the moonbells.
	func update() -> void:
		var on := is_awake()
		if on != awake:
			awake = on
			_apply_blooms()
		if spawner == null or not is_instance_valid(spawner):
			return
		if on:
			if not spawner.is_processing():
				spawner.set_process(true)
			return
		# Asleep: the spawner stops at once (no new moth by day, not even to replace one lost mid-fight);
		# moths already out stay while one of them is fighting, then flutter off (a soft puff, not a pop).
		if spawner.is_processing():
			spawner.set_process(false)
		var alive_v: Variant = spawner.get("alive")
		if not (alive_v is Array) or (alive_v as Array).is_empty():
			return
		var alive: Array = alive_v
		for e in alive:
			if is_instance_valid(e) and (e as Node).has_method("is_threatening") and bool((e as Node).is_threatening()):
				return
		for e in alive:
			if is_instance_valid(e) and e is Node3D and (e as Node3D).is_inside_tree():
				Fx.burst(get_parent(), (e as Node3D).global_position + Vector3.UP * 0.3, "sparkle", 0.5)
		if spawner.has_method("despawn_all"):
			spawner.despawn_all()

	func _apply_blooms() -> void:
		if blooms != null:
			blooms.material_override = Common.moonbell_material(awake)
		if glow_caps != null:
			glow_caps.visible = awake
		if halos != null:
			halos.visible = awake
		if glow_light != null:
			glow_light.visible = awake

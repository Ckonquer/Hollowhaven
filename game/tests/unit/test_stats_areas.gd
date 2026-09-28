extends "res://tests/test_case.gd"
## Area-aware player checks for the Chapter Two areas (spec section 9): world bounds and under-terrain
## recovery for outdoor areas (surface AND hallowmere_reach), lantern look per area kind, kill heights, and
## the horror-intensity damage scaling of underground areas (combat.gd). Legacy surface/below numbers unchanged.

const Logic := preload("res://src/player/player_logic.gd")
const Combat := preload("res://src/combat/combat.gd")
const Layout := preload("res://data/world_layout.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const Palette := preload("res://src/art/palette.gd")
const PlayerScript := preload("res://src/player/player.gd")

var _saved_intensity: Variant
var _saved_area_id := ""
var _saved_area: Node = null
var player: CharacterBody3D
var floor_body: StaticBody3D


func before_each() -> void:
	fresh_state()
	_saved_intensity = Settings.get_value("horror_intensity")
	_saved_area_id = Game.area_id
	_saved_area = Game.area


func after_each() -> void:
	Settings.set_value("horror_intensity", _saved_intensity)
	Game.area_id = _saved_area_id
	Game.area = _saved_area
	for c in get_children():
		c.queue_free()
	await wait_frames(2)


func test_outdoor_areas_match_game_and_layout_data() -> void:
	assert_eq(Logic.OUTDOOR_AREAS, Game.OUTDOOR_AREAS, "same outdoor list as Game")
	assert_eq(Logic.world_half_extents("surface"), Vector2(Layout.WORLD_HALF_EXTENT, Layout.WORLD_HALF_EXTENT))
	assert_eq(Logic.world_half_extents("hallowmere_reach"), Vector2(Reach.HALF_X, Reach.HALF_Z))
	for a in ["below", "tobin_annex", "hushed_works", "moonveil_manor", "echo_trial"]:
		assert_eq(Logic.world_half_extents(a), Vector2.ZERO, "%s has no world bounds" % a)


func test_recovery_bounds_per_area() -> void:
	var kill := Layout.KILL_Y
	var sb := Logic.world_half_extents("surface")
	var rb := Logic.world_half_extents("hallowmere_reach")
	assert_eq(Logic.recovery_reason_bounds(Vector3(125, 5, 0), sb, kill, NAN, 0.0), "outside", "surface edge (legacy)")
	assert_eq(Logic.recovery_reason_bounds(Vector3(125, 5, 0), rb, kill, NAN, 0.0), "", "the Reach is wider (140 m)")
	assert_eq(Logic.recovery_reason_bounds(Vector3(155, 5, 0), rb, kill, NAN, 0.0), "outside", "past the Reach edge + margin")
	assert_eq(Logic.recovery_reason_bounds(Vector3(0, 5, 125), rb, kill, NAN, 0.0), "outside", "Reach z extent is 110")
	assert_eq(Logic.recovery_reason_bounds(Vector3(500, 5, 0), Vector2.ZERO, kill, NAN, 0.0), "", "no bounds underground")
	assert_eq(Logic.recovery_reason_bounds(Vector3(0, 1, 0), rb, kill, 4.0, 0.5), "below_floor", "under the Reach terrain")
	# the legacy signature keeps its exact behaviour
	assert_eq(Logic.recovery_reason(Vector3(125, 5, 0), "surface", kill, Layout.WORLD_HALF_EXTENT, NAN, 0.0), "outside")
	assert_eq(Logic.recovery_reason(Vector3(125, 5, 0), "below", kill, Layout.WORLD_HALF_EXTENT, NAN, 0.0), "")
	assert_true(Logic.in_world_bounds(Vector3(141, 0, 0), "hallowmere_reach"))
	assert_false(Logic.in_world_bounds(Vector3(143, 0, 0), "hallowmere_reach"))
	assert_false(Logic.in_world_bounds(Vector3(113, 0, 0), "surface"))
	assert_true(Logic.in_world_bounds(Vector3(900, 0, 0), "hushed_works"))


func test_kill_heights() -> void:
	assert_almost(Logic.kill_y_for("surface", Layout.KILL_Y), -40.0, 0.001)
	assert_almost(Logic.kill_y_for("below", Layout.KILL_Y), -40.0, 0.001, "legacy")
	assert_true(Logic.kill_y_for("hushed_works", Layout.KILL_Y) < -34.0 - 10.0, "well below the Works' lowest floor (-34)")


func test_lantern_scale_and_tint_by_area_kind() -> void:
	# outdoor: soft in daylight, full at night (surface legacy numbers unchanged)
	for a in ["surface", "hallowmere_reach"]:
		assert_almost(Logic.lantern_scale(a, 12.0), 0.45, 0.0001, "%s noon" % a)
		assert_almost(Logic.lantern_scale(a, 23.0), 1.0, 0.0001, "%s night" % a)
	assert_almost(Logic.lantern_scale("hallowmere_reach", 18.25), Logic.lantern_scale("surface", 18.25), 0.0001, "same dusk curve")
	# underground and interiors: full strength at any hour
	for a in ["below", "tobin_annex", "hushed_works", "moonveil_manor", "echo_trial"]:
		assert_almost(Logic.lantern_scale(a, 12.0), 1.0, 0.0001, "%s at noon" % a)
	var base := Palette.LANTERN_GLOW
	assert_eq(Logic.lantern_tint("surface", base), base)
	assert_eq(Logic.lantern_tint("below", base), base)
	var warm := Logic.lantern_tint("moonveil_manor", base)
	assert_true(warm != base, "interiors get their own tint")
	assert_true(warm.b < base.b and warm.r >= base.r - 0.001, "and it is warmer (less blue)")
	assert_eq(Logic.lantern_tint("echo_trial", base), warm)


func test_underground_threats_scale_with_intensity() -> void:
	Settings.set_value("horror_intensity", 0)
	for a in ["below", "tobin_annex", "hushed_works"]:
		assert_almost(Combat.damage_mult_for_area(a), 0.6, 0.001, "%s Gentle" % a)
	for a in ["surface", "hallowmere_reach", "moonveil_manor", "echo_trial"]:
		assert_almost(Combat.damage_mult_for_area(a), 1.0, 0.001, "%s never scales" % a)
	Settings.set_value("horror_intensity", 2)
	assert_almost(Combat.damage_mult_for_area("hushed_works"), 1.15, 0.001)
	assert_almost(Combat.damage_mult_for_area("below"), 1.15, 0.001, "legacy Below number")
	assert_almost(Combat.damage_mult_for_area("surface"), 1.0, 0.001)


## A fake outdoor area whose terrain is 6 m above the floor body: an airborne Krystal under it is recovered.
class FakeTerrain extends Node:
	func height_at(_x: float, _z: float) -> float:
		return 6.0


func _spawn(pos: Vector3) -> void:
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = pos + Vector3(0, -0.5, 0)
	player = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.teleport(Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.05, 0)))


func test_reach_player_is_recovered_outside_the_world() -> void:
	Game.area_id = "hallowmere_reach"
	_spawn(Vector3(130, 0, 0))
	await wait_physics(40)                      # safe points recorded at x=130 (inside the Reach, outside the surface)
	assert_true(player.call("_in_world_bounds"), "x=130 is inside the Reach")
	var safe: Vector3 = player.global_position
	player.global_position = Vector3(160, 0.05, 0)
	await wait_physics(4)
	assert_true(player.global_position.distance_to(safe) < 1.5, "recovered from beyond the Reach edge (%s)" % str(player.global_position))


func test_reach_under_terrain_recovery_is_outdoor_only() -> void:
	Game.area_id = "hallowmere_reach"
	var fa := FakeTerrain.new()
	add_child(fa)
	Game.area = fa
	_spawn(Vector3(30, 0, 30))
	await wait_physics(40)
	var safe: Vector3 = player.global_position
	player.global_position = Vector3(30, 3.0, 60)      # airborne (no floor here), 3 m under the fake terrain
	await wait_physics(75)
	assert_eq(player.recoveries, 1, "outdoor: an airborne Krystal under the terrain is recovered (once)")
	assert_true(player.global_position.distance_to(safe) < 1.5)
	# the same situation in an interior never checks a heightfield
	Game.area_id = "moonveil_manor"
	var before: int = player.recoveries
	player.global_position = Vector3(30, 3.0, 60)
	await wait_physics(75)
	assert_eq(player.recoveries, before, "interiors don't use the under-terrain check")


## Review addition: the player applies the lantern look it computes - Kindling Charm radius (light_radius for
## Combat.light_at + the avatar's OmniLight range, refreshed on equip/unequip) and the warmer interior tint.
func test_player_lantern_radius_charm_and_interior_tint() -> void:
	Game.area_id = "surface"
	_spawn(Vector3(-40, 0, -40))
	await wait_physics(4)
	var l: OmniLight3D = player.avatar.get_lantern_light()
	assert_not_null(l, "avatar lantern light")
	player.call("_refresh_owned")
	assert_almost(float(player.light_radius), 6.0, 0.0001, "legacy radius")
	assert_almost(l.omni_range, 7.0, 0.0001, "legacy lantern light range")
	assert_eq(l.light_color, Palette.LANTERN_GLOW, "legacy colour outdoors")
	GameState.give_item("kindling_charm", 1)
	assert_true(GameState.equip("kindling_charm"))
	assert_almost(float(player.light_radius), 6.0 * 1.2, 0.0001, "Kindling Charm: +20% light radius at once")
	assert_almost(l.omni_range, 7.0 * 1.2, 0.0001)
	Game.area_id = "moonveil_manor"
	player.call("_refresh_owned")
	assert_eq(l.light_color, Logic.lantern_tint("moonveil_manor", Palette.LANTERN_GLOW), "warmer indoors")
	assert_true(GameState.unequip("charm"))
	assert_almost(float(player.light_radius), 6.0, 0.0001, "back to legacy after taking it off")
	assert_almost(l.omni_range, 7.0, 0.0001)

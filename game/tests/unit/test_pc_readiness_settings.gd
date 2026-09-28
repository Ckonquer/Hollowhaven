extends "res://tests/test_case.gd"
## 2.0.3 (the gift build, first played on a different, unknown Windows PC): the project settings that decide whether
## the game still starts and stays readable on that PC. Every value below is what the packaged 2.0.2 build was probed
## with on screen (docs/ch2/DIFFERENT_PC_READINESS.md): the default Windows driver (Vulkan), the automatic fallback
## chain the packaged exe really walked when a driver was made unavailable (Vulkan -> Direct3D 12 -> OpenGL 3 /
## Compatibility; ANGLE is linked into the exe), the file log a player can send when something goes wrong, and the
## window / UI scaling the small-window and odd-aspect probes (1280x720 .. 21:9) relied on.
## Most of these are Godot defaults (project.godot does not list them): the test reads the EFFECTIVE values, so a
## project.godot edit or a future engine default that turns one off fails here instead of on Krystal's PC.


func _setting(key: String) -> Variant:
	assert_true(ProjectSettings.has_setting(key), "project setting %s exists in this engine version" % key)
	return ProjectSettings.get_setting(key)


func test_renderer_is_forward_plus_on_a_verified_windows_driver() -> void:
	assert_eq(String(_setting("rendering/renderer/rendering_method")), "forward_plus",
		"Forward+ is the renderer every visual QA pass used (the fallbacks below start from it)")
	var drv := String(_setting("rendering/rendering_device/driver.windows"))
	assert_true(drv in ["vulkan", "d3d12"], "Windows starts on Vulkan or Direct3D 12 (both probed), got %s" % drv)


func test_rendering_device_fallbacks_stay_on() -> void:
	# A PC without working Vulkan drivers switches to Direct3D 12 (probe f1_no_vulkan), and one without either to
	# OpenGL 3 / the Compatibility renderer (probe f2_no_vulkan_no_d3d12) instead of showing an error box and quitting.
	assert_true(bool(_setting("rendering/rendering_device/fallback_to_d3d12")), "Vulkan missing -> Direct3D 12")
	assert_true(bool(_setting("rendering/rendering_device/fallback_to_vulkan")), "Direct3D 12 missing -> Vulkan")
	assert_true(bool(_setting("rendering/rendering_device/fallback_to_opengl3")),
		"neither Vulkan nor Direct3D 12 -> OpenGL 3 (Compatibility renderer)")


func test_compatibility_renderer_fallbacks_stay_on() -> void:
	# The last resort: native OpenGL 3.3, else ANGLE (OpenGL ES over Direct3D 11, linked into the exe; probe c2_angle),
	# and ANGLE forced for the old GPUs whose OpenGL drivers Godot knows to be broken.
	assert_eq(String(_setting("rendering/gl_compatibility/driver.windows")), "opengl3", "native OpenGL first")
	assert_true(bool(_setting("rendering/gl_compatibility/fallback_to_angle")), "no usable OpenGL 3.3 -> ANGLE")
	assert_true(bool(_setting("rendering/gl_compatibility/fallback_to_native")), "no usable ANGLE -> native OpenGL")
	var forced: Variant = _setting("rendering/gl_compatibility/force_angle_on_devices")
	assert_true(forced is Array and not (forced as Array).is_empty(),
		"the engine's list of GPUs with broken OpenGL drivers (sent to ANGLE) is kept")


func test_player_pc_keeps_a_log_file_to_send() -> void:
	# "The game doesn't start / crashed": the player can send %APPDATA%\Hollowhaven\logs\godot.log.
	assert_true(bool(_setting("debug/file_logging/enable_file_logging.pc")), "release builds on PC write a log file")
	assert_eq(String(_setting("debug/file_logging/log_path")), "user://logs/godot.log", "... in user://logs")
	assert_true(int(_setting("debug/file_logging/max_log_files")) >= 2, "... and keep the previous run's log too")
	assert_true(bool(_setting("application/config/use_custom_user_dir")), "user:// is %APPDATA%\\<name>")
	assert_eq(String(_setting("application/config/custom_user_dir_name")), "Hollowhaven", "... named Hollowhaven")


func test_window_and_ui_scale_to_any_screen() -> void:
	# The UI is laid out for 1920x1080 and scales to the window (probed at 1280x720, 1366x768, 16:10, 21:9);
	# DPI-aware so a 150% / 4K laptop screen shows it sharp instead of blurred by Windows.
	assert_eq(String(_setting("display/window/stretch/mode")), "canvas_items", "UI scales with the window")
	assert_eq(String(_setting("display/window/stretch/aspect")), "expand", "other shapes than 16:9 add room, no bars")
	assert_eq(int(_setting("display/window/size/viewport_width")), 1920, "UI base width")
	assert_eq(int(_setting("display/window/size/viewport_height")), 1080, "UI base height")
	assert_true(bool(_setting("display/window/dpi/allow_hidpi")), "DPI-aware window (sharp on scaled screens)")
	assert_true(bool(_setting("display/window/size/resizable")), "the windowed mode can be resized")


func test_no_microphone_and_screen_stays_on() -> void:
	# Nothing on first launch asks Windows for microphone access; a quiet stretch of play does not blank the screen.
	assert_false(bool(_setting("audio/driver/enable_input")), "audio input (microphone) is never opened")
	assert_true(bool(_setting("display/window/energy_saving/keep_screen_on")), "the screen saver waits while playing")

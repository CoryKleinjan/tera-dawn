class_name VideoSettings
extends SettingsSection
## The window (mode, size, vsync, frame rate cap) and the HD-2D effects that cost the most
## on slower computers. TDStage reads the effects whenever Settings.changed fires.

enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }
const WINDOW_MODE_NAMES: Array[String] = ["Windowed", "Fullscreen", "Borderless fullscreen"]
## Window sizes offered in windowed mode (the game draws at 960x540 and scales up).
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
## Frame rate caps offered; 0 is no cap.
const FPS_CAPS: Array[int] = [0, 30, 60, 120, 144, 240]

var window_mode := WindowMode.WINDOWED
var window_size := Vector2i(1600, 900)
var vsync := true
var max_fps := 0
var bloom := true
var ambient_occlusion := true
var fog := true

# What the window was last set to, so changing an effect doesn't move or resize it.
var _shown_mode := -1
var _shown_size := Vector2i.ZERO

func section() -> String:
	return "video"

func reset() -> void:
	window_mode = WindowMode.WINDOWED
	window_size = Vector2i(1600, 900)
	vsync = true
	max_fps = 0
	bloom = true
	ambient_occlusion = true
	fog = true

func load_from(cfg: ConfigFile) -> void:
	var s := section()
	var mode := int(cfg.get_value(s, "window_mode", window_mode))
	if mode >= 0 and mode < WindowMode.size():
		window_mode = mode as WindowMode
	var size: Variant = cfg.get_value(s, "window_size", window_size)
	if size is Vector2i and size in WINDOW_SIZES:
		window_size = size
	var fps := int(cfg.get_value(s, "max_fps", max_fps))
	if fps in FPS_CAPS:
		max_fps = fps
	vsync = bool(cfg.get_value(s, "vsync", vsync))
	bloom = bool(cfg.get_value(s, "bloom", bloom))
	ambient_occlusion = bool(cfg.get_value(s, "ambient_occlusion", ambient_occlusion))
	fog = bool(cfg.get_value(s, "fog", fog))

func save_to(cfg: ConfigFile) -> void:
	var s := section()
	cfg.set_value(s, "window_mode", window_mode)
	cfg.set_value(s, "window_size", window_size)
	cfg.set_value(s, "vsync", vsync)
	cfg.set_value(s, "max_fps", max_fps)
	cfg.set_value(s, "bloom", bloom)
	cfg.set_value(s, "ambient_occlusion", ambient_occlusion)
	cfg.set_value(s, "fog", fog)

## F11: between a window and borderless fullscreen.
func toggle_fullscreen() -> void:
	window_mode = WindowMode.BORDERLESS if window_mode == WindowMode.WINDOWED else WindowMode.WINDOWED

## The window sizes that fit on the screen the game is on (always at least the smallest).
static func sizes_that_fit() -> Array[Vector2i]:
	var fits: Array[Vector2i] = []
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	for s in WINDOW_SIZES:
		if s == WINDOW_SIZES[0] or (s.x <= screen.x and s.y <= screen.y):
			fits.append(s)
	return fits

func apply() -> void:
	Engine.max_fps = max_fps
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if window_mode == _shown_mode and (window_mode != WindowMode.WINDOWED or window_size == _shown_size):
		return
	_shown_mode = window_mode
	_shown_size = window_size
	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(window_size)
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			DisplayServer.window_set_position(screen.position + (screen.size - window_size) / 2)

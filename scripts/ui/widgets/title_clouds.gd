class_name TDTitleClouds
extends Control
## Clouds drifting slowly across the title screen's key art, nearer ones bigger, brighter and
## faster (a little parallax). Fills its parent and ignores the mouse.

const CLOUD_ART := ["dawnharbor/clouds_1", "dawnharbor/clouds_2", "dawnharbor/clouds_3", "dawnharbor/clouds_4"]
const COUNT := 9
## Nearest and farthest clouds: how many times their art size, speed in pixels a second, and
## opacity.
const NEAR := Vector3(7.0, 14.0, 0.55)
const FAR := Vector3(3.5, 4.0, 0.3)
## Clouds stay in the top part of the screen (a share of its height).
const SKY := 0.45

var _clouds: Array = []  # [texture, x, y share, depth 0 far..1 near]

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in COUNT:
		var tex: Texture2D = load("res://assets/sprites/backgrounds/%s.png" % CLOUD_ART[i % CLOUD_ART.size()])
		_clouds.append([tex, rng.randf(), rng.randf() * SKY, float(i) / (COUNT - 1)])
	# far ones first, so near ones draw over them
	_clouds.sort_custom(func(a: Array, b: Array) -> bool: return a[3] < b[3])

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for c in _clouds:
		var speed: float = lerpf(FAR.y, NEAR.y, c[3])
		c[1] = fmod(c[1] + speed * delta / maxf(1.0, size.x), 1.0)
	queue_redraw()

func _draw() -> void:
	for c in _clouds:
		var tex: Texture2D = c[0]
		var depth: float = c[3]
		var s := tex.get_size() * lerpf(FAR.x, NEAR.x, depth)
		# from just off the left edge to just off the right
		var x: float = c[1] * (size.x + s.x) - s.x
		draw_texture_rect(tex, Rect2(Vector2(x, c[2] * size.y), s), false, Color(1, 1, 1, lerpf(FAR.z, NEAR.z, depth)))

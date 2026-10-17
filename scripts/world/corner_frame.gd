class_name CornerFrame
extends CanvasLayer
## The leaves hanging into the screen's top corners (BiomeDef.frame_left / frame_right), like
## the dark foreground plants that frame Hollow Knight's screens. Each is one half of a 16:9
## picture, kept whole, so drawing both as tall as the screen in their corners puts every leaf
## where it was painted, on any screen shape. They hang over the world and the characters
## (they are right in front of the camera), take the map's colour grade, and stay under the HUD.

## Over the world, under the stage's colour grade (TDStage._build_post, layer 5).
const LAYER := 4

var _left := TextureRect.new()
var _right := TextureRect.new()
## BiomeDef.frame_scale of the frame showing.
var _scale := 1.0

func _init() -> void:
	layer = LAYER
	for r: TextureRect in [_left, _right]:
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(r)

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)

## Shows `b`'s corner leaves, or none.
func show_for(b: BiomeDef) -> void:
	_scale = b.frame_scale
	_left.texture = b.frame_left
	_right.texture = b.frame_right
	visible = b.frame_left != null or b.frame_right != null
	_fit()

func _fit() -> void:
	var view := get_viewport().get_visible_rect().size
	for r: TextureRect in [_left, _right]:
		if r.texture == null:
			continue
		var h := view.y * _scale
		var size := Vector2(h * r.texture.get_width() / float(r.texture.get_height()), h)
		r.size = size
		r.position = Vector2(0.0 if r == _left else view.x - size.x, 0.0)

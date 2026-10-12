class_name TDStencil
## A faint, flat body shape of the hero (his idle pose, bare) that the equipment window lays
## its gear slots on. Made once from the hero's art, enlarged smoothly so its edge stays soft
## when drawn big.

const TINT := Color(Palette.MIST, 0.16)
## How much smoother than the hero's art the shape is made.
const SMOOTH := 4

static var _tex: ImageTexture

## The shape, trimmed to the hero's visible pixels (feet at the bottom edge).
static func texture() -> ImageTexture:
	if _tex == null:
		var frame := (Paperdoll.FRAMES.get_frame_texture(&"idle", 0) as AtlasTexture).get_image()
		frame.convert(Image.FORMAT_RGBA8)
		var img := frame.get_region(frame.get_used_rect())
		for y in img.get_height():
			for x in img.get_width():
				img.set_pixel(x, y, Color(TINT, img.get_pixel(x, y).a))
		# halve first so the art's stair-stepped edge is averaged away, then enlarge smoothly
		var w := img.get_width()
		var h := img.get_height()
		img.resize(w / 2, h / 2, Image.INTERPOLATE_LANCZOS)
		img.resize(w * SMOOTH, h * SMOOTH, Image.INTERPOLATE_CUBIC)
		_tex = ImageTexture.create_from_image(img)
	return _tex

## Draws the shape on `ci` as tall as `r`, standing at its bottom middle.
static func draw(ci: CanvasItem, r: Rect2) -> void:
	var t := texture()
	var size := t.get_size() * (r.size.y / t.get_height())
	ci.draw_texture_rect(t, Rect2(Vector2(r.get_center().x - size.x / 2.0, r.end.y - size.y), size), false, Color(1, 1, 1, TINT.a))

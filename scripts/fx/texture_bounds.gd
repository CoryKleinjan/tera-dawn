class_name TextureBounds
extends RefCounted
## The painted (not see-through) part of a texture, worked out once and remembered. Reading a
## picture back from the GPU is slow, and a frame of a strip (an AtlasTexture) reads back the
## whole strip, so the first frame asked for reads its strip once and works out every frame of
## the same size along it; the copy is let go straight after.

## Texture, or [atlas, region] -> its used rect.
static var _rects := {}

## The smallest rect holding every pixel of `tex` that isn't fully see-through, in its own
## pixels (the whole texture when it can't be read).
static func used_rect(tex: Texture2D) -> Rect2i:
	var key: Variant = _key(tex)
	if not _rects.has(key):
		if tex is AtlasTexture and (tex as AtlasTexture).atlas:
			_read_strip(tex as AtlasTexture)
		else:
			var img := _image(tex)
			_rects[key] = img.get_used_rect() if img else Rect2i(Vector2i.ZERO, tex.get_size())
	return _rects[key]

static func _key(tex: Texture2D) -> Variant:
	if tex is AtlasTexture and (tex as AtlasTexture).atlas:
		return [(tex as AtlasTexture).atlas, Rect2i((tex as AtlasTexture).region)]
	return tex

## Reads `a`'s atlas once and works out every frame cut like `a` along its row of the strip.
static func _read_strip(a: AtlasTexture) -> void:
	var region := Rect2i(a.region)
	var img := _image(a.atlas)
	if img == null or region.size.x <= 0:
		_rects[_key(a)] = Rect2i(Vector2i.ZERO, a.get_size())
		return
	var x := region.position.x % region.size.x
	while x + region.size.x <= img.get_width():
		var r := Rect2i(Vector2i(x, region.position.y), region.size)
		_rects[[a.atlas, r]] = img.get_region(r).get_used_rect()
		x += region.size.x
	if not _rects.has(_key(a)):  # frames that don't sit on an even grid
		_rects[_key(a)] = img.get_region(region).get_used_rect()

static func _image(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img and img.is_compressed():
		img.decompress()
	return img

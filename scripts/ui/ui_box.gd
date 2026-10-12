class_name TDUiBox
extends StyleBox
## A nine-patch of UI art that is cut finer than it's drawn (UiSkin.density texels per art
## pixel). Its margins, region and the rest are set in art pixels, like the art's own
## numbers in the code, and it's drawn so one art pixel covers one canvas pixel at scale 1,
## the same size as before the art was cut finer. Use it like a StyleBoxTexture: as a theme
## style, with `draw`, or with UiSkin.draw_box at another scale. Copy it with `copy()`.

## The art with its margins in texels.
var inner := StyleBoxTexture.new()
## Texels per art pixel.
var density := 1.0

var texture: Texture2D:
	get: return inner.texture
	set(v): inner.texture = v
var texture_margin_left: float:
	get: return inner.texture_margin_left / density
	set(v): inner.texture_margin_left = v * density
var texture_margin_top: float:
	get: return inner.texture_margin_top / density
	set(v): inner.texture_margin_top = v * density
var texture_margin_right: float:
	get: return inner.texture_margin_right / density
	set(v): inner.texture_margin_right = v * density
var texture_margin_bottom: float:
	get: return inner.texture_margin_bottom / density
	set(v): inner.texture_margin_bottom = v * density
## Part of the art to draw, in art pixels (empty: all of it).
var region_rect: Rect2:
	get: return Rect2(inner.region_rect.position / density, inner.region_rect.size / density)
	set(v): inner.region_rect = Rect2(v.position * density, v.size * density)
var modulate_color: Color:
	get: return inner.modulate_color
	set(v): inner.modulate_color = v
var axis_stretch_horizontal: StyleBoxTexture.AxisStretchMode:
	get: return inner.axis_stretch_horizontal
	set(v): inner.axis_stretch_horizontal = v
var axis_stretch_vertical: StyleBoxTexture.AxisStretchMode:
	get: return inner.axis_stretch_vertical
	set(v): inner.axis_stretch_vertical = v

func _init(art: Texture2D = null, texels_per_pixel := 1.0) -> void:
	inner.texture = art
	density = texels_per_pixel

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	draw_scaled(to_canvas_item, rect, 1.0)

## Draws it into `rect` at `scale` canvas pixels per art pixel.
func draw_scaled(to_canvas_item: RID, rect: Rect2, scale: float) -> void:
	var k := scale / density
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D(0.0, Vector2(k, k), 0.0, rect.position))
	inner.draw(to_canvas_item, Rect2(Vector2.ZERO, rect.size / k))
	RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D())

## A copy that can be changed without changing this one.
func copy() -> TDUiBox:
	var out := TDUiBox.new(null, density)
	out.inner = inner.duplicate() as StyleBoxTexture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		out.set_content_margin(side, get_content_margin(side))
	return out

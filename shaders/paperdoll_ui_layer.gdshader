shader_type canvas_item;
// A layer of the dressed hero in menus (PaperdollView): its colour multiplied in, or with
// `gear` the item colour gear_tint() shades it in.

#include "res://shaders/gear_tint.gdshaderinc"
#include "res://shaders/paperdoll_piece.gdshaderinc"
#include "res://shaders/paperdoll_stride.gdshaderinc"

uniform vec4 tint = vec4(1.0);
uniform bool gear = false;

void fragment() {
	vec3 back, front;
	stride_from(UV, 1.0 / TEXTURE_PIXEL_SIZE, back, front);
	vec4 c = stride_over(texture(TEXTURE, front.xy) * front.z, texture(TEXTURE, back.xy) * back.z);
	c.rgb = gear ? gear_tint(c.rgb, tint.rgb) : c.rgb * tint.rgb;
	COLOR = c * COLOR * vec4(1.0, 1.0, 1.0, tint.a * fist_cut(UV) * hair_cut_at(UV));
}

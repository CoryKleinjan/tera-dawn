shader_type canvas_item;
// A layer of the dressed hero in menus (PaperdollView): its colour multiplied in, or with
// `gear` the item colour gear_tint() shades it in.

#include "res://shaders/gear_tint.gdshaderinc"

uniform vec4 tint = vec4(1.0);
uniform bool gear = false;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = gear ? gear_tint(c.rgb, tint.rgb) : c.rgb * tint.rgb;
	COLOR = c * COLOR * vec4(1.0, 1.0, 1.0, tint.a);
}

shader_type canvas_item;
// The dressed hero in menus (the character creator, the equipment window).

#include "res://shaders/paperdoll.gdshaderinc"
#include "res://shaders/paperdoll_stride.gdshaderinc"

// The draw's own colour (COLOR in fragment() already has the texture multiplied in).
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec3 back, front;
	stride_from(UV, 1.0 / TEXTURE_PIXEL_SIZE, back, front);
	COLOR = stride_over(dress(texture(TEXTURE, front.xy), front.xy) * front.z,
			dress(texture(TEXTURE, back.xy), back.xy) * back.z) * tint;
}

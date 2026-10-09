shader_type canvas_item;
// The dressed hero in menus (the character creator, the equipment window).

#include "res://shaders/paperdoll.gdshaderinc"

// The draw's own colour (COLOR in fragment() already has the texture multiplied in).
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = dress(texture(TEXTURE, UV), UV) * tint;
}

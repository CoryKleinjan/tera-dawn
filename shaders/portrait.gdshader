shader_type canvas_item;
// A menu's hero (PaperdollView): the picture of him its own little 3D stage renders, colour
// graded like the map (grade.gdshaderinc), as the finishing pass grades him in game. The
// picture's soft edges were blended over a clear background, so it's premultiplied.
render_mode blend_premul_alpha;

#include "res://shaders/grade.gdshaderinc"

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 straight = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
	COLOR = vec4(grade(straight) * c.a, c.a);
}

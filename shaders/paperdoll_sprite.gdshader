shader_type spatial;
// The dressed hero standing in the 3D stage: like a shaded, alpha-cut Sprite3D.
render_mode cull_disabled, specular_disabled;

#define LINEAR_COLOR
#include "res://shaders/paperdoll.gdshaderinc"

uniform sampler2D strip : source_color, filter_nearest;

void fragment() {
	vec4 c = dress(texture(strip, UV), UV) * COLOR;
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}

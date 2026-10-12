shader_type spatial;
// The dressed hero standing in the 3D stage: like a shaded, soft-edged, smoothly filtered
// Sprite3D (TDStage.style_sprite), drawn as paperdoll_stage.gdshaderinc says.
render_mode cull_disabled, specular_disabled, depth_prepass_alpha;

#define LINEAR_COLOR
#include "res://shaders/paperdoll.gdshaderinc"
#include "res://shaders/paperdoll_stage.gdshaderinc"

uniform sampler2D strip : source_color, filter_linear_mipmap;

void fragment() {
	vec4 c = dress(strip_texel(strip, UV), UV) * COLOR;
	ALPHA = c.a;
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}

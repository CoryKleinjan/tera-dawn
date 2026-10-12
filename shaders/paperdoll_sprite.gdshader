shader_type spatial;
// The dressed hero standing in the 3D stage: like a shaded, soft-edged, smoothly filtered
// Sprite3D (TDStage.style_sprite), drawn as paperdoll_stage.gdshaderinc says.
render_mode cull_disabled, specular_disabled, depth_prepass_alpha;

#include "res://shaders/paperdoll.gdshaderinc"
#include "res://shaders/paperdoll_stage.gdshaderinc"
#include "res://shaders/paperdoll_stride.gdshaderinc"

uniform sampler2D strip : source_color, filter_linear_mipmap;

void fragment() {
	vec3 back, front;
	stride_from(UV, vec2(textureSize(strip, 0)), back, front);
	vec4 c = stride_over(dress(strip_texel(strip, front.xy), front.xy) * front.z,
			dress(strip_texel(strip, back.xy), back.xy) * back.z) * COLOR;
	ALPHA = c.a;
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
}

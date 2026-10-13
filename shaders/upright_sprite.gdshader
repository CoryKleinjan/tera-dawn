shader_type spatial;
render_mode skip_vertex_transform, depth_prepass_alpha, cull_disabled;
// A sprite piece (a ladder or rope piece) whose sides stay straight up and down on screen
// (see upright.gdshaderinc), drawn like TDStage's sprites: soft painted edges, lit.

#include "res://shaders/upright.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform bool flip_h = false;
// How far right (3D units) the bottom edge is drawn from the top edge: a vine's stem leaves a
// piece a little off from where it enters, so the piece leans to meet the next one.
uniform float slant = 0.0;

void vertex() {
	VERTEX.x += slant * UV.y;
	if (flip_h) {
		UV.x = 1.0 - UV.x;
	}
	upright_vertex(VERTEX, NORMAL, MODELVIEW_MATRIX);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 1.0;
}

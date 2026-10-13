shader_type spatial;
render_mode skip_vertex_transform, alpha_to_coverage;
// A tall land wall (a raised level's wall and its end outline) whose sides stay straight up
// and down on screen. The camera looks down a little, so in plain perspective a tall wall's
// sides lean in toward the middle of the screen; each corner here is moved sideways to sit
// right under the top corner above it. Otherwise it draws like the land's other strips
// (TerrainBuilder._strip): a repeating texture, cut out where see-through, fully rough.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// The quad's top edge, in its own space.
uniform float top = 0.5;

void vertex() {
	UV = UV * uv_scale + uv_offset;
	vec3 v = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 t = (MODELVIEW_MATRIX * vec4(VERTEX.x, top, VERTEX.z, 1.0)).xyz;
	v.x = t.x * v.z / t.z;
	VERTEX = v;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
	ROUGHNESS = 1.0;
}

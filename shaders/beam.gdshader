shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Soft vertical pillar of light (level up).

uniform vec4 color : source_color = vec4(1.0, 0.82, 0.4, 1.0);
uniform float fade = 1.0;
uniform float energy = 2.0;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float body = smoothstep(1.0, 0.0, x) * smoothstep(0.0, 0.7, UV.y);
	float stripes = 0.75 + 0.25 * sin(UV.y * 30.0 + TIME * 8.0);
	ALBEDO = color.rgb * energy;
	ALPHA = body * stripes * fade;
}

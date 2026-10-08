shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// Swirling oval portal. HDR colors so it blooms.

uniform vec4 ring_color : source_color = vec4(0.67, 0.55, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.82, 0.4, 1.0);
uniform float energy = 2.5;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, 2.0);
	float r = length(p * vec2(1.0, 0.55));
	float a = atan(p.y, p.x);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 - TIME * 3.0 + r * 10.0);
	float ring = smoothstep(0.62, 0.5, r) * smoothstep(0.3, 0.5, r);
	float core = smoothstep(0.5, 0.0, r);
	vec3 c = ring_color.rgb * ring * (0.6 + swirl * 0.8) + core_color.rgb * core * (0.35 + 0.15 * sin(TIME * 2.0));
	ALBEDO = c * energy;
	ALPHA = clamp(ring + core * 0.6, 0.0, 1.0);
}

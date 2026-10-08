shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
// A crescent sword trail. progress runs 0 to 1 over the effect's life.

uniform float progress = 0.0;
uniform float face = 1.0;
uniform vec4 color_a : source_color = vec4(1.0, 0.82, 0.4, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.48, 0.35, 1.0);
uniform float energy = 2.2;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= face;
	p.y = -p.y;
	vec2 c = vec2(-0.7 + progress * 0.5, 0.0);
	vec2 d = p - c;
	float r = length(d);
	float a = abs(atan(d.y, d.x));
	float width = mix(0.09, 0.03, progress);
	float arc = smoothstep(width, 0.0, abs(r - 1.05)) * smoothstep(1.25, 0.4, a);
	float inner = smoothstep(width * 3.0, 0.0, abs(r - 0.9)) * smoothstep(1.1, 0.3, a) * 0.25;
	vec3 col = mix(color_b.rgb, color_a.rgb, arc);
	ALBEDO = col * energy;
	ALPHA = clamp((arc + inner) * (1.0 - progress), 0.0, 1.0);
}

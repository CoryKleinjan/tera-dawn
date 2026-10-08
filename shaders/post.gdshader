shader_type canvas_item;
// Screen-space finishing pass: tilt-shift blur toward the top and bottom edges, a vignette and a light grade.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float blur_top = 0.2;
uniform float blur_bottom = 0.16;
uniform float blur_strength = 2.6;
uniform float vignette = 0.55;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	float b = max(smoothstep(blur_top, 0.0, uv.y), smoothstep(1.0 - blur_bottom, 1.0, uv.y));
	vec3 c = textureLod(screen, uv, b * blur_strength).rgb;
	vec2 v = (uv - 0.5) * vec2(1.0, 0.75);
	c *= 1.0 - vignette * smoothstep(0.2, 0.75, length(v) * 1.2);
	COLOR = vec4(c * tint.rgb, 1.0);
}

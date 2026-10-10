shader_type canvas_item;
// Screen-space finishing pass: a light tilt-shift blur on the very top and bottom edges (the
// depth of field does the real work, so gameplay up high stays sharp), a vignette, the map's
// colour grade (BiomeDef "Atmosphere") and a fade to dark for map changes.

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float blur_top = 0.06;
uniform float blur_bottom = 0.05;
uniform float blur_strength = 1.6;
uniform float vignette = 0.5;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Colour grade: shadows are pushed toward `lift`, everything is multiplied by `tint`.
uniform vec4 lift : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float lift_amount = 0.0;
uniform float saturation = 1.0;
// 0 shows the scene, 1 is fully faded to `fade_color` (TDStage.fade).
uniform float fade = 0.0;
uniform vec4 fade_color : source_color = vec4(0.06, 0.04, 0.1, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	float b = max(smoothstep(blur_top, 0.0, uv.y), smoothstep(1.0 - blur_bottom, 1.0, uv.y));
	vec3 c = textureLod(screen, uv, b * blur_strength).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	c = mix(c, c + lift.rgb * 0.25, lift_amount * (1.0 - smoothstep(0.0, 0.6, luma)));
	vec2 v = (uv - 0.5) * vec2(1.0, 0.75);
	c *= 1.0 - vignette * smoothstep(0.2, 0.75, length(v) * 1.2);
	c *= tint.rgb;
	COLOR = vec4(mix(c, fade_color.rgb, fade), 1.0);
}

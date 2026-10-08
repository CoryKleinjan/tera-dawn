shader_type sky;
// Painted gradient sky with a low sun. The camera never rotates, so EYEDIR.y maps to screen height.

uniform vec3 top_color : source_color;
uniform vec3 mid_color : source_color;
uniform vec3 low_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 sun_color : source_color;
uniform vec3 sun_dir = vec3(0.3, -0.05, -1.0);
uniform float sun_size = 0.05;

void sky() {
	float y = EYEDIR.y;
	vec3 c = mix(horizon_color, low_color, smoothstep(-0.32, -0.12, y));
	c = mix(c, mid_color, smoothstep(-0.14, 0.0, y));
	c = mix(c, top_color, smoothstep(-0.02, 0.14, y));
	float d = distance(EYEDIR, normalize(sun_dir));
	c += sun_color * (smoothstep(sun_size, sun_size * 0.85, d) * 2.6 + exp(-d * 7.0) * 0.55 + exp(-d * 2.2) * 0.15);
	COLOR = c;
}

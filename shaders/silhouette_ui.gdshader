shader_type canvas_item;
// A flat-coloured cut-out of whatever is drawn: its shape in `tint`, with the edge
// softened over `soften` texels so a small sprite drawn big keeps a smooth outline.
uniform vec4 tint : source_color = vec4(1.0);
uniform float soften = 1.5;

void fragment() {
	float a = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			a += texture(TEXTURE, UV + vec2(float(x), float(y)) * 0.5 * soften * TEXTURE_PIXEL_SIZE).a;
		}
	}
	COLOR = vec4(tint.rgb, smoothstep(0.25, 0.75, a / 25.0) * tint.a);
}

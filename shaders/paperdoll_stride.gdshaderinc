// The passing step of the hero's walk (Paperdoll.PASSING_STEPS). Every walk frame in the art is
// drawn mid-stride with his feet apart, so on the frames where his arms swing past his body
// his lower legs slide in toward each other instead: below `top` each row of the back leg
// (left of `split`, he faces right in the strip) moves right and each row of the front leg
// moves left, more the lower it is, up to `shift` at his feet. His body and every strip layer
// (clothes, shoes, capes) do the same, so they stay lined up.
//
//   vec3 back, front;
//   stride_from(UV, strip_size, back, front);
//   c = stride_over(colour_at(front.xy) * front.z, colour_at(back.xy) * back.z);
//
// Off a passing step `back` is `UV` itself and `front` shows nothing. Both are always sampled
// (not in a branch) so the GPU picks mipmaps from smooth coordinates.

// Per passing step: (strip frame, split x, top y, shift), in frame pixels. Paperdoll sets them.
uniform vec4 stride_steps[4];
uniform int stride_count = 0;
uniform vec2 stride_frame = vec2(256.0, 208.0);

// Where the back and front leg's pixels shown at strip coordinate `uv` come from (xy), and
// how much that leg reaches there (z, 0 to 1, soft over a pixel at the split). The
// coordinates themselves don't jump at the split.
void stride_from(vec2 uv, vec2 strip_size, out vec3 back, out vec3 front) {
	back = vec3(uv, 1.0);
	front = vec3(uv, 0.0);
	vec2 p = uv * strip_size;
	float f = floor(p.x / stride_frame.x);
	for (int i = 0; i < stride_count; i++) {
		vec4 s = stride_steps[i];
		if (s.x != f || p.y <= s.z) {
			continue;
		}
		float d = s.w * clamp((p.y - s.z) / (stride_frame.y - s.z), 0.0, 1.0);
		float x = p.x - f * stride_frame.x;
		back = vec3((p - vec2(d, 0.0)) / strip_size, clamp(s.y - (x - d) + 0.5, 0.0, 1.0));
		front = vec3((p + vec2(d, 0.0)) / strip_size, clamp(x + d - s.y + 0.5, 0.0, 1.0));
		return;
	}
}

// The front leg's colour over the back leg's (both straight, not premultiplied).
vec4 stride_over(vec4 front, vec4 back) {
	float a = front.a + back.a * (1.0 - front.a);
	vec3 rgb = (front.rgb * front.a + back.rgb * back.a * (1.0 - front.a)) / max(a, 1e-4);
	return vec4(rgb, a);
}

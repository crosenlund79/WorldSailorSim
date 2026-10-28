shader_type canvas_item;
// I024: a locked achievement's badge on the laptop: greyed and dimmed (a
// padlock is drawn over it too, so it reads as locked without colour).

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.30, 0.59, 0.11));
	COLOR = vec4(vec3(g * 0.62 + 0.10), c.a * 0.72);
}

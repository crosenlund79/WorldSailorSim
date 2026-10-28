shader_type canvas_item;
// The sea around the boat (Operation Real Horizon): an illustrated, 2D sea
// surface. Layered value noise in the deck's own coordinates (scene units,
// the bow is +x): slow depth/tone variation, a swell and a chop that both run
// with the wind (`wind_dir`, where the wind blows to), shaded as if lit from
// the upper left, whitecaps and wind streaks from about 20 kn, and small sun
// glints in clear daylight. `flow` moves the pattern aft as the boat makes
// way. Cheap: a few noise lookups per pixel, no textures.

uniform vec4 deep_colour : source_color = vec4(0.161, 0.275, 0.325, 1.0);
uniform vec4 base_colour : source_color = vec4(0.322, 0.471, 0.529, 1.0);
uniform vec4 light_colour : source_color = vec4(0.663, 0.761, 0.776, 1.0);
uniform vec4 shadow_colour : source_color = vec4(0.114, 0.2, 0.235, 1.0);
uniform vec4 foam_colour : source_color = vec4(0.902, 0.925, 0.918, 1.0);
uniform vec2 wind_dir = vec2(1.0, 0.0);
// 0 glassy calm .. 1 gale (sea state from the wind).
uniform float sea_state = 0.3;
// 0 open sea .. 1 sheltered harbour (shorter, smaller waves).
uniform float shelter = 0.0;
// 0 .. 1 sun glints (clear daylight).
uniform float sun = 1.0;
// 0 .. 1 rain dimpling the surface.
uniform float rain = 0.0;
uniform vec2 flow = vec2(0.0);
uniform float sea_time = 0.0;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = world - flow;
	vec2 along = normalize(wind_dir + vec2(1e-4, 0.0));
	vec2 across = vec2(-along.y, along.x);
	float u = dot(p, along);
	float v = dot(p, across);
	float s = clamp(sea_state, 0.0, 1.0);
	float calm = 1.0 - smoothstep(0.0, 0.25, s);

	// Slow tone variation: depth, wind patches, light on the swell.
	float tone = fbm(world * 0.0011 + vec2(sea_time * 0.004, 0.0));
	float patches = fbm(vec2(u * 0.0016, v * 0.0028) - along * sea_time * 0.02);
	vec3 col = mix(base_colour.rgb, deep_colour.rgb, clamp((0.62 - tone) * 1.4, 0.0, 1.0) * 0.6);

	// Swell: long crests across the wind, broken along their length.
	float swell_len = mix(520.0, 1100.0, s) * mix(1.0, 0.45, shelter);
	float bend = fbm(vec2(v * 0.0019, u * 0.0011)) * 6.0;
	float phase = u / swell_len * 6.2832 + bend - sea_time * mix(0.35, 0.8, s);
	float swell = sin(phase);
	float swell_slope = cos(phase);
	float swell_amp = mix(0.10, 0.55, s) * (1.0 - shelter * 0.6);

	// Chop: short wind waves, elongated across the wind.
	float chop_scale = mix(0.022, 0.012, s) * mix(1.0, 1.6, shelter);
	vec2 cp = vec2(u * chop_scale * 1.0, v * chop_scale * 0.45) - vec2(sea_time * mix(0.25, 1.1, s), 0.0);
	float chop = fbm(cp);
	float chop_d = fbm(cp + vec2(0.07, 0.0)) - chop;
	float chop_amp = mix(0.12, 0.65, s) * (1.0 - calm * 0.75);

	// Light from the upper left: faces towards it are brighter (sky), the
	// lee faces darker.
	vec2 light_dir = normalize(vec2(-0.6, -0.8));
	float facing = dot(along, light_dir);
	float slope = swell_slope * swell_amp * facing + chop_d * 9.0 * chop_amp;
	col = mix(col, light_colour.rgb, clamp(slope, 0.0, 1.0) * 0.55);
	col = mix(col, shadow_colour.rgb, clamp(-slope, 0.0, 1.0) * 0.6);
	col = mix(col, shadow_colour.rgb, (1.0 - patches) * 0.18 * (0.4 + s));

	// Glassy calm: broad soft reflections of the sky.
	float sheen = fbm(world * 0.0024 + vec2(0.0, sea_time * 0.01));
	col = mix(col, light_colour.rgb, calm * smoothstep(0.55, 0.85, sheen) * 0.28);

	// Whitecaps and streaks from about 20 kn.
	float white = smoothstep(0.55, 0.95, s);
	if (white > 0.0) {
		// Breaking crests: ragged foam on the swell's crest line, broken up
		// by fine noise; long thin streaks of old foam down the wind.
		float lace = fbm(vec2(u * 0.03, v * 0.018) + vec2(sea_time * 0.2, 0.0));
		float crest = smoothstep(0.9, 0.995, swell + (chop - 0.5) * 0.25) * smoothstep(0.5, 0.72, lace);
		float streak = smoothstep(0.74, 0.86, noise(vec2(u * 0.0025, v * 0.11))) * smoothstep(0.4, 0.7, lace);
		col = mix(col, foam_colour.rgb, clamp(crest * 0.8 + streak * 0.22, 0.0, 1.0) * white);
	}

	// Sun glints on the chop.
	float glint = smoothstep(0.86, 0.97, noise(world * 0.09 + vec2(sea_time * 0.6, -sea_time * 0.3))) * smoothstep(0.45, 0.7, chop);
	col = mix(col, vec3(1.0, 0.99, 0.95), glint * sun * 0.55 * (1.0 - s * 0.6));

	// Rain: fine dimpling and a grey sheen.
	if (rain > 0.0) {
		float dimple = smoothstep(0.9, 1.0, noise(world * 0.14 + vec2(sea_time * 7.0, sea_time * 3.0)));
		col = mix(col, light_colour.rgb * 0.9, rain * (0.12 + dimple * 0.35));
	}
	COLOR = vec4(col, 1.0);
}

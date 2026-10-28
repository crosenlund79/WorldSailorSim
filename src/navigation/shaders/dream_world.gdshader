shader_type canvas_item;
// The Dreamer's Map's illustrated look (after 0.105b): reads the chart as it
// has been drawn (land fill, islets, coast lines, water) and recolours it by
// position - soft green land, snow and ice in the far north and Antarctica,
// sandy brown in the great deserts, a deeper blue sea. Presentation only: the
// geometry, navigation and the working chart are untouched.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 rect_origin;            // this rect's top-left, in map units
uniform float scale = 160.0;         // map units per degree (MapProjection.scale)
uniform vec4 land_src : source_color;
uniform vec4 islet_src : source_color;
uniform vec4 coast_src : source_color;
uniform vec4 water_src : source_color;
uniform vec4 green : source_color = vec4(0.44, 0.50, 0.39, 1.0);
uniform vec4 green_dark : source_color = vec4(0.35, 0.42, 0.32, 1.0);
uniform vec4 snow : source_color = vec4(0.86, 0.88, 0.89, 1.0);
uniform vec4 sand : source_color = vec4(0.66, 0.60, 0.48, 1.0);
uniform vec4 coast_green : source_color = vec4(0.25, 0.36, 0.24, 1.0);
uniform vec4 coast_sand : source_color = vec4(0.52, 0.42, 0.28, 1.0);
uniform vec4 coast_snow : source_color = vec4(0.62, 0.66, 0.70, 1.0);
uniform vec4 deep_sea : source_color = vec4(0.12, 0.21, 0.26, 1.0);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// A soft ellipse: 1 inside, fading to 0 over `soft` of its radius.
float blob(vec2 geo, vec2 centre, vec2 radius, float soft) {
	vec2 d = (geo - centre) / radius;
	return 1.0 - smoothstep(1.0 - soft, 1.0 + soft, length(d));
}

float desert(vec2 g) {
	float d = 0.0;
	d = max(d, blob(g, vec2(10.0, 23.0), vec2(24.0, 8.5), 0.45));   // Sahara
	d = max(d, blob(g, vec2(47.0, 22.0), vec2(10.5, 7.5), 0.45));   // Arabian Peninsula
	d = max(d, blob(g, vec2(130.0, -25.0), vec2(14.0, 6.5), 0.5));  // central Australian deserts
	d = max(d, blob(g, vec2(105.0, 43.0), vec2(12.0, 4.0), 0.55));  // Gobi
	d = max(d, blob(g, vec2(-69.8, -23.5), vec2(2.2, 6.0), 0.5));   // Atacama
	// A ragged edge rather than a perfect oval.
	return clamp(d * (0.85 + 0.3 * noise(g * 0.9)), 0.0, 1.0);
}

float ice(vec2 g) {
	float north = smoothstep(64.0, 70.0, g.y);
	float greenland = blob(g, vec2(-41.0, 73.0), vec2(22.0, 13.0), 0.2);
	float antarctic = 1.0 - smoothstep(-62.0, -58.0, g.y);
	return clamp(max(max(north, greenland), antarctic), 0.0, 1.0);
}

float match(vec3 c, vec3 ref) {
	return 1.0 - smoothstep(0.04, 0.13, distance(c, ref));
}

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	vec2 m = rect_origin + local_pos;
	float lon = mod(m.x / scale + 180.0, 360.0) - 180.0;
	float lat = degrees(2.0 * atan(exp(radians(-m.y / scale))) - PI / 2.0);
	vec2 g = vec2(lon, lat);
	float n = noise(g * 0.35) * 0.6 + noise(g * 1.3) * 0.4;
	vec3 land = mix(green.rgb, green_dark.rgb, n);
	float dry = desert(g);
	float cold = ice(g);
	land = mix(land, sand.rgb * (0.95 + 0.1 * n), dry);
	land = mix(land, snow.rgb, cold);
	vec3 coast = mix(mix(coast_green.rgb, coast_sand.rgb, dry), coast_snow.rgb, cold);
	vec3 sea = deep_sea.rgb * (0.94 + 0.08 * n);
	float is_land = max(match(c.rgb, land_src.rgb), match(c.rgb, islet_src.rgb));
	float is_coast = match(c.rgb, coast_src.rgb);
	float is_water = match(c.rgb, water_src.rgb);
	vec3 out_rgb = c.rgb;
	out_rgb = mix(out_rgb, sea, is_water);
	out_rgb = mix(out_rgb, coast, is_coast);
	out_rgb = mix(out_rgb, land, is_land);
	COLOR = vec4(out_rgb, 1.0);
}

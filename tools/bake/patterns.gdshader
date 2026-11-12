shader_type canvas_item;
// Procedural texture patterns, rendered once by tools/bake_textures.gd and
// saved as PNG files in assets/textures/.
//
// Tiling patterns output "detail" maps: R = brightness, G = random value per
// element (brick, plank, shingle...), B = height. A second pass (mode 1)
// turns the height into a normal map. Sprites (mode 2) output RGBA.
// uv.y points UP in the world when these textures are used.

uniform int pattern = 0;
uniform int mode = 0;
uniform float normal_strength = 3.0;

float hash11(float n) {
	return fract(sin(n * 127.1 + 3.7) * 43758.5453);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21) + 0.17);
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n * 31.7 + 5.1));
}

// Value noise that repeats every `period` cells.
float pnoise(vec2 p, vec2 period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(mod(i, period));
	float b = hash21(mod(i + vec2(1.0, 0.0), period));
	float c = hash21(mod(i + vec2(0.0, 1.0), period));
	float d = hash21(mod(i + vec2(1.0, 1.0), period));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 uv, vec2 freq, int octaves) {
	float total = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int o = 0; o < octaves; o++) {
		total += amp * pnoise(uv * freq + float(o) * 17.0, freq);
		norm += amp;
		amp *= 0.5;
		freq *= 2.0;
	}
	return total / norm;
}

// Repeating cell noise. Returns (distance to nearest point, distance to the
// second nearest, random id of the nearest cell).
vec3 pvoronoi(vec2 p, vec2 period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 cell = mod(i + g, period);
			vec2 r = g + hash22(cell) * 0.9 + 0.05 - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = hash21(cell + 7.7);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// 0: irregular stone blocks in courses.
vec4 stone_wall(vec2 uv) {
	float rows = 5.0;
	float nb = 3.0;
	float y = (uv.y + (fbm(uv, vec2(3.0), 2) - 0.5) * 0.045) * rows;
	float row = mod(floor(y), rows);
	float fy = fract(y);
	float x = uv.x * nb + hash11(row * 3.1) + 0.4 * pnoise(vec2(uv.x * 4.0, row + 0.5), vec2(4.0, rows));
	float cell = mod(floor(x), nb);
	float fx = fract(x);
	float id = hash21(vec2(cell, row) + 3.3);
	float d = min(min(fx, 1.0 - fx) / nb, min(fy, 1.0 - fy) / rows);
	d += (fbm(uv, vec2(14.0), 3) - 0.5) * 0.016;
	float body = smoothstep(0.006, 0.04, d);
	float grain = fbm(uv, vec2(10.0), 5);
	float chips = smoothstep(0.62, 0.75, fbm(uv, vec2(7.0), 3));
	float h = body * (0.6 + 0.2 * id + 0.25 * grain - 0.12 * chips);
	float lum = mix(0.38, 0.72 + 0.3 * grain - 0.1 * chips, body);
	return vec4(lum, id, h, 1.0);
}

// 1: cracked rock for cliffs and boulders.
vec4 rock(vec2 uv) {
	vec2 warp = vec2(fbm(uv, vec2(4.0), 3), fbm(uv + 0.37, vec2(4.0), 3)) - 0.5;
	vec3 v = pvoronoi((uv + warp * 0.12) * 5.0, vec2(5.0));
	vec3 v2 = pvoronoi((uv + warp * 0.05) * 11.0, vec2(11.0));
	float crack = smoothstep(0.0, 0.14, v.y - v.x);
	float crack2 = smoothstep(0.0, 0.1, v2.y - v2.x);
	float grain = fbm(uv, vec2(12.0), 5);
	float h = crack * (0.55 + 0.25 * v.z) + 0.12 * crack2 + 0.2 * grain;
	float lum = (0.55 + 0.3 * grain) * mix(0.55, 1.0, crack) * mix(0.85, 1.0, crack2);
	return vec4(lum, v.z, h, 1.0);
}

// 2: wooden planks running along v, with grain and knots.
vec4 planks(vec2 uv) {
	float nb = 5.0;
	float x = uv.x * nb;
	float cell = mod(floor(x), nb);
	float fx = fract(x);
	float id = hash11(cell * 5.3 + 1.0);
	float y = uv.y + id * 3.7;
	float joint = abs(fract(y * 1.0 + id) - 0.5);
	float grain = fbm(vec2(uv.x + id * 0.31, y), vec2(40.0, 3.0), 4);
	float rings = 0.5 + 0.5 * sin((uv.x * nb + grain * 1.6) * 14.0 + id * 20.0);
	vec3 knot = pvoronoi(vec2(uv.x * nb, uv.y * 2.0 + id * 9.0), vec2(nb, 2.0));
	float knots = smoothstep(0.16, 0.05, knot.x) * step(0.75, knot.z);
	float gap = smoothstep(0.0, 0.06, min(fx, 1.0 - fx)) * smoothstep(0.0, 0.012, joint);
	float h = gap * (0.65 + 0.2 * grain + 0.1 * rings - 0.25 * knots) * (0.9 + 0.1 * sin(fx * 3.14159));
	float lum = mix(0.3, 0.68 + 0.22 * grain + 0.1 * rings - 0.3 * knots, gap);
	return vec4(lum, id, h, 1.0);
}

float shingle_height(float fx, float fy, float id) {
	float side = smoothstep(0.0, 0.08, min(fx, 1.0 - fx));
	return (0.35 + 0.6 * (1.0 - fy) + 0.08 * id) * mix(0.75, 1.0, side);
}

// 3: overlapping roof shingles with rounded lower edges.
vec4 shingles(vec2 uv) {
	float rows = 6.0;
	float nb = 5.0;
	float y = uv.y * rows;
	float row = floor(y);
	float fy = fract(y);
	float x = uv.x * nb + mod(row, 2.0) * 0.5 + 0.18 * hash11(mod(row, rows) * 2.3);
	float cell = floor(x);
	float fx = fract(x);
	float id = hash21(vec2(mod(cell, nb), mod(row, rows)));
	// The rounded bottom of this shingle; below it the row underneath shows.
	float curve = 0.34 * pow(abs(fx * 2.0 - 1.0), 2.4) + 0.05 * id;
	float grain = fbm(uv, vec2(30.0, 6.0), 4);
	float h;
	float lum;
	if (fy < curve) {
		float row2 = row - 1.0;
		float x2 = uv.x * nb + mod(row2, 2.0) * 0.5 + 0.18 * hash11(mod(row2, rows) * 2.3);
		float id2 = hash21(vec2(mod(floor(x2), nb), mod(row2, rows)));
		h = shingle_height(fract(x2), 1.0 + fy, id2) - 0.25;
		id = id2;
		lum = 0.42 + 0.2 * grain;
	} else {
		h = shingle_height(fx, fy, id);
		float lip = smoothstep(curve, curve + 0.12, fy);
		lum = (0.62 + 0.3 * grain) * mix(0.8, 1.0, lip) * mix(0.82, 1.0, smoothstep(0.0, 0.06, min(fx, 1.0 - fx)));
	}
	h += 0.1 * grain;
	return vec4(lum, id, clamp(h, 0.0, 1.0), 1.0);
}

// 4: lumpy lime plaster with worn patches and hairline cracks.
vec4 plaster(vec2 uv) {
	float broad = fbm(uv, vec2(3.0), 4);
	float fine = fbm(uv, vec2(18.0), 4);
	float strokes = fbm(uv, vec2(5.0, 22.0), 3);
	float worn = smoothstep(0.6, 0.78, fbm(uv + 0.5, vec2(2.0), 4));
	vec3 v = pvoronoi(uv * 4.0 + (fine - 0.5) * 0.4, vec2(4.0));
	float crack = 1.0 - smoothstep(0.0, 0.025, v.y - v.x) * 1.0;
	crack *= smoothstep(0.45, 0.6, broad);
	float h = 0.55 + 0.2 * broad + 0.12 * strokes + 0.08 * fine - 0.22 * worn - 0.25 * crack;
	float lum = 0.8 + 0.12 * broad + 0.08 * fine - 0.1 * worn - 0.3 * crack;
	return vec4(lum, worn, h, 1.0);
}

// 5: deeply furrowed tree bark.
vec4 bark(vec2 uv) {
	vec2 warp = vec2(fbm(uv, vec2(6.0, 2.0), 3) - 0.5, 0.0);
	vec3 v = pvoronoi((uv + warp * 0.1) * vec2(9.0, 2.0), vec2(9.0, 2.0));
	float ridge = smoothstep(0.0, 0.22, v.y - v.x);
	float grain = fbm(uv, vec2(36.0, 5.0), 4);
	float h = ridge * (0.6 + 0.3 * v.z) + 0.2 * grain;
	float lum = (0.5 + 0.35 * grain) * mix(0.4, 1.0, ridge);
	return vec4(lum, v.z, h, 1.0);
}

// 6: layered straw thatch.
vec4 thatch(vec2 uv) {
	float layers = 3.0;
	float edge = fbm(uv, vec2(24.0, 1.0), 2) * 0.35;
	float y = uv.y * layers + edge;
	float fy = fract(y);
	float fibres = fbm(uv, vec2(90.0, 3.0), 3);
	float fibres2 = pnoise(uv * vec2(160.0, 2.0), vec2(160.0, 2.0));
	float h = 0.3 + 0.55 * (1.0 - fy) + 0.25 * fibres;
	h *= mix(0.6, 1.0, smoothstep(0.0, 0.08, fy));
	float lum = (0.55 + 0.3 * fibres + 0.15 * fibres2) * mix(0.55, 1.0, smoothstep(0.0, 0.25, fy));
	return vec4(lum, fibres2, h, 1.0);
}

// 7: grassy ground seen from above (the base under the 3D grass blades).
vec4 ground(vec2 uv) {
	float blotch = fbm(uv, vec2(4.0), 4);
	float tufts = fbm(uv, vec2(26.0), 4);
	vec3 v = pvoronoi(uv * 22.0, vec2(22.0));
	float blades = smoothstep(0.5, 0.0, v.x);
	float h = 0.4 + 0.3 * tufts + 0.3 * blades;
	float lum = 0.62 + 0.2 * blotch + 0.18 * tufts * blades;
	return vec4(lum, blotch, h, 1.0);
}

// 8: packed dirt with pebbles.
vec4 dirt(vec2 uv) {
	float broad = fbm(uv, vec2(4.0), 5);
	float fine = fbm(uv, vec2(30.0), 3);
	vec3 v = pvoronoi(uv * 14.0, vec2(14.0));
	float pebble = smoothstep(0.3, 0.1, v.x) * step(0.86, v.z);
	float h = 0.35 + 0.25 * broad + 0.12 * fine + 0.45 * pebble;
	float lum = 0.62 + 0.22 * broad + 0.1 * fine + 0.14 * pebble;
	return vec4(lum, mix(broad, v.z, pebble), h, 1.0);
}

// 9: reptile scales for the creature's hide.
vec4 hide(vec2 uv) {
	vec2 warp = vec2(fbm(uv, vec2(5.0), 2), fbm(uv + 0.4, vec2(5.0), 2)) - 0.5;
	vec3 v = pvoronoi((uv + warp * 0.05) * 9.0, vec2(9.0));
	float edge = v.y - v.x;
	float dome = smoothstep(0.0, 0.2, edge) * (1.0 - 0.45 * v.x);
	float fine = fbm(uv, vec2(40.0), 3);
	float h = dome * (0.7 + 0.3 * v.z) + 0.08 * fine;
	float lum = (0.62 + 0.25 * v.z + 0.1 * fine) * mix(0.45, 1.0, smoothstep(0.0, 0.12, edge));
	return vec4(lum, v.z, h, 1.0);
}

// 10: three independent repeating noises, for large-scale colour variation.
vec4 noise_pack(vec2 uv) {
	return vec4(fbm(uv, vec2(4.0), 6), fbm(uv + 0.31, vec2(7.0), 5), fbm(uv + 0.67, vec2(16.0), 4), 1.0);
}

// 11: a bunch of leaves on a transparent background.
vec4 leaf_cluster(vec2 uv) {
	vec4 result = vec4(0.0);
	for (int k = 0; k < 90; k++) {
		float fk = float(k);
		float ang = fk * 2.39996 + hash11(fk) * 0.6;
		float rad = 0.03 + 0.38 * sqrt((fk + 0.5) / 90.0);
		vec2 c = vec2(0.5) + vec2(cos(ang), sin(ang)) * rad;
		float rot = ang + (hash11(fk + 40.0) - 0.5) * 1.8;
		float len = 0.055 + 0.03 * hash11(fk + 80.0);
		vec2 d = uv - c;
		float l = (d.x * cos(rot) + d.y * sin(rot)) / len;
		float w = (-d.x * sin(rot) + d.y * cos(rot)) / len;
		float width = 0.46 * pow(max(1.0 - l * l, 0.0), 0.75) * (1.0 - 0.25 * l);
		float inside = smoothstep(0.0, 0.035, width - abs(w));
		if (abs(l) < 1.0 && inside > 0.0) {
			float rib = smoothstep(0.0, 0.05, abs(w));
			float veins = 0.5 + 0.5 * sin((l * 9.0 - abs(w) * 14.0));
			float lum = (0.58 + 0.34 * (l * 0.5 + 0.5)) * mix(0.72, 1.0, rib) * (0.92 + 0.08 * veins);
			lum *= 0.72 + 0.28 * hash11(fk + 120.0);
			vec4 leaf = vec4(lum, hash11(fk + 160.0), 0.0, inside);
			result = mix(result, leaf, step(result.a, inside));
		}
	}
	return result;
}

// 12: a single upright flame.
vec4 flame(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	float t = p.y * 0.5 + 0.5;
	float n = fbm(uv, vec2(4.0, 3.0), 4);
	float n2 = fbm(uv + 0.5, vec2(6.0, 4.0), 3);
	p.x += (n - 0.5) * 0.7 * t;
	float r = length(vec2(p.x * (1.15 + 2.4 * t * t), p.y * 0.98 + 0.05));
	float body = smoothstep(1.0, 0.72, r);
	float lick = smoothstep(0.3, 0.62, n2 + (1.0 - r) * 0.9);
	float alpha = body * lick;
	float core = smoothstep(0.95, 0.15, r + (n2 - 0.5) * 0.35);
	return vec4(core, n, 0.0, alpha);
}

// 13: a billowing smoke puff.
vec4 smoke(vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	float n = fbm(uv, vec2(4.0), 5);
	float n2 = fbm(uv + 0.3, vec2(8.0), 4);
	float r = length(p) + (n - 0.5) * 0.28;
	float alpha = smoothstep(0.95, 0.35, r) * smoothstep(0.15, 0.6, n2 + (1.0 - r) * 0.7);
	float lum = 0.55 + 0.3 * n2 + 0.2 * p.y;
	return vec4(clamp(lum, 0.0, 1.0), n, 0.0, alpha);
}

vec4 sample_pattern(vec2 uv) {
	uv = fract(uv);
	switch (pattern) {
		case 0: return stone_wall(uv);
		case 1: return rock(uv);
		case 2: return planks(uv);
		case 3: return shingles(uv);
		case 4: return plaster(uv);
		case 5: return bark(uv);
		case 6: return thatch(uv);
		case 7: return ground(uv);
		case 8: return dirt(uv);
		case 9: return hide(uv);
		case 10: return noise_pack(uv);
		case 11: return leaf_cluster(uv);
		case 12: return flame(uv);
		default: return smoke(uv);
	}
}

void fragment() {
	vec4 s = sample_pattern(UV);
	if (mode == 1) {
		vec2 e = vec2(1.0 / 512.0, 0.0);
		float dx = sample_pattern(UV - e.xy).b - sample_pattern(UV + e.xy).b;
		float dy = sample_pattern(UV - e.yx).b - sample_pattern(UV + e.yx).b;
		vec3 n = normalize(vec3(dx * normal_strength, dy * normal_strength, 0.1));
		COLOR = vec4(n * 0.5 + 0.5, 1.0);
	} else if (mode == 2) {
		COLOR = s;
	} else {
		COLOR = vec4(s.rgb, 1.0);
	}
}

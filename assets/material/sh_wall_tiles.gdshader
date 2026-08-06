shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 tile_color : source_color = vec4(0.96, 0.95, 0.91, 1.0);
uniform vec4 grout_color : source_color = vec4(0.67, 0.74, 0.78, 1.0);

uniform vec2 tile_count = vec2(6.0, 6.0);

uniform float grout_width : hint_range(0.01, 0.15) = 0.04;
uniform float corner_radius : hint_range(0.0, 0.2) = 0.07;
uniform float bevel_width : hint_range(0.01, 0.2) = 0.07;

uniform float bump_strength : hint_range(0.0, 10.0) = 4.0;
uniform float center_bulge : hint_range(0.0, 1.0) = 0.22;


float rounded_box_sdf(
	vec2 point,
	vec2 half_size,
	float radius
) {
	vec2 offset = abs(point) - half_size + vec2(radius);

	return (
		min(max(offset.x, offset.y), 0.0)
		+ length(max(offset, vec2(0.0)))
		- radius
	);
}


float tile_height(vec2 uv) {
	vec2 cell = fract(uv * tile_count) - vec2(0.5);

	vec2 tile_half_size = vec2(0.5 - grout_width);

	float distance_to_tile = rounded_box_sdf(
		cell,
		tile_half_size,
		corner_radius
	);

	float tile_mask = 1.0 - smoothstep(
		-0.006,
		0.006,
		distance_to_tile
	);

	// 从砖缝向砖面内部逐渐抬高，形成圆润倒角。
	float edge_height = smoothstep(
		0.0,
		bevel_width,
		max(-distance_to_tile, 0.0)
	);

	// 砖块中心轻微鼓起。
	vec2 normalized_cell = cell / tile_half_size;
	float distance_from_center = length(normalized_cell);

	float bulge = pow(
		max(1.0 - distance_from_center, 0.0),
		2.0
	);

	return tile_mask * (
		edge_height
		+ bulge * center_bulge
	);
}


void fragment() {
	vec2 cell = fract(UV * tile_count) - vec2(0.5);
	vec2 tile_half_size = vec2(0.5 - grout_width);

	float distance_to_tile = rounded_box_sdf(
		cell,
		tile_half_size,
		corner_radius
	);

	float antialias = fwidth(distance_to_tile);

	float tile_mask = 1.0 - smoothstep(
		-antialias,
		antialias,
		distance_to_tile
	);

	float inside_distance = max(-distance_to_tile, 0.0);

	float bevel_highlight = 1.0 - smoothstep(
		0.0,
		bevel_width,
		inside_distance
	);

	vec3 final_color = mix(
		grout_color.rgb,
		tile_color.rgb,
		tile_mask
	);

	final_color += bevel_highlight * tile_mask * 0.055;

	// 根据高度差生成程序化法线。
	float sample_offset = 0.0025;

	float height_left = tile_height(
		UV - vec2(sample_offset, 0.0)
	);

	float height_right = tile_height(
		UV + vec2(sample_offset, 0.0)
	);

	float height_down = tile_height(
		UV - vec2(0.0, sample_offset)
	);

	float height_up = tile_height(
		UV + vec2(0.0, sample_offset)
	);

	vec3 tangent_normal = normalize(
		vec3(
			(height_left - height_right) * bump_strength,
			(height_down - height_up) * bump_strength,
			1.0
		)
	);

	ALBEDO = final_color;
	ROUGHNESS = mix(0.70, 0.28, tile_mask);
	SPECULAR = 0.48;

	NORMAL_MAP = tangent_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
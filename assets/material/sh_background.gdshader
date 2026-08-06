shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D space_texture : source_color, filter_linear_mipmap;

uniform float rotation_speed : hint_range(-0.05, 0.05, 0.001) = 0.004;
uniform float drift_speed : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float drift_amount : hint_range(0.0, 0.05, 0.001) = 0.008;
uniform float zoom : hint_range(1.0, 2.0, 0.01) = 1.52;
uniform float brightness : hint_range(0.0, 2.0, 0.01) = 0.90;

void fragment() {
	vec2 uv = UV - vec2(0.5);

	float angle = TIME * rotation_speed;
	float c = cos(angle);
	float s = sin(angle);

	uv = vec2(
		uv.x * c - uv.y * s,
		uv.x * s + uv.y * c
	);

	uv /= zoom;
	uv += vec2(0.5);

	vec2 drift = vec2(
		sin(TIME * drift_speed),
		cos(TIME * drift_speed * 0.73)
	) * drift_amount;

	uv += drift;

	vec3 color = texture(space_texture, uv).rgb;
	ALBEDO = color * brightness;
}
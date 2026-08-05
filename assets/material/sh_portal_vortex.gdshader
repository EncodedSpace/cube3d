shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 inner_color : source_color =
	vec4(0.20, 0.95, 1.00, 1.0);

uniform vec4 outer_color : source_color =
	vec4(0.25, 0.45, 1.00, 1.0);

uniform float spin_speed : hint_range(-5.0, 5.0, 0.01) = 1.4;
uniform float spiral_count : hint_range(1.0, 10.0, 1.0) = 5.0;
uniform float brightness : hint_range(0.0, 5.0, 0.05) = 2.2;
uniform float hole_size : hint_range(0.0, 0.3, 0.01) = 0.10;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float radius = length(p);
	float angle = atan(p.y, p.x);

	// 螺旋纹理
	float spiral = sin(
		angle * spiral_count
		- TIME * spin_speed
		+ radius * 28.0
	);

	float bands = smoothstep(-0.30, 0.85, spiral);

	// 圆形外轮廓
	float outer_mask =
		1.0 - smoothstep(0.42, 0.50, radius);

	// 中间吸入口
	float inner_mask =
		smoothstep(hole_size * 0.4, hole_size, radius);

	// 呼吸式明暗变化
	float pulse =
		0.84
		+ sin(TIME * 2.2 - radius * 18.0) * 0.16;

	vec3 color = mix(
		inner_color.rgb,
		outer_color.rgb,
		smoothstep(0.08, 0.45, radius)
	);

	float alpha =
		outer_mask
		* inner_mask
		* (0.25 + bands * 0.75);

	float intensity = brightness * pulse;

	ALBEDO = color * intensity * 0.35;
	EMISSION = color * intensity * bands;
	ALPHA = alpha * 0.75;
}
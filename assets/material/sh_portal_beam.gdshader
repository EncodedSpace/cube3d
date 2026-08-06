shader_type spatial;

render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(
	0.25,
	0.90,
	1.00,
	1.00
);

uniform float brightness : hint_range(0.0, 3.0, 0.01) = 0.55;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.28;

uniform float fade_power : hint_range(0.2, 8.0, 0.1) = 2.2;

uniform float pulse_speed : hint_range(0.0, 5.0, 0.1) = 1.4;
uniform float pulse_amount : hint_range(0.0, 0.5, 0.01) = 0.12;

uniform float flow_speed : hint_range(-5.0, 5.0, 0.1) = 0.8;
uniform float flow_density : hint_range(1.0, 40.0, 1.0) = 14.0;
uniform float flow_strength : hint_range(0.0, 1.0, 0.01) = 0.25;

uniform bool invert_fade = false;


void fragment() {
	// 默认 UV.y = 0 为锅口，UV.y = 1 为光束顶部。
	float vertical_uv = UV.y;

	if (invert_fade) {
		vertical_uv = 1.0 - vertical_uv;
	}

	// 锅口附近最明显，向上逐渐消失。
	float distance_fade = pow(
		clamp(1.0 - vertical_uv, 0.0, 1.0),
		fade_power
	);

	// 防止光束最底部出现过于生硬的切边。
	float bottom_softness = smoothstep(
		0.0,
		0.035,
		vertical_uv
	);

	// 向上流动的柔和光带。
	float flow_wave = sin(
		vertical_uv * flow_density
		- TIME * flow_speed * 3.0
	);

	flow_wave = flow_wave * 0.5 + 0.5;

	float flow = mix(
		1.0 - flow_strength,
		1.0,
		flow_wave
	);

	// 整体轻微呼吸。
	float pulse = 1.0 + sin(
		TIME * pulse_speed
	) * pulse_amount;

	float final_alpha =
		opacity
		* distance_fade
		* bottom_softness
		* flow
		* pulse;

	vec3 final_color =
		beam_color.rgb
		* brightness
		* pulse;

	ALBEDO = final_color;
	EMISSION = final_color;
	ALPHA = clamp(final_alpha, 0.0, 1.0);
}
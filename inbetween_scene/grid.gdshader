// NOTE: Shader automatically converted from Godot Engine 4.7.1.stable's StandardMaterial3D.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform ivec2 albedo_texture_size;
uniform float point_size : hint_range(0.1, 128.0, 0.1);

uniform float roughness : hint_range(0.0, 1.0);
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;

uniform float specular : hint_range(0.0, 1.0, 0.01);
uniform float metallic : hint_range(0.0, 1.0, 0.01);

uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

// --- 优化后的网格参数 ---
group_uniforms Grid_Settings;
uniform bool enable_grid = true;                                            // 是否开启网格
uniform vec4 grid_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);          // 网格颜色（默认设为白色，方便对比）
uniform float grid_scale : hint_range(0.1, 100.0, 0.1) = 10.0;             // 网格密度
uniform float grid_thickness : hint_range(0.001, 0.2, 0.001) = 0.03;       // 线条粗细 (建议 0.01 ~ 0.05)
// ------------------------

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec2 base_uv = UV;

	vec4 albedo_tex = texture(texture_albedo, base_uv);
	vec3 final_albedo = albedo.rgb * albedo_tex.rgb;

	// --- 重新设计的平滑网格逻辑 ---
	if (enable_grid) {
		// 1. 将 UV 映射到 0~1 的重复网格单元
		vec2 g_uv = fract(base_uv * grid_scale);
		
		// 2. 计算每个像素到单元格边缘的距离
		vec2 dist = min(g_uv, 1.0 - g_uv);
		
		// 3. 使用屏幕空间微分计算边缘平滑抗锯齿范围
		vec2 der = fwidth(base_uv * grid_scale);
		vec2 grid_line = smoothstep(grid_thickness + der, grid_thickness - der, dist);
		
		// 4. 取 X 和 Y 方向的较大值形成交叉网格
		float grid_mask = max(grid_line.x, grid_line.y);
		
		// 5. 将网格混合到基础颜色上
		final_albedo = mix(final_albedo, grid_color.rgb, grid_mask * grid_color.a);
	}
	// ------------------------------

	ALBEDO = final_albedo;

	float metallic_tex = dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;

	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;
	ALPHA *= albedo.a * albedo_tex.a;
}
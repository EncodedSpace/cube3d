shader_type spatial;
render_mode unshaded;

group_uniforms Player_Interaction;
uniform vec3 player_position = vec3(0.0);                   // 玩家的世界坐标（由脚本传递）
uniform float interaction_radius : hint_range(1.0, 20.0) = 8.0; // 交互影响半径
uniform float ring_frequency : hint_range(0.5, 10.0) = 3.0;     // 动态波纹密度

group_uniforms Visual_Settings;
uniform float frequency : hint_range(0.1, 10.0) = 1.5;         // 纹理空间缩放比例
uniform float emission_energy : hint_range(1.0, 50.0) = 12.0; // 极高自发光亮度（开启 Glow 效果极佳）

varying vec3 world_pos; // 用于将顶点世界坐标传递给片元着色器

void vertex() {
    // 将顶点局部坐标转化为世界坐标
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // 1. 基于世界坐标生成连续的黑白网格/线条（消除 UV 缝隙）
    vec3 scale_pos = world_pos * frequency;
    vec3 grid = abs(fract(scale_pos - 0.5) - 0.5);
    float lines = smoothstep(0.08, 0.0, min(min(grid.x, grid.y), grid.z));
    
    // 2. 计算当前像素顶点与玩家位置的物理距离
    float dist_to_player = distance(world_pos, player_position);
    
    // 3. 根据玩家距离生成扩散的能量脉冲环（Distance Ring Effect）
    float ring = sin(dist_to_player * ring_frequency - TIME * 4.0);
    ring = smoothstep(0.4, 0.9, ring); // 拉高能量环对比度
    
    // 4. 计算玩家接近时的衰减（接近玩家时发光越强，远离则逐渐暗淡）
    float player_proximity = 1.0 - clamp(dist_to_player / interaction_radius, 0.0, 1.0);
    player_proximity = pow(player_proximity, 2.0); // 强化近距离爆发感
    
    // 5. 合成最终遮罩：网格线 + 玩家脉冲能量环
    float final_mask = max(lines * 0.3, ring * player_proximity);
    
    // 6. 输出纯黑背景与高亮纯白发光
    vec3 bright_white = vec3(1.0) * emission_energy * (1.0 + player_proximity * 2.0);
    ALBEDO = mix(vec3(0.0), bright_white, final_mask);
}
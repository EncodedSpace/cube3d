shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D bg_texture : source_color, filter_linear_mipmap;
uniform float brightness : hint_range(0.0, 2.0, 0.01) = 1.0;

void fragment() {
	ALBEDO = texture(bg_texture, UV).rgb * brightness;
}

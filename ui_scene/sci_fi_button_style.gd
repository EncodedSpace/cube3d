class_name SciFiButtonStyle
extends RefCounted
## In-game button look keyed off welcome subtitle blue (assets/story_style.tres).

# story_style.tres bg_color RGB (alpha boosted for solid buttons)
const WELCOME_BLUE := Color(0.288, 0.475, 0.6, 1.0)
const ACCENT := Color(0.45, 0.68, 0.88, 1.0)
const ACCENT_DIM := Color(0.288, 0.475, 0.6, 0.95)
const BTN_BG := Color(0.288, 0.475, 0.6, 0.85)
const BTN_BG_HOVER := Color(0.36, 0.56, 0.72, 0.95)
const BTN_BG_PRESSED := Color(0.22, 0.38, 0.52, 0.98)


static func make_style(bg: Color, border: Color, border_w: float = 2.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(round(border_w)))
	s.set_corner_radius_all(10)
	s.content_margin_left = 18.0
	s.content_margin_right = 18.0
	s.content_margin_top = 10.0
	s.content_margin_bottom = 10.0
	return s


## Apply menu button chrome. Does not force size (HUD buttons keep their layout).
static func apply(btn: Button, font_size: int = -1, highlight: bool = false) -> void:
	if btn == null:
		return
	var border := ACCENT if highlight else ACCENT_DIM
	var normal_bg := BTN_BG_PRESSED if highlight else BTN_BG
	btn.add_theme_stylebox_override("normal", make_style(normal_bg, border, 2.5 if highlight else 2.0))
	btn.add_theme_stylebox_override("hover", make_style(BTN_BG_HOVER, ACCENT, 2.5))
	btn.add_theme_stylebox_override("pressed", make_style(BTN_BG_PRESSED, Color(0.7, 0.85, 1.0, 1.0), 3.0))
	btn.add_theme_stylebox_override(
		"disabled",
		make_style(Color(0.18, 0.24, 0.32, 0.55), Color(0.35, 0.42, 0.5, 0.5), 1.0)
	)
	btn.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.85, 0.93, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.65, 0.7))
	if font_size > 0:
		btn.add_theme_font_size_override("font_size", font_size)


static func is_under_excluded_panel(node: Node) -> bool:
	var n := node
	while n != null:
		var name_str := String(n.name)
		if name_str == "GameOverPanel" or name_str == "VictoryPanel":
			return true
		n = n.get_parent()
	return false

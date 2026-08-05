extends Control

## Shared bottom-left WASD movement legend for every in-game HUD instance.
const FONT_PATH := "res://Fonts/Source Han Sans CN.ttf"
const BLUE := Color("#4ca3ffff")
const BLUE_SOFT := Color("#4ca3ff88")
const KEY_FILL := Color("#102238e8")
const PANEL_FILL := Color("#081322cc")

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(260, 240)
	_font = load(FONT_PATH) as Font
	queue_redraw()


func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_FILL
	panel.border_color = Color("#6f9bc055")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(22)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))

	# Rotate the movement axes 45° to match the isometric cube.
	# Key caps and WASD glyphs deliberately remain upright and horizontal.
	var origin := Vector2(130, 128)
	_draw_arrow(origin, Vector2(158, 100)) # W: cube-forward, upper right
	_draw_arrow(origin, Vector2(102, 100)) # A: cube-left, upper left
	_draw_arrow(origin, Vector2(102, 156)) # S: cube-back, lower left
	_draw_arrow(origin, Vector2(158, 156)) # D: cube-right, lower right
	# Four equally spaced positions around the center; each key cap stays unrotated.
	_draw_key(Vector2(156, 58), "W")
	_draw_key(Vector2(60, 58), "A")
	_draw_key(Vector2(60, 154), "S")
	_draw_key(Vector2(156, 154), "D")


func _draw_arrow(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, BLUE_SOFT, 3.0, true)
	var direction := (to - from).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var head_base := to - direction * 13.0
	draw_colored_polygon(PackedVector2Array([to, head_base + perpendicular * 7.0, head_base - perpendicular * 7.0]), BLUE)


func _draw_key(position: Vector2, key: String) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = KEY_FILL
	box.border_color = BLUE
	box.set_border_width_all(2)
	box.set_corner_radius_all(7)
	draw_style_box(box, Rect2(position, Vector2(44, 44)))
	var draw_font := _font if _font != null else ThemeDB.fallback_font
	draw_string(draw_font, position + Vector2(0, 31), key, HORIZONTAL_ALIGNMENT_CENTER, 44, 25, Color("#eaf5ff"))

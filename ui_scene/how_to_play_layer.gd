extends Control
class_name HowToPlayLayer

## A five-page, one-step-at-a-time help overlay.  It remains responsive while the game is paused.
signal return_requested

const FONT_PATH := "res://Fonts/Source Han Sans CN.ttf"
const CYAN := Color("#3ee4ee")
const CYAN_DIM := Color("#276f84")
const PANEL_BG := Color("#0b1928f8")
const CARD_BG := Color("#14293bf5")

## Five focused pages, presented one at a time.
const PAGES := [
	["1", "控制角色移动", ["W", "A", "S", "D"], "用 WASD 在当前墙面移动，探索可走的空间。", "从脚下这一步开始。"],
	["2", "旋转观察空间", ["Q", "E"], "按 Q / E 切换视角，寻找隐藏的道路与机关。", "换个角度，线索就会出现。"],
	["3", "翻转到另一面", ["贴近边缘", "继续前进"], "走到边缘后继续前进，立方体会翻转，重力也会改变。", "站稳，世界正在倒转。"],
	["4", "利用重力激活机关", ["特殊物品", "指定位置", "机关"], "利用重力，将特殊物品送达指定位置，激活机关。", "让重力替你完成最后一步。"],
	["5", "开启逃生大门", ["规划路径", "按钮", "逃生大门"], "合理规划路径，按下按钮，开启逃生大门。", "大门开启，向出口前进。"]
]

var _panel: PanelContainer
var _cards: Array[PanelContainer] = []
var _page_label: Label
var _previous_button: Button
var _next_button: Button
var _return_button: Button
var _page_index := 0
var _tween: Tween
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = load(FONT_PATH) as Font
	_build_interface()
	visible = false


func open() -> void:
	_page_index = 0
	_show_page(false)
	visible = true
	modulate = Color(1, 1, 1, 0)
	move_to_front()
	if _tween != null:
		_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.96, 0.96)
	_tween = create_tween().set_parallel(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _tween.finished
	visible = false
	modulate = Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		return_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_change_page(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_change_page(1)
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color("#06111ddd")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 32.0
	center.offset_top = 24.0
	center.offset_right = -32.0
	center.offset_bottom = -24.0
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(1040, 780)
	_panel.add_theme_stylebox_override("panel", _style(PANEL_BG, 18, CYAN_DIM, 2))
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := _label("玩法说明", 46, Color("#f4f8ff"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var subtitle := _label("◆  HOW TO PLAY  ◆", 17, CYAN)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)
	var goal := _label("探索、旋转、翻转，找到绿色出口", 20, Color("#bdd4ea"))
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(goal)

	var page_host := CenterContainer.new()
	page_host.custom_minimum_size = Vector2(0, 410)
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(page_host)
	for page in PAGES:
		var card := _make_page_card(page[0], page[1], page[2], page[3], page[4])
		page_host.add_child(card)
		_cards.append(card)

	var navigation := HBoxContainer.new()
	navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	navigation.add_theme_constant_override("separation", 20)
	content.add_child(navigation)
	_previous_button = _make_navigation_button("← 上一页")
	_previous_button.pressed.connect(func() -> void: _change_page(-1))
	navigation.add_child(_previous_button)
	_page_label = _label("", 18, Color("#c8def3"))
	_page_label.custom_minimum_size = Vector2(92, 42)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	navigation.add_child(_page_label)
	_next_button = _make_navigation_button("下一页 →")
	_next_button.pressed.connect(func() -> void: _change_page(1))
	navigation.add_child(_next_button)

	_return_button = Button.new()
	_return_button.text = "返回游戏"
	_return_button.custom_minimum_size = Vector2(240, 48)
	_return_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_return_button.focus_mode = Control.FOCUS_NONE
	SciFiButtonStyle.apply(_return_button, 22, true)
	_return_button.pressed.connect(func() -> void: return_requested.emit())
	content.add_child(_return_button)
	var hint := _label("左右方向键翻页 · ESC 返回游戏", 14, Color("#7896b2"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

	if _font != null:
		_apply_font(self, _font)
	_show_page(false)


func _make_page_card(number: String, heading: String, keys: Array, body: String, tip: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(820, 370)
	card.add_theme_stylebox_override("panel", _style(CARD_BG, 16, Color("#315d78"), 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)
	var step := _label("STEP " + number, 17, CYAN)
	step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(step)
	var heading_label := _label(heading, 32, Color("#f5f9ff"))
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading_label)
	box.add_child(_make_key_layout(number, keys))
	box.add_child(HSeparator.new())
	var description := _label(body, 21, Color("#ccddec"))
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(description)
	var note := _label("✦  " + tip + "  ✦", 16, CYAN)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	return card


func _make_key_layout(number: String, keys: Array) -> Control:
	# Step 1 deliberately follows the familiar keyboard layout: W above A / S / D.
	if number == "1":
		var keyboard := VBoxContainer.new()
		keyboard.alignment = BoxContainer.ALIGNMENT_CENTER
		keyboard.add_theme_constant_override("separation", 8)
		var top_row := HBoxContainer.new()
		top_row.alignment = BoxContainer.ALIGNMENT_CENTER
		top_row.add_child(_make_key_chip("W"))
		keyboard.add_child(top_row)
		var bottom_row := HBoxContainer.new()
		bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
		bottom_row.add_theme_constant_override("separation", 10)
		for key in ["A", "S", "D"]:
			bottom_row.add_child(_make_key_chip(key))
		keyboard.add_child(bottom_row)
		return keyboard

	var keys_row := HBoxContainer.new()
	keys_row.alignment = BoxContainer.ALIGNMENT_CENTER
	keys_row.add_theme_constant_override("separation", 10)
	for key in keys:
		keys_row.add_child(_make_key_chip(str(key)))
	return keys_row


func _make_navigation_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(145, 42)
	button.focus_mode = Control.FOCUS_NONE
	SciFiButtonStyle.apply(button, 17)
	return button


func _make_key_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _style(Color("#091623"), 7, CYAN, 1))
	var label := _label(text, 16, Color("#e9f7ff"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	margin.add_child(label)
	chip.add_child(margin)
	return chip


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _change_page(direction: int) -> void:
	var target := clampi(_page_index + direction, 0, PAGES.size() - 1)
	if target == _page_index:
		return
	_page_index = target
	_show_page(true)


func _show_page(animate: bool) -> void:
	if _cards.is_empty():
		return
	for index in _cards.size():
		var card := _cards[index]
		card.visible = index == _page_index
		if card.visible and animate:
			card.modulate = Color(1, 1, 1, 0)
			card.scale = Vector2(0.96, 0.96)
			card.pivot_offset = card.size * 0.5
			var page_tween := card.create_tween().set_parallel(true)
			page_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			page_tween.tween_property(card, "modulate:a", 1.0, 0.18)
			page_tween.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			card.modulate = Color.WHITE
			card.scale = Vector2.ONE
	_page_label.text = "%d / %d" % [_page_index + 1, PAGES.size()]
	_previous_button.disabled = _page_index == 0
	_next_button.disabled = _page_index == PAGES.size() - 1


func _style(color: Color, radius: int, border: Color, width: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(radius)
	return result


func _apply_font(node: Node, font: Font) -> void:
	if node is Label or node is Button:
		(node as Control).add_theme_font_override("font", font)
	for child in node.get_children():
		_apply_font(child, font)

extends CanvasLayer

## Zen-mode UI controller – size input → generate → shared in-game UI.

const SHARED_UI_PATH := "res://ui_scene/ui_ingame.tscn"

var _cube: Node3D = null
var _shared_ui: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false

	_cube = get_parent().get_node_or_null("Node3D")
	if _cube == null:
		push_error("ZenUI: Node3D not found.")
		return

	# Freeze the player until the map is generated
	var player := get_parent().get_node_or_null("Player") as Node3D
	if player != null:
		player.set_physics_process(false)

	_show_size_panel()


# ═══════════════════════════════════════════════════════════════
#  Size input panel
# ═══════════════════════════════════════════════════════════════

func _show_size_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "SizePanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.set_size(Vector2(400, 260))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.92)
	style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "禅模式"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	# Spacer
	var s1 := Control.new()
	s1.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(s1)

	# Hint
	var hint := Label.new()
	hint.text = "输入地图尺寸（6–12）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	vbox.add_child(hint)

	# SpinBox row
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(hbox)

	var spin := SpinBox.new()
	spin.name = "SizeSpin"
	spin.min_value = 6
	spin.max_value = 12
	spin.value = 8
	spin.step = 1
	spin.custom_minimum_size = Vector2(100, 0)
	spin.add_theme_font_size_override("font_size", 24)
	hbox.add_child(spin)

	# Buttons
	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_box)

	var gen_btn := Button.new()
	gen_btn.text = "生成地图"
	gen_btn.custom_minimum_size = Vector2(140, 44)
	gen_btn.add_theme_font_size_override("font_size", 22)
	gen_btn.pressed.connect(_on_generate_pressed.bind(spin))
	btn_box.add_child(gen_btn)

	var back_btn := Button.new()
	back_btn.text = "返回主菜单"
	back_btn.custom_minimum_size = Vector2(140, 44)
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.pressed.connect(_on_back_pressed)
	btn_box.add_child(back_btn)

	add_child(panel)


func _on_generate_pressed(spin: SpinBox) -> void:
	var size := int(spin.value)
	_cube.set("n", size)
	_cube.generate()

	# Unfreeze the player now that the map exists
	var player := get_parent().get_node_or_null("Player") as Node3D
	if player != null:
		player.set_physics_process(true)

	# Wait one frame for the scene tree to settle, then show shared UI.
	await get_tree().process_frame

	# Remove size panel
	var panel := get_node_or_null("SizePanel")
	if panel != null:
		panel.queue_free()

	# Instantiate shared UI
	var ui_scene := load(SHARED_UI_PATH) as PackedScene
	if ui_scene == null:
		push_error("ZenUI: cannot load shared UI scene.")
		return

	_shared_ui = ui_scene.instantiate() as CanvasLayer
	_shared_ui.name = "ui_ingame"
	_shared_ui.set("welcome_text", "禅模式 · %d×%d×%d\n走向蓝色出口吧！" % [size, size, size])
	_shared_ui.set("congrats_text", "恭喜你完成了禅模式！")
	_shared_ui.set("next_scene", "")   # no next level in zen mode
	get_parent().add_child(_shared_ui)

	# Connect the exit signal from Node3D/staticboxes/StaticBox_EXIT → shared UI
	var exit_area := _cube.get_node_or_null("staticboxes/StaticBox_EXIT") as Area3D
	if exit_area != null:
		if not exit_area.body_entered.is_connected(_shared_ui._on_exit_body_entered):
			exit_area.body_entered.connect(_shared_ui._on_exit_body_entered)


func _on_back_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main.tscn")


# ═══════════════════════════════════════════════════════════════
#  Forward Q/E input to the cube
# ═══════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if _cube == null:
		return
	if event.is_action_pressed("rotate_left") and _cube.has_method("_on_left_pressed"):
		_cube._on_left_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_right") and _cube.has_method("_on_right_pressed"):
		_cube._on_right_pressed()
		get_viewport().set_input_as_handled()

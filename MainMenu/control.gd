extends Control
## Sci-fi main menu — 三面之外 (default visible page).

const CYAN := Color(0.6, 1.0, 1.0, 1.0)

@onready var help_button: Button = $TopBar/HelpButton
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var tutorial_button: Button = $CenterContainer/VBoxContainer/TutorialButton
@onready var level1_button: Button = $CenterContainer/VBoxContainer/Level1Button
@onready var level2_button: Button = $CenterContainer/VBoxContainer/Level2Button
@onready var level3_button: Button = $CenterContainer/VBoxContainer/Level3Button
@onready var level4_button: Button = $CenterContainer/VBoxContainer/Level4Button
@onready var level5_button: Button = $CenterContainer/VBoxContainer/Level5Button
@onready var level6_button: Button = $CenterContainer/VBoxContainer/Level6Button
@onready var zen_mode_button: Button = $CenterContainer/VBoxContainer/ZenModeButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton
@onready var how_to_play: HowToPlayLayer = $HowToPlayLayer

var _feedback_busy := false


func _ready() -> void:
	_connect_buttons()
	_refresh_unlocks()
	if how_to_play:
		how_to_play.return_requested.connect(_on_help_closed)


func _connect_buttons() -> void:
	start_button.pressed.connect(_on_start_pressed)
	tutorial_button.pressed.connect(_on_tutorial_pressed)
	level1_button.pressed.connect(_on_level1_pressed)
	level2_button.pressed.connect(_on_level2_pressed)
	level3_button.pressed.connect(_on_level3_pressed)
	level4_button.pressed.connect(_on_level4_pressed)
	level5_button.pressed.connect(_on_level5_pressed)
	level6_button.pressed.connect(_on_level6_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	help_button.pressed.connect(_on_help_pressed)
	zen_mode_button.pressed.connect(_on_zen_mode_pressed)


func _refresh_unlocks() -> void:
	var progress := get_node_or_null("/root/LevelProgress")
	tutorial_button.disabled = false
	if progress == null:
		level1_button.disabled = true
		level2_button.disabled = true
		level3_button.disabled = true
		level4_button.disabled = true
		level5_button.disabled = true
		level6_button.disabled = true
		return
	level1_button.disabled = not progress.is_completed("teach")
	level2_button.disabled = not progress.is_completed("level1")
	level3_button.disabled = not progress.is_completed("level2")
	level4_button.disabled = not progress.is_completed("level3")
	level5_button.disabled = not progress.is_completed("level4")
	level6_button.disabled = not progress.is_completed("level4")


func _button_feedback(btn: BaseButton) -> void:
	if _feedback_busy or btn == null:
		return
	_feedback_busy = true
	var original_modulate := btn.modulate
	var original_scale := btn.scale
	btn.pivot_offset = btn.size * 0.5
	btn.modulate = CYAN
	btn.scale = Vector2(1.06, 1.06)
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(btn):
		btn.modulate = original_modulate
		btn.scale = original_scale
	_feedback_busy = false


func _go_to_scene(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Scene not found: %s" % path)
		return
	get_tree().change_scene_to_file(path)


func _on_start_pressed() -> void:
	await _button_feedback(start_button)
	_go_to_scene("res://teach/main.tscn")


func _on_tutorial_pressed() -> void:
	await _button_feedback(tutorial_button)
	_go_to_scene("res://teach/main.tscn")


func _on_level1_pressed() -> void:
	await _button_feedback(level1_button)
	_go_to_scene("res://level1/main.tscn")


func _on_level2_pressed() -> void:
	await _button_feedback(level2_button)
	_go_to_scene("res://level2/main.tscn")


func _on_level3_pressed() -> void:
	await _button_feedback(level3_button)
	_go_to_scene("res://level3/main.tscn")


func _on_level4_pressed() -> void:
	await _button_feedback(level4_button)
	_go_to_scene("res://level5/main.tscn")


func _on_level5_pressed() -> void:
	await _button_feedback(level5_button)
	_go_to_scene("res://level6/main.tscn")


func _on_level6_pressed() -> void:
	await _button_feedback(level6_button)
	_go_to_scene("res://level7/main.tscn")


func _on_quit_pressed() -> void:
	await _button_feedback(quit_button)
	get_tree().quit()


func _on_zen_mode_pressed() -> void:
	# Zen mode is intentionally always available and does not use level-unlock progress.
	await _button_feedback(zen_mode_button)
	_go_to_scene("res://map_generator/zen_mode.tscn")


func _on_help_pressed() -> void:
	await _button_feedback(help_button)
	if how_to_play:
		how_to_play.open()


func _on_help_closed() -> void:
	if how_to_play:
		how_to_play.close()

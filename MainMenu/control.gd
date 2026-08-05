extends Control

## MainMenu controller - sequential level activation.
## Teaching -> Level1 -> Level2 -> Level3 -> Level4, unlocked by completion.
## ZEN MODE is always available.

func _ready() -> void:
	_refresh_buttons()

func _refresh_buttons() -> void:
	var btn1 := $HBoxContainer/Button as Button  # 教学关卡
	var btn2 := $HBoxContainer/Button2 as Button  # 关卡1
	var btn3 := $HBoxContainer/Button3 as Button  # 关卡2
	var btn4 := $HBoxContainer/Button4 as Button  # 关卡3
	var btn5 := $HBoxContainer/Button5 as Button  # 关卡4

	var progress := get_node_or_null("/root/LevelProgress")
	# 教学关卡始终可用
	btn1.disabled = false
	# 后续关卡按顺序解锁
	if progress == null:
		btn2.disabled = true
		btn3.disabled = true
		btn4.disabled = true
		btn5.disabled = true
		return
	btn2.disabled = not progress.is_completed("teach")
	btn3.disabled = not progress.is_completed("level1")
	btn4.disabled = not progress.is_completed("level2")
	btn5.disabled = not progress.is_completed("level3")


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://teach/main.tscn")

func _on_button2_pressed() -> void:
	get_tree().change_scene_to_file("res://level1/main.tscn")

func _on_button3_pressed() -> void:
	get_tree().change_scene_to_file("res://level2/main.tscn")

func _on_button4_pressed() -> void:
	get_tree().change_scene_to_file("res://level3/main.tscn")

func _on_button5_pressed() -> void:
	get_tree().change_scene_to_file("res://level4/main.tscn")

func _on_zen_mode_pressed() -> void:
	get_tree().change_scene_to_file("res://map_generator/zen_mode.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()

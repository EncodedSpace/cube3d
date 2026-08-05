extends CanvasLayer

const SUCCEED_SFX_PATH := "res://audio/succeed.mp3"

var won: bool = false
var _succeed_sfx: AudioStreamPlayer


func _ready() -> void:
	# 自动加入分组，所有关卡都不需要手动设置。
	if not is_in_group("ui_ingame"):
		add_to_group("ui_ingame")

	# 暂停游戏后，UI 仍然可以操作。
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 防止上一个场景遗留暂停状态。
	get_tree().paused = false

	$back.visible = false
	$next.visible = false
	$congratulations.visible = false
	$help.visible = false
	$help_bg.visible = false
	$welcome.visible = true
	$GameOverPanel.visible = false

	# 防止空格或回车触发按钮。
	for child in get_children():
		if child is BaseButton:
			(child as BaseButton).focus_mode = (
				Control.FOCUS_NONE
			)

	_setup_succeed_sfx()
	_hide_welcome_after_delay()

	var player := get_parent().get_node_or_null("Player")

	if player != null and player.has_signal("died"):
		if not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or won:
		return

	var player := get_parent().get_node_or_null("Player")

	# 角色死亡后禁止 Q/E 旋转。
	if player != null and player.get("is_dead") == true:
		return

	var cube := get_parent().get_node_or_null("Node3D")

	if cube == null:
		return

	if (
		event.is_action_pressed("rotate_left")
		and cube.has_method("_on_left_pressed")
	):
		cube._on_left_pressed()
		get_viewport().set_input_as_handled()

	elif (
		event.is_action_pressed("rotate_right")
		and cube.has_method("_on_right_pressed")
	):
		cube._on_right_pressed()
		get_viewport().set_input_as_handled()


func _hide_welcome_after_delay() -> void:
	await get_tree().create_timer(2.0).timeout

	if is_instance_valid($welcome):
		$welcome.visible = false


# 兼容旧关卡中仍然存在的 body_entered 信号连接。
# 这里不能再立即显示胜利，否则会打断吸入动画。
func _on_exit_body_entered(_body: Node) -> void:
	return


# 兼容手动连接的 absorption_finished 信号。
func _on_exit_absorption_finished() -> void:
	show_win_after_absorb()


# 传送门公共场景通过 ui_ingame 分组调用这个方法。
func show_win_after_absorb() -> void:
	if won:
		return

	_show_win()


func _show_win() -> void:
	if won:
		return

	won = true

	_play_succeed_sfx()

	$congratulations.visible = true
	$back.visible = true
	$next.visible = true

	game_paused()


func _setup_succeed_sfx() -> void:
	_succeed_sfx = AudioStreamPlayer.new()
	_succeed_sfx.name = "SucceedSfx"
	_succeed_sfx.bus = "Master"
	_succeed_sfx.volume_db = -4.0
	_succeed_sfx.process_mode = Node.PROCESS_MODE_ALWAYS

	add_child(_succeed_sfx)

	if ResourceLoader.exists(SUCCEED_SFX_PATH):
		_succeed_sfx.stream = (
			load(SUCCEED_SFX_PATH) as AudioStream
		)


func _play_succeed_sfx() -> void:
	if _succeed_sfx != null and _succeed_sfx.stream != null:
		_succeed_sfx.play()


func _on_back_pressed() -> void:
	reset_level()
	game_continued()


func _on_help_button_pressed() -> void:
	$help.visible = true
	$help_bg.visible = true
	game_paused()


func game_paused() -> void:
	$exit.disabled = true
	$welcome.visible = false

	var player := get_parent().get_node_or_null("Player")

	if player != null:
		player.set_physics_process(false)

		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO

	for box in _movable_boxes():
		box.freeze = true

	get_tree().paused = true


func game_continued() -> void:
	$exit.disabled = false

	$back.visible = false
	$next.visible = false
	$congratulations.visible = false
	$help.visible = false
	$help_bg.visible = false

	var player := get_parent().get_node_or_null("Player")

	if player != null:
		player.set_physics_process(true)

	for box in _movable_boxes():
		box.freeze = false

	get_tree().paused = false


func _on_back_to_game_pressed() -> void:
	game_continued()


func _on_exit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


func _movable_boxes() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []

	var cube := get_parent().get_node_or_null("Node3D")

	if cube == null:
		return result

	for child in cube.get_children():
		if (
			child is RigidBody3D
			and "MovableBox" in child.name
		):
			result.append(child as RigidBody3D)

	return result


func reset_level() -> void:
	get_tree().paused = false
	won = false

	# 先恢复传送门和被隐藏的玩家状态。
	get_tree().call_group(
		"exit_portal",
		"reset_portal"
	)

	var cube := get_parent().get_node_or_null("Node3D")

	if cube != null and cube.has_method("reset_to_start"):
		cube.reset_to_start()

	for box in _movable_boxes():
		if box.has_method("reset_to_start"):
			box.reset_to_start()

		box.freeze = false

	var player := get_parent().get_node_or_null("Player")

	if player != null:
		player.visible = true
		player.process_mode = Node.PROCESS_MODE_INHERIT

		player.set_process_input(true)
		player.set_process_unhandled_input(true)
		player.set_process_unhandled_key_input(true)
		player.set_physics_process(true)

		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO

		if player.has_method("reset_to_start"):
			player.reset_to_start()


func _on_next_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(
		"res://level2/main.tscn"
	)


func _on_player_died() -> void:
	for child in get_children():
		if (
			child is CanvasItem
			and child != $GameOverPanel
		):
			child.visible = false

	$GameOverPanel.visible = true
	get_tree().paused = true


func _on_restart_button_pressed() -> void:
	get_tree().paused = false

	var level_root := get_parent()
	var scene_path: String = level_root.scene_file_path

	if scene_path.is_empty():
		push_error("无法识别当前关卡场景路径")
		return

	print("重新加载关卡：", scene_path)

	get_tree().change_scene_to_file(scene_path)


func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()

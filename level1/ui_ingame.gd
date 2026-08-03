extends CanvasLayer

var won: bool = false


func _ready() -> void:
	# Stay interactive while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# In case previous scene left the tree paused (e.g. teach win → next).
	get_tree().paused = false
	$back.visible = false
	$next.visible = false
	$congratulations.visible = false
	$help.visible = false
	$help_bg.visible = false
	$welcome.visible = true

	# Prevent Space/Enter from activating a focused button (would also jump).
	for child in get_children():
		if child is BaseButton:
			(child as BaseButton).focus_mode = Control.FOCUS_NONE

	_hide_welcome_after_delay()

	$GameOverPanel.visible = false

	var player := get_parent().get_node_or_null("Player")
	if player != null and player.has_signal("died"):
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

	if event.is_action_pressed("rotate_left") and cube.has_method("_on_left_pressed"):
		cube._on_left_pressed()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("rotate_right") and cube.has_method("_on_right_pressed"):
		cube._on_right_pressed()
		get_viewport().set_input_as_handled()


func _hide_welcome_after_delay() -> void:
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid($welcome):
		$welcome.visible = false


func _on_exit_body_entered(body: Node) -> void:
	if body.name != "Player":
		return
	_show_win()


func _show_win() -> void:
	won = true
	$congratulations.visible = true
	$back.visible = true
	$next.visible = true
	game_paused()


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
	get_tree().quit()


func _movable_boxes() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	var cube := get_parent().get_node_or_null("Node3D")
	if cube == null:
		return result
	for child in cube.get_children():
		if child is RigidBody3D and "MovableBox" in child.name:
			result.append(child as RigidBody3D)
	return result


func reset_level() -> void:
	# 若在暂停中，先恢复，再重置
	get_tree().paused = false
	won = false

	var cube := get_parent().get_node_or_null("Node3D")
	if cube != null and cube.has_method("reset_to_start"):
		cube.reset_to_start()

	for box in _movable_boxes():
		if box.has_method("reset_to_start"):
			box.reset_to_start()
		box.freeze = false

	var player := get_parent().get_node_or_null("Player")
	if player != null and player.has_method("reset_to_start"):
		player.reset_to_start()
		player.set_physics_process(true)


func _on_next_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://level2/main.tscn")


func _on_player_died() -> void:
	for child in get_children():
		if child is CanvasItem and child != $GameOverPanel:
			child.visible = false

	$GameOverPanel.visible = true
	get_tree().paused = true


func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()

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

	# Prevent Space/Enter from activating a focused button (would fire left/right
	# rotate while also jumping).
	for child in get_children():
		if child is BaseButton:
			(child as BaseButton).focus_mode = Control.FOCUS_NONE

	_hide_welcome_after_delay()


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
	$left.disabled = true
	$right.disabled = true
	$exit.disabled = true
	$welcome.visible = false
	
	var player := get_parent().get_node_or_null("Player")
	if player != null:
		player.set_physics_process(false)
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO

	var box := get_parent().get_node_or_null("Node3D/MovableBox") as RigidBody3D
	if box != null:
		box.freeze = true

	get_tree().paused = true
	
func game_continued() -> void:
	$left.disabled = false
	$right.disabled = false
	$exit.disabled = false
	$back.visible = false
	$next.visible = false
	$congratulations.visible = false
	$help.visible = false
	$help_bg.visible = false

	var player := get_parent().get_node_or_null("Player")
	if player != null:
		player.set_physics_process(true)

	var box := get_parent().get_node_or_null("Node3D/MovableBox") as RigidBody3D
	if box != null:
		box.freeze = false

	get_tree().paused = false

func _on_back_to_game_pressed() -> void:
	game_continued()

func _on_exit_pressed() -> void:
	get_tree().quit()
	
func reset_level() -> void:
	# 若在暂停中，先恢复，再重置
	get_tree().paused = false
	won = false

	var cube := get_parent().get_node_or_null("Node3D")
	if cube != null and cube.has_method("reset_to_start"):
		cube.reset_to_start()

	var player := get_parent().get_node_or_null("Player")
	if player != null and player.has_method("reset_to_start"):
		player.reset_to_start()
		player.set_physics_process(true)

	var box := get_parent().get_node_or_null("Node3D/MovableBox") as RigidBody3D
	if box != null:
		box.freeze = false
		# 若也要箱子回原位，可同样给箱子记 start_transform 再重置

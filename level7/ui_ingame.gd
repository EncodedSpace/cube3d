extends CanvasLayer

const SUCCEED_SFX_PATH := "res://assets/audio/succeed.mp3"

var won: bool = false
var _succeed_sfx: AudioStreamPlayer


func _ready() -> void:
	# Stay interactive while the game tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# In case previous scene left the tree paused (e.g. teach win �?next).
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

	_setup_succeed_sfx()
	_hide_welcome_after_delay()


func _unhandled_input(event: InputEvent) -> void:
	# Q = yaw left, E = yaw right. Blocked while paused / on win screen.
	if get_tree().paused or won:
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
	if won or body.name != "Player":
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
		_succeed_sfx.stream = load(SUCCEED_SFX_PATH) as AudioStream


func _play_succeed_sfx() -> void:
	if _succeed_sfx and _succeed_sfx.stream:
		_succeed_sfx.play()


func _on_back_pressed() -> void:
	reset_level()


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
	# 关卡内道具状态很多（钥匙已吃、门已开、G 已删等），整关重载才能完整复原�?	get_tree().paused = false
	won = false
	get_tree().reload_current_scene()

func _on_next_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://level2/main.tscn")

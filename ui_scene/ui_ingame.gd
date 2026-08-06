extends CanvasLayer

const SUCCEED_SFX_PATH := "res://assets/audio/succeed.mp3"
## Resolved .import UID -> use path load as fallback when uid:// fails (e.g. Web).
const FONT_PATH := "res://Fonts/Source Han Sans CN.ttf"

## 欢迎语，�?_ready 中自动设置到 welcome Label
@export_multiline var welcome_text: String = "欢迎来到教学关卡！\n请走到绿色出口吧�?
## 通关祝贺�?@export_multiline var congrats_text: String = "恭喜你完成了教学关卡�?
## 下一关的场景路径，为空则隐藏"下一�?按钮
@export var next_scene: String = ""
## 是否为禅模式：true 时显�?重新生成"按钮并隐�?下一�?
@export var is_zen_mode: bool = false

var won: bool = false
var _succeed_sfx: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	won = false

	if not is_in_group("ui_ingame"):
		add_to_group("ui_ingame")

	_apply_ui_theme()

	$back.visible = false
	$next.visible = false
	$next2.visible = false
	$zen_mode.visible = false
	$congratulations.visible = false
	$help.visible = false
	$help_bg.visible = false
	$welcome.visible = true
	# 禅模式专属：显示"重新生成"按钮
	$recreate.visible = is_zen_mode

	$welcome.text = welcome_text
	$congratulations.text = congrats_text

	for child in get_children():
		if child is BaseButton:
			(child as BaseButton).focus_mode = Control.FOCUS_NONE

	_setup_succeed_sfx()
	_hide_welcome_after_delay()

	var game_over := get_node_or_null("GameOverPanel") as CanvasItem
	if game_over != null:
		game_over.visible = false

	var player := get_parent().get_node_or_null("Player")
	if player != null and player.has_signal("died"):
		player.died.connect(_on_player_died)


## Apply the Chinese font to every Label + Button descendant.
## Uses add_theme_font_override("font", ...) directly on each control,
## which is the most reliable way across all platforms including Web.
func _apply_ui_theme() -> void:
	var font := load(FONT_PATH) as Font
	if font == null:
		return
	var controls: Array[Node] = []
	_gather_text_controls(self, controls)
	for c in controls:
		(c as Control).add_theme_font_override("font", font)


func _gather_text_controls(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child is Label or child is Button:
			result.append(child)
		_gather_text_controls(child, result)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or won:
		return
	var player := get_parent().get_node_or_null("Player")
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


# 兼容旧关�?body_entered 连接。若本关�?portal_absorb，则等吸入结束后再胜利�?func _on_exit_body_entered(body: Node) -> void:
	if won or body.name != "Player":
		return
	if not get_tree().get_nodes_in_group("exit_portal").is_empty():
		return
	_show_win()


func _on_exit_absorption_finished() -> void:
	show_win_after_absorb()


# 传送门吸入结束后由 portal_absorb 通过 ui_ingame 分组调用�?func show_win_after_absorb() -> void:
	_show_win()


func _show_win() -> void:
	if won:
		return
	won = true
	_play_succeed_sfx()
	$congratulations.visible = true
	$back.visible = true
	$zen_mode.visible = true
	if not next_scene.is_empty():
		$next.visible = true
	# 禅模式通关后：显示"下一轮游�?按钮（作用同"重新生成"�?	if is_zen_mode:
		$next2.visible = true
		$next.visible = false
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


func _on_reload_pressed() -> void:
	reset_level()


func _on_zen_mode_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://map_generator/zen_mode.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://MainMenu/control.tscn")


func _on_next2_pressed() -> void:
	# 禅模式专�?下一轮游�?：与"重新生成"一致，弹出尺寸面板重新建图�?	_on_recreate_pressed()


func _on_recreate_pressed() -> void:
	# 禅模式专属：把请求转发给 ZenUI，让它显示居中的尺寸面板�?	var zen := get_parent().get_node_or_null("ZenUI")
	if zen != null and zen.has_method("_on_recreate_pressed"):
		zen._on_recreate_pressed()


func _on_size_menu_pressed(id: int) -> void:
	# MenuButton 选择尺寸后：禅模式直接按所选尺寸重新生成�?	var zen := get_parent().get_node_or_null("ZenUI")
	if zen == null or not zen.has_method("_generate_with_size"):
		return
	var size := 6 + id
	zen._generate_with_size(size)


func _on_help_button_pressed() -> void:
	# Always hide legacy help panel �?only show sci-fi HowToPlayLayer.
	$help.visible = false
	$help_bg.visible = false
	game_paused()
	var help_layer := $HowToPlayLayer as HowToPlayLayer
	if help_layer:
		help_layer.open()
	else:
		push_error("HowToPlayLayer missing on ui_ingame")


func game_paused() -> void:
	$exit.disabled = true
	$welcome.visible = false
	$help.visible = false
	$help_bg.visible = false

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
	$next2.visible = false
	$zen_mode.visible = false
	$congratulations.visible = false
	$help.visible = false
	$help_bg.visible = false
	if has_node("HowToPlayLayer"):
		$HowToPlayLayer.close()

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
		if child is RigidBody3D and (
			"MovableBox" in child.name or "DeadlyBox" in child.name
		):
			result.append(child as RigidBody3D)
	return result


func reset_level() -> void:
	# 不要�?reload 之后再调�?game_continued（节点已被释放）�?	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	won = false

	# 禅模式：软重置，保留当前生成的地图�?	if is_zen_mode:
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
		game_continued()
		return

	# 手写关卡：整关重载，确保钥匙/门等状态完整复原�?	tree.reload_current_scene()


func _on_next_pressed() -> void:
	get_tree().paused = false
	if not next_scene.is_empty():
		# 标记当前关卡完成
		_mark_current_level_complete()
		get_tree().change_scene_to_file(next_scene)


func _mark_current_level_complete() -> void:
	var progress := get_node_or_null("/root/LevelProgress")
	if progress == null:
		return
	match next_scene:
		"res://level1/main.tscn":
			progress.mark_completed("teach")
		"res://level2/main.tscn":
			progress.mark_completed("level1")
		"res://level3/main.tscn":
			progress.mark_completed("level2")
		"res://level4/main.tscn":
			progress.mark_completed("level3")
		"res://level5/main.tscn":
			progress.mark_completed("level4")


func _on_player_died() -> void:
	var game_over := get_node_or_null("GameOverPanel") as CanvasItem
	if game_over == null:
		return
	for child in get_children():
		if child is CanvasItem and child != game_over:
			(child as CanvasItem).visible = false
	game_over.visible = true
	get_tree().paused = true


func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	var level_root := get_parent()
	var scene_path: String = level_root.scene_file_path if level_root != null else ""
	if scene_path.is_empty():
		push_error("无法识别当前关卡场景路径")
		return
	get_tree().change_scene_to_file(scene_path)


func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()

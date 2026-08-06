extends CanvasLayer

const SUCCEED_SFX_PATH := "res://assets/audio/succeed.mp3"
## Resolved .import UID -> use path load as fallback when uid:// fails (e.g. Web).
const FONT_PATH := "res://Fonts/Source Han Sans CN.ttf"

## 欢迎语，在 _ready 中自动设置到 welcome Label
@export_multiline var welcome_text: String = "欢迎来到教学关卡！\n请走到绿色出口吧！"
## 通关祝贺语
@export_multiline var congrats_text: String = "恭喜你完成了教学关卡！"
## 下一关的场景路径，为空则隐藏"下一关"按钮
@export var next_scene: String = ""
## 是否为禅模式：true 时显示"重新生成"按钮并隐藏"下一关"
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
	# 禅模式才显示"重新生成"按钮
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
	var victory := get_node_or_null("VictoryPanel") as CanvasItem
	if victory != null:
		victory.visible = false

	var player := get_parent().get_node_or_null("Player")
	if player != null and player.has_signal("died"):
		player.died.connect(_on_player_died)


## Apply the Chinese font to every Label + Button descendant,
## and style buttons like the main menu (except GameOver / Victory panels).
func _apply_ui_theme() -> void:
	var font := load(FONT_PATH) as Font
	if font == null:
		push_error("无法加载字体：Fonts/Source Han Sans CN.ttf")
		return
	var controls: Array[Node] = []
	_gather_text_controls(self, controls)
	for c in controls:
		(c as Control).add_theme_font_override("font", font)
		if c is Button and not SciFiButtonStyle.is_under_excluded_panel(c):
			var btn := c as Button
			var highlight := btn.name in ["next", "next2", "zen_mode", "back"]
			# Keep existing scene font sizes when set; otherwise match menu (26).
			var size := btn.get_theme_font_size("font_size")
			if size <= 0:
				size = 26
			SciFiButtonStyle.apply(btn, size, highlight)


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


# Compatible with old body_entered connections. If portal_absorb exists, wait for absorb.
func _on_exit_body_entered(body: Node) -> void:
	if won or body.name != "Player":
		return
	if not get_tree().get_nodes_in_group("exit_portal").is_empty():
		return
	_show_win()


func _on_exit_absorption_finished() -> void:
	show_win_after_absorb()


# Called by portal_absorb via the ui_ingame group after suction finishes.
func show_win_after_absorb() -> void:
	_show_win()


func _show_win() -> void:
	if won:
		return
	won = true
	_play_succeed_sfx()
	# Unlock next level as soon as this stage is cleared (not only when pressing Next).
	_mark_current_level_complete()
	# Legacy win chrome stays hidden; dessert VictoryPanel is the win UI.
	$congratulations.visible = false
	$back.visible = false
	$next.visible = false
	$next2.visible = false
	$zen_mode.visible = false
	var game_over := get_node_or_null("GameOverPanel") as CanvasItem
	if game_over != null:
		game_over.visible = false
	_show_victory_panel()
	game_paused()


func _show_victory_panel() -> void:
	var panel := get_node_or_null("VictoryPanel") as CanvasItem
	if panel == null:
		# Fallback if panel missing from scene.
		$congratulations.visible = true
		$back.visible = true
		if not next_scene.is_empty():
			$next.visible = true
		return
	# Dim the rest of the HUD so only the dessert panel reads clearly.
	for child in get_children():
		if child is CanvasItem and child != panel:
			(child as CanvasItem).visible = false
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	# Panel copy comes from the scene (do not override text in code).
	var next_btn := panel.find_child("NextLevelButton", true, false) as Button
	if next_btn != null:
		next_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		# Zen: reuse Next as recreate; otherwise hide when no next scene.
		if is_zen_mode:
			next_btn.visible = true
		else:
			next_btn.visible = not next_scene.is_empty()
	for btn_name in ["RestartButton", "QuitButton"]:
		var btn := panel.find_child(btn_name, true, false) as Button
		if btn != null:
			btn.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = true


func _on_victory_next_pressed() -> void:
	if is_zen_mode:
		_on_recreate_pressed()
		return
	_on_next_pressed()


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
	# 如果父节点有"重新生成"或"下一轮游戏"方法则调用，否则回退
	_on_recreate_pressed()


func _on_recreate_pressed() -> void:
	# 优先查找父节点上的 ZenUI（禅模式挂载点）
	var zen := get_parent().get_node_or_null("ZenUI")
	if zen != null and zen.has_method("_on_recreate_pressed"):
		zen._on_recreate_pressed()


func _on_size_menu_pressed(id: int) -> void:
	# MenuButton item selection handled by size menu callback
	var zen := get_parent().get_node_or_null("ZenUI")
	if zen == null or not zen.has_method("_generate_with_size"):
		return
	var size := 6 + id
	zen._generate_with_size(size)


func _on_help_button_pressed() -> void:
	# Always hide legacy help panel ? only show sci-fi HowToPlayLayer.
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
	var victory := get_node_or_null("VictoryPanel") as CanvasItem
	if victory != null:
		victory.visible = false
	var game_over := get_node_or_null("GameOverPanel") as CanvasItem
	if game_over != null:
		game_over.visible = false
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
	# 禅模式 reload 前先恢复运行，避免暂停状态残留
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	won = false

	# 禅模式：重置立方体 / 箱子 / 玩家到开局状态
	if is_zen_mode:
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

	# 非禅模式：直接重新加载当前场景
	tree.reload_current_scene()


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
	# Prefer next_scene mapping; fall back to current scene path.
	var key := ""
	match next_scene:
		"res://level1/main.tscn":
			key = "teach"
		"res://level2/main.tscn":
			key = "level1"
		"res://level3/main.tscn":
			key = "level2"
		"res://level4/main.tscn":
			key = "level3"
		"res://level5/main.tscn":
			key = "level4"
		"res://level6/main.tscn":
			key = "level5"
		_:
			var scene := get_tree().current_scene
			var path := ""
			if scene != null:
				path = scene.scene_file_path
			match path:
				"res://teach/main.tscn":
					key = "teach"
				"res://level1/main.tscn":
					key = "level1"
				"res://level2/main.tscn":
					key = "level2"
				"res://level3/main.tscn":
					key = "level3"
				"res://level4/main.tscn":
					key = "level4"
				"res://level5/main.tscn":
					key = "level5"
				"res://level6/main.tscn":
					key = "level6"
	if key.is_empty():
		return
	progress.mark_completed(key)


func _on_player_died() -> void:
	var game_over := get_node_or_null("GameOverPanel") as CanvasItem
	if game_over == null:
		return
	var victory := get_node_or_null("VictoryPanel") as CanvasItem
	if victory != null:
		victory.visible = false
	for child in get_children():
		if child is CanvasItem and child != game_over:
			(child as CanvasItem).visible = false
	game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	for btn in game_over.find_children("*", "Button", true, false):
		(btn as Button).process_mode = Node.PROCESS_MODE_ALWAYS
	game_over.visible = true
	get_tree().paused = true


func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	var level_root := get_parent()
	var scene_path: String = level_root.scene_file_path if level_root != null else ""
	if scene_path.is_empty():
		push_error("无法重新加载关卡：缺少 scene_file_path")
		return
	get_tree().change_scene_to_file(scene_path)


func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://MainMenu/control.tscn")

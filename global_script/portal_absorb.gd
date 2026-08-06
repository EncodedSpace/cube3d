extends Area3D


signal absorption_finished


# ==================================================
# 场景节点
# ==================================================

# 拖入平底锅漩涡中心的 AbsorbPoint。
# AbsorbPoint 的局部 Y 轴必须垂直离开锅面，
# 指向玩家所在的空间。
@export var absorb_point: Marker3D


# ==================================================
# 动画参数
# ==================================================

@export_group("开始吸入")

# 取消滚动后等待几个物理帧，
# 让 RollController 中尚未结束的协程安全退出。
@export_range(1, 5, 1)
var settle_physics_frames: int = 2


@export_group("漂浮到锅口")

# 主角距离锅口表面的高度。
@export_range(0.1, 2.0, 0.01)
var float_height: float = 0.55

# 主角漂浮到锅口上方时，与中心的距离。
@export_range(0.05, 1.0, 0.01)
var orbit_radius: float = 0.28

# 漂浮阶段持续时间。
@export_range(0.1, 2.0, 0.01)
var float_duration: float = 0.38

# 漂浮轨迹额外拱起的高度。
@export_range(0.0, 1.0, 0.01)
var floating_arc_height: float = 0.12


@export_group("螺旋吸入")

# 螺旋吸入阶段持续时间。
@export_range(0.1, 3.0, 0.01)
var suction_duration: float = 0.68

# 绕锅中心旋转的圈数。
@export_range(0.0, 3.0, 0.05)
var orbit_turns: float = 0.85

# 最后进入锅面以下的深度。
@export_range(0.0, 1.0, 0.01)
var sink_depth: float = 0.10

# 改变吸入方向。
@export var clockwise: bool = false

@onready var absorb_sfx: AudioStreamPlayer = (
	get_node_or_null("../AbsorbSfx")
	as AudioStreamPlayer
)

# ==================================================
# 运行状态
# ==================================================

var is_absorbing: bool = false

var _player: Node3D
var _original_visual: Node3D
var _absorb_visual: Node3D

var _original_visual_visible: bool = true

var _saved_player_physics_processing: bool = true
var _saved_player_input_processing: bool = true
var _saved_player_unhandled_input: bool = true
var _saved_player_unhandled_key_input: bool = true

var _active_tween: Tween


# ==================================================
# 初始化
# ==================================================

func _ready() -> void:
	add_to_group("exit_portal")

	var callback: Callable = Callable(
		self,
		"_on_body_entered"
	)

	if not body_entered.is_connected(callback):
		body_entered.connect(callback)

	if absorb_sfx == null:
		push_error(
			"portal_absorb.gd：没有找到同级节点 AbsorbSfx"
		)
	elif absorb_sfx.stream == null:
		push_error(
			"portal_absorb.gd：AbsorbSfx 没有设置音频文件"
		)


# ==================================================
# 检测玩家
# ==================================================

func _on_body_entered(body: Node3D) -> void:
	if is_absorbing:
		return

	if not body.is_in_group("player"):
		return

	if absorb_point == null:
		push_error(
			"portal_absorb.gd：没有绑定 AbsorbPoint"
		)
		return

	is_absorbing = true
	
	# 吸入动作开始时只播放一次。
	_play_absorb_sfx()

	# 进入吸入区域后立刻禁止大立方体继续翻转。
	get_tree().call_group(
		"cube_world",
		"set_portal_locked",
		true
	)

	# body_entered 信号执行期间不能直接修改 monitoring。
	set_deferred(
		"monitoring",
		false
	)

	# 等信号执行完毕后再开始吸入。
	call_deferred(
		"_begin_absorption",
		body
	)


# ==================================================
# 安全停止玩家
# ==================================================

func _begin_absorption(player: Node3D) -> void:
	if not is_instance_valid(player):
		_abort_absorption()
		return

	if not player.is_inside_tree():
		_abort_absorption()
		return

	_player = player

	_save_player_processing_state(player)

	# 先停止玩家速度。
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO

	# 立即取消正在进行的滚动和跳跃。
	_cancel_player_controllers(player)

	# 等待控制器里的物理协程安全退出。
	for _index in range(settle_physics_frames):
		await get_tree().physics_frame

		if not is_instance_valid(player):
			_abort_absorption()
			return

	# 停止玩家继续读取移动输入。
	_freeze_player_controls(player)

	_original_visual = (
		player.get_node_or_null(
			"Pivot/PlayerCube"
		) as Node3D
	)

	if _original_visual == null:
		push_error(
			"portal_absorb.gd：Player 中没有找到 "
			+ "Pivot/PlayerCube"
		)

		_abort_absorption()
		return

	_original_visual_visible = (
		_original_visual.visible
	)

	# 记录原视觉模型的世界坐标。
	var original_global_transform := (
		_original_visual.global_transform
	)

	# 复制视觉模型。
	# 后面的动画只操作复制体，不移动 CharacterBody3D。
	_absorb_visual = (
		_original_visual.duplicate()
		as Node3D
	)

	if _absorb_visual == null:
		push_error(
			"portal_absorb.gd：无法复制 PlayerCube"
		)

		_abort_absorption()
		return

	# 复制体的脚本全部停止运行，
	# 但外部 Tween 仍然可以修改它的 Transform。
	_absorb_visual.process_mode = (
		Node.PROCESS_MODE_DISABLED
	)

	# 挂到 AbsorbPoint 下，
	# 让所有动画都使用平底锅自身的局部方向。
	absorb_point.add_child(
		_absorb_visual
	)

	# 重新恢复原来的世界位置，
	# 避免更换父节点时发生跳动。
	_absorb_visual.global_transform = (
		original_global_transform
	)

	_disable_processing_recursive(
		_absorb_visual
	)

	# 隐藏原来的玩家视觉。
	# CharacterBody3D 和碰撞体仍然保留在物理空间中。
	_original_visual.visible = false

	await absorb_visual(
		_absorb_visual
	)

	if is_instance_valid(_absorb_visual):
		_absorb_visual.queue_free()

	_absorb_visual = null

	# 通知公共 UI 显示胜利界面。
	get_tree().call_group(
		"ui_ingame",
		"show_win_after_absorb"
	)

	# 保留信号，兼容已经手动连接的关卡。
	absorption_finished.emit()


func _cancel_player_controllers(
	player: Node3D
) -> void:
	var roll_controller := (
		player.get_node_or_null(
			"RollController"
		)
	)

	var jump_controller := (
		player.get_node_or_null(
			"JumpController"
		)
	)

	if (
		roll_controller != null
		and roll_controller.has_method("cancel")
	):
		roll_controller.call("cancel")

	if (
		jump_controller != null
		and jump_controller.has_method("cancel")
	):
		jump_controller.call("cancel")


func _freeze_player_controls(
	player: Node3D
) -> void:
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_process_unhandled_key_input(false)

	var roll_controller := (
		player.get_node_or_null(
			"RollController"
		)
	)

	var jump_controller := (
		player.get_node_or_null(
			"JumpController"
		)
	)

	for controller in [
		roll_controller,
		jump_controller
	]:
		if controller == null:
			continue

		controller.set_process(false)
		controller.set_physics_process(false)
		controller.set_process_input(false)
		controller.set_process_unhandled_input(false)
		controller.set_process_unhandled_key_input(false)


func _disable_processing_recursive(
	node: Node
) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)

	for child in node.get_children():
		_disable_processing_recursive(child)


# ==================================================
# 吸入动画
# ==================================================

func absorb_visual(visual: Node3D) -> void:
	var start_position: Vector3 = visual.position
	var start_scale: Vector3 = visual.scale

	var start_angle: float = atan2(
		start_position.z,
		start_position.x
	)

	var hover_position: Vector3 = Vector3(
		cos(start_angle) * orbit_radius,
		float_height,
		sin(start_angle) * orbit_radius
	)

	# 第一阶段：漂浮到锅口上方
	var float_tween: Tween = create_tween()

	float_tween.set_trans(Tween.TRANS_SINE)
	float_tween.set_ease(Tween.EASE_IN_OUT)

	float_tween.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(visual):
				return

			var smooth_t: float = smoothstep(
				0.0,
				1.0,
				t
			)

			var current_position: Vector3 = (
				start_position.lerp(
					hover_position,
					smooth_t
				)
			)

			current_position.y += (
				sin(t * PI) * 0.16
			)

			visual.position = current_position

			var pulse: float = (
				sin(t * PI) * 0.08
			)

			visual.scale = start_scale * Vector3(
				1.0 - pulse,
				1.0 + pulse,
				1.0 - pulse
			),
		0.0,
		1.0,
		float_duration
	)

	await float_tween.finished

	if not is_instance_valid(visual):
		return

	await get_tree().create_timer(0.10).timeout

	if not is_instance_valid(visual):
		return

	# 第二阶段：龙卷风式螺旋吸入
	var direction: float = (
		-1.0 if clockwise else 1.0
	)

	var suction_tween: Tween = create_tween()
	suction_tween.set_trans(Tween.TRANS_LINEAR)

	suction_tween.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(visual):
				return

			var angle: float = (
				start_angle
				+ TAU
				* orbit_turns
				* t
				* direction
			)

			var radius_t: float = pow(
				t,
				1.55
			)

			var current_radius: float = lerp(
				orbit_radius,
				0.0,
				radius_t
			)

			var drop_t: float = smoothstep(
				0.18,
				1.0,
				t
			)

			var drop_curve: float = pow(
				drop_t,
				1.45
			)

			var current_height: float = lerp(
				float_height,
				-sink_depth,
				drop_curve
			)

			visual.position = Vector3(
				cos(angle) * current_radius,
				current_height,
				sin(angle) * current_radius
			)

			var shrink_t: float = smoothstep(
				0.58,
				1.0,
				t
			)

			var shrink_curve: float = pow(
				shrink_t,
				1.8
			)

			var scale_factor: float = lerp(
				1.0,
				0.015,
				shrink_curve
			)

			visual.scale = (
				start_scale * scale_factor
			),
		0.0,
		1.0,
		suction_duration
	)

	await suction_tween.finished

	if is_instance_valid(visual):
		visual.visible = false


# ==================================================
# 重置
# ==================================================

func _save_player_processing_state(
	player: Node3D
) -> void:
	_saved_player_physics_processing = (
		player.is_physics_processing()
	)

	_saved_player_input_processing = (
		player.is_processing_input()
	)

	_saved_player_unhandled_input = (
		player.is_processing_unhandled_input()
	)

	_saved_player_unhandled_key_input = (
		player.is_processing_unhandled_key_input()
	)


func reset_portal() -> void:
	if (
		_active_tween != null
		and _active_tween.is_valid()
	):
		_active_tween.kill()

	_active_tween = null

	if is_instance_valid(_absorb_visual):
		_absorb_visual.queue_free()

	_absorb_visual = null

	if is_instance_valid(_original_visual):
		_original_visual.visible = (
			_original_visual_visible
		)

	if is_instance_valid(_player):
		_player.set_physics_process(
			_saved_player_physics_processing
		)

		_player.set_process_input(
			_saved_player_input_processing
		)

		_player.set_process_unhandled_input(
			_saved_player_unhandled_input
		)

		_player.set_process_unhandled_key_input(
			_saved_player_unhandled_key_input
		)

		var roll_controller := (
			_player.get_node_or_null(
				"RollController"
			)
		)

		var jump_controller := (
			_player.get_node_or_null(
				"JumpController"
			)
		)

		for controller in [
			roll_controller,
			jump_controller
		]:
			if controller == null:
				continue

			controller.set_process(true)
			controller.set_physics_process(true)
			controller.set_process_input(true)
			controller.set_process_unhandled_input(true)
			controller.set_process_unhandled_key_input(true)

	is_absorbing = false

	get_tree().call_group(
		"cube_world",
		"set_portal_locked",
		false
	)

	_player = null
	_original_visual = null

	await get_tree().process_frame

	if not is_inside_tree():
		return

	set_deferred(
		"monitoring",
		true
	)


func _abort_absorption() -> void:
	is_absorbing = false

	get_tree().call_group(
		"cube_world",
		"set_portal_locked",
		false
	)

	set_deferred(
		"monitoring",
		true
	)

func _play_absorb_sfx() -> void:
	if absorb_sfx == null:
		push_warning("出口场景没有找到 AbsorbSfx")
		return

	if absorb_sfx.stream == null:
		push_warning("AbsorbSfx 没有设置吸入音效")
		return

	absorb_sfx.play()

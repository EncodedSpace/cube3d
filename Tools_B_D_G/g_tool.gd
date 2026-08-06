extends AnimatableBody3D

## 披萨盒机关：
## - 披萨进入检测范围后，不再瞬移
## - 而是将披萨视觉模型平滑漂浮到 PizzaSnapPoint
## - 到位后持续进行小幅上下漂浮
## - 原物理刚体会被删除，避免后续翻转时漂移
## - 漂浮完成后触发 B_Tool 和 g_collected 信号


signal g_collected


@export_category("触发对象")

## 同组中的 B_Tool。
@export var b_tool_path: NodePath = ^"../B_Tool"

## 披萨刚体名称需要包含的文字。
@export var collector_name_filter: String = "MovableBox_C"

## 检测披萨使用的物理层。
@export_flags_3d_physics var detection_collision_mask: int = 0xFFFFFFFF


@export_category("检测范围")

## 披萨盒内部检测区域的尺寸。
@export var detection_size: Vector3 = Vector3(1.0, 1.0, 1.0)

## 检测区域相对于 G_Tool 原点的位置。
@export var detection_offset: Vector3 = Vector3.ZERO


@export_category("披萨固定")

## 披萨最终固定点。
@export var pizza_snap_point_path: NodePath = ^"PizzaSnapPoint"

## MovableBox_C 内部真正的披萨视觉节点。
@export var pizza_visual_path: NodePath = ^"Pizza Slice"

## 固定后关闭原披萨刚体的碰撞。
@export var disable_pizza_collision: bool = true


@export_category("吸入动画")

## 漂浮吸入总时长。
@export var capture_move_duration: float = 0.38

## 漂浮过程中先轻微上扬，再落入盒中。
@export var capture_arc_height: float = 0.16

## 吸入完成后是否再触发机关。
## 一般建议保持 true，让视觉先完成。
@export var trigger_after_capture_animation: bool = true


@export_category("盒内悬浮")

## 盒内上下浮动高度。
@export var idle_float_height: float = 0.05

## 单次上浮/下浮时长。
@export var idle_float_duration: float = 0.9

## 是否启用盒内持续悬浮动画。
@export var enable_idle_float: bool = true


var _collected := false
var _detection_area: Area3D
var _snap_point: Node3D
var _captured_visual: Node3D

var _capture_tween: Tween
var _idle_tween: Tween


func _ready() -> void:
	# G_Tool 已经是旋转大立方体的子节点。
	# 不需要再进行额外的物理同步，否则可能造成位置修正。
	sync_to_physics = false
	top_level = false

	_snap_point = _resolve_snap_point()

	if _snap_point == null:
		push_warning(
			"G_Tool：没有找到 PizzaSnapPoint，请检查场景节点名称"
		)

	_setup_detection_area()

	# 处理开局时披萨已经与检测区重叠的情况。
	call_deferred("_check_initial_overlaps")


func _setup_detection_area() -> void:
	_detection_area = get_node_or_null("DetectionArea") as Area3D

	if _detection_area == null:
		_detection_area = Area3D.new()
		_detection_area.name = "DetectionArea"
		add_child(_detection_area)

	_detection_area.position = detection_offset
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = detection_collision_mask
	_detection_area.monitoring = true
	_detection_area.monitorable = false

	var collision_shape := _detection_area.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D

	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		_detection_area.add_child(collision_shape)

	var box_shape := collision_shape.shape as BoxShape3D

	if box_shape == null:
		box_shape = BoxShape3D.new()
		collision_shape.shape = box_shape

	box_shape.size = detection_size

	if not _detection_area.body_entered.is_connected(_on_body_entered):
		_detection_area.body_entered.connect(_on_body_entered)


func _resolve_snap_point() -> Node3D:
	if not pizza_snap_point_path.is_empty():
		var from_path := get_node_or_null(pizza_snap_point_path) as Node3D
		if from_path != null:
			return from_path

	return get_node_or_null("PizzaSnapPoint") as Node3D


func _is_pizza(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false

	if not body is RigidBody3D:
		return false

	if collector_name_filter.is_empty():
		return true

	return collector_name_filter in String(body.name)


func _check_initial_overlaps() -> void:
	if _collected:
		return

	if _detection_area == null or not is_instance_valid(_detection_area):
		return

	for body in _detection_area.get_overlapping_bodies():
		if _is_pizza(body):
			_begin_capture(body as RigidBody3D)
			return


func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return

	if not _is_pizza(body):
		return

	_begin_capture(body as RigidBody3D)


func _begin_capture(pizza: RigidBody3D) -> void:
	if _collected:
		return

	if pizza == null or not is_instance_valid(pizza):
		return

	_collected = true
	set_physics_process(false)

	if _detection_area != null:
		_detection_area.set_deferred("monitoring", false)

	call_deferred("_finish_capture", pizza)


func _finish_capture(pizza: RigidBody3D) -> void:
	if pizza == null or not is_instance_valid(pizza):
		_reset_failed_capture()
		return

	_snap_point = _resolve_snap_point()

	if _snap_point == null:
		push_warning("G_Tool：披萨已经进入检测区，但找不到 PizzaSnapPoint")
		_reset_failed_capture()
		return

	var pizza_visual := _resolve_pizza_visual(pizza)

	if pizza_visual == null:
		push_warning("G_Tool：找不到披萨视觉节点，请检查 Pizza Visual Path")
		_reset_failed_capture()
		return

	# 停止原披萨刚体。
	pizza.linear_velocity = Vector3.ZERO
	pizza.angular_velocity = Vector3.ZERO
	pizza.gravity_scale = 0.0
	pizza.freeze = true
	pizza.sleeping = true

	if disable_pizza_collision:
		pizza.collision_layer = 0
		pizza.collision_mask = 0
		_disable_collision_shapes(pizza)

	# 记录原始缩放，防止重挂后缩放异常。
	var original_scale := pizza_visual.scale

	# 将“披萨视觉模型”重挂到 PizzaSnapPoint 下，
	# 但保留当前的全局位置，这样才能从当前位置平滑飞入。
	pizza_visual.reparent(_snap_point, true)
	pizza_visual.scale = original_scale
	pizza_visual.name = "CapturedPizza"

	_captured_visual = pizza_visual

	# 原物理刚体删除，避免后续翻转时位置漂移。
	pizza.queue_free()

	# 开始吸入动画。
	_start_capture_animation()

	# 如果不想等动画结束再触发，可以在这里触发。
	if not trigger_after_capture_animation:
		_trigger_b_tool()
		g_collected.emit()


func _start_capture_animation() -> void:
	if _captured_visual == null or not is_instance_valid(_captured_visual):
		return

	if _capture_tween != null and _capture_tween.is_valid():
		_capture_tween.kill()

	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()

	var start_local_pos := _captured_visual.position
	var mid_local_pos := start_local_pos + Vector3.UP * capture_arc_height

	_capture_tween = create_tween()
	_capture_tween.set_trans(Tween.TRANS_QUAD)
	_capture_tween.set_ease(Tween.EASE_OUT)

	# 第一段：轻微上浮，产生被吸走前的漂浮感。
	_capture_tween.tween_property(
		_captured_visual,
		"position",
		mid_local_pos,
		capture_move_duration * 0.35
	)

	# 第二段：漂浮进入盒子固定点。
	_capture_tween.set_trans(Tween.TRANS_CUBIC)
	_capture_tween.set_ease(Tween.EASE_IN_OUT)

	_capture_tween.tween_property(
		_captured_visual,
		"position",
		Vector3.ZERO,
		capture_move_duration * 0.65
	)

	# 同时缓慢归正角度。
	_capture_tween.parallel().tween_property(
		_captured_visual,
		"rotation",
		Vector3.ZERO,
		capture_move_duration
	)

	_capture_tween.tween_callback(_on_capture_animation_finished)


func _on_capture_animation_finished() -> void:
	if _captured_visual == null or not is_instance_valid(_captured_visual):
		return

	_captured_visual.position = Vector3.ZERO
	_captured_visual.rotation = Vector3.ZERO

	if enable_idle_float:
		_start_idle_float()

	if trigger_after_capture_animation:
		_trigger_b_tool()
		g_collected.emit()


func _start_idle_float() -> void:
	if _captured_visual == null or not is_instance_valid(_captured_visual):
		return

	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()

	_idle_tween = create_tween()
	_idle_tween.set_loops()

	_idle_tween.set_trans(Tween.TRANS_SINE)
	_idle_tween.set_ease(Tween.EASE_IN_OUT)

	_idle_tween.tween_property(
		_captured_visual,
		"position:y",
		idle_float_height,
		idle_float_duration
	)

	_idle_tween.tween_property(
		_captured_visual,
		"position:y",
		0.0,
		idle_float_duration
	)


func _resolve_pizza_visual(pizza: RigidBody3D) -> Node3D:
	if not pizza_visual_path.is_empty():
		var from_path := pizza.get_node_or_null(pizza_visual_path) as Node3D
		if from_path != null:
			return from_path

	var named_visual := pizza.get_node_or_null("Pizza Slice") as Node3D
	if named_visual != null:
		return named_visual

	for child in pizza.get_children():
		if child is CollisionShape3D:
			continue
		if child is Node3D:
			return child as Node3D

	return null


func _reset_failed_capture() -> void:
	_collected = false

	if _detection_area != null:
		_detection_area.set_deferred("monitoring", true)


func _trigger_b_tool() -> void:
	var b_tool := _resolve_b_tool()

	if b_tool == null:
		push_warning("G_Tool：没有找到 B_Tool，后续机关无法触发")
		return

	if b_tool.has_method("enable_gravity"):
		b_tool.enable_gravity()
	else:
		push_warning("G_Tool：找到 B_Tool，但它没有 enable_gravity() 方法")


func _resolve_b_tool() -> Node:
	if not b_tool_path.is_empty():
		var from_path := get_node_or_null(b_tool_path)
		if from_path != null:
			return from_path

	var parent := get_parent()
	if parent != null:
		return parent.get_node_or_null("B_Tool")

	return null


func _disable_collision_shapes(root: Node) -> void:
	for child in root.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", true)

		_disable_collision_shapes(child)


## 供外部存档/复原流程调用。
func restore_after_g_collected() -> void:
	_collected = true

	if _detection_area != null:
		_detection_area.set_deferred("monitoring", false)

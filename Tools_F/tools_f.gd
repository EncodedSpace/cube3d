@tool
extends Node3D

## F 道具：1×1×1 触发立方体（节点名 F_Trigger，随附着墙面裁切显隐）。
## 玩家重合时：先复原 Tool_B_D_G 到「G 已收集」，再把 A/B 当前位置对调。
## 若 MovableBox 会换到某扇 D 上：D 先保持开门，箱子沿 -Y 滑出后再关门。


@export var trigger_position := Vector3(0.0, 0.5, 0.0)

## 要交换的两个物体。在 level2 场景树里，可直接拖节点过来。
@export var object_a: Node3D
@export var object_b: Node3D

## 可选：直接指定 Tool_B_D_G 根节点；留空则从 object_a/b 或同级自动查找。
@export var tools_bdg: Node3D

## 只触发一次；关闭则可反复交换。
@export var trigger_once := true

## 判定与 D「重叠」的距离。
@export var d_overlap_distance := 0.85
## 箱子从 D 滑到邻格的时长。
@export var slide_duration := 0.45


@onready var trigger: Area3D = $F_Trigger

var _triggered := false
var _slide_tween: Tween


func _ready() -> void:
	_apply_position()
	if Engine.is_editor_hint():
		set_process(true)
		return

	if trigger:
		trigger.monitoring = true
		trigger.monitorable = false
		trigger.collision_layer = 0
		trigger.collision_mask = 1
		if not trigger.body_entered.is_connected(_on_body_entered):
			trigger.body_entered.connect(_on_body_entered)
		call_deferred("_check_initial_overlaps")
	set_process(false)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_position()


func _apply_position() -> void:
	if trigger:
		trigger.position = trigger_position


func _check_initial_overlaps() -> void:
	if trigger == null or not is_instance_valid(trigger):
		return
	for body in trigger.get_overlapping_bodies():
		if body.is_in_group("player"):
			_try_swap()
			return


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_try_swap()


func _try_swap() -> void:
	if trigger_once and _triggered:
		return

	if object_a == null or object_b == null or not is_instance_valid(object_a) or not is_instance_valid(object_b):
		push_warning("Tools_F: object_a / object_b 未设置或无效，无法交换")
		return

	_triggered = true

	var ta := object_a.global_transform
	var tb := object_b.global_transform

	var bdg := _resolve_tools_bdg()
	var b_tool := _find_b_tool(bdg)
	# B 当前所在的 D：换位后 MovableBox 会落到这里 → 先别关门。
	var keep_open: Array[Node3D] = []
	if b_tool != null and bdg != null and bdg.has_method("get_all_d_walls"):
		for d in bdg.get_all_d_walls():
			if d != null and is_instance_valid(d) and b_tool.global_position.distance_to(d.global_position) < d_overlap_distance:
				keep_open.append(d as Node3D)

	if bdg != null and bdg.has_method("restore_after_g_collected"):
		bdg.restore_after_g_collected(true, keep_open)

	object_a.global_transform = tb
	object_b.global_transform = ta

	# B 开重力。
	for n in [object_a, object_b]:
		if n != null and n.is_in_group("b_tool") and n.has_method("enable_gravity"):
			n.enable_gravity()

	# 换位后连补几帧：避免 B 落在 D 顶面时 Area 擦边漏检。
	if bdg != null and bdg.has_method("check_all_d_b_overlaps"):
		_recheck_d_overlaps(bdg)

	var cube := _find_cube_world()
	if cube != null and cube.has_method("update_cutaway_visibility"):
		cube.call_deferred("update_cutaway_visibility")

	var box := _find_movable_box()
	if box != null and not keep_open.is_empty():
		_slide_box_off_d(box, keep_open)
	elif box != null:
		_enable_movable_gravity(box)


func _recheck_d_overlaps(bdg: Node) -> void:
	for _i in range(8):
		if bdg == null or not is_instance_valid(bdg):
			return
		if bdg.has_method("check_all_d_b_overlaps"):
			bdg.check_all_d_b_overlaps()
		await get_tree().physics_frame


func _slide_box_off_d(box: RigidBody3D, walls: Array[Node3D]) -> void:
	var d := _nearest_wall(box.global_position, walls)
	if d == null:
		_enable_movable_gravity(box)
		_close_walls(walls)
		return

	# 沿世界 -Y 滑出一格，再关门。
	var target := box.global_position + Vector3.DOWN * 1.0

	# 冻结后缓动滑出，避免重力穿洞 / 物理弹飞。
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	box.gravity_scale = 0.0
	box.freeze = true
	box.sleeping = true

	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()

	_slide_tween = create_tween()
	_slide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(box, "global_position", target, slide_duration)
	_slide_tween.finished.connect(func() -> void:
		if is_instance_valid(box):
			box.global_position = target
			_enable_movable_gravity(box)
		_close_walls(walls)
		var cube := _find_cube_world()
		if cube != null and cube.has_method("update_cutaway_visibility"):
			cube.update_cutaway_visibility()
	)


func _nearest_wall(pos: Vector3, walls: Array[Node3D]) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for d in walls:
		if d == null or not is_instance_valid(d):
			continue
		var dist := pos.distance_to(d.global_position)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _close_walls(walls: Array[Node3D]) -> void:
	for d in walls:
		if d != null and is_instance_valid(d) and d.has_method("restore_after_g_collected"):
			d.restore_after_g_collected()


func _find_b_tool(bdg: Node) -> Node3D:
	if bdg != null:
		var from_bdg := bdg.get_node_or_null("B_Tool") as Node3D
		if from_bdg != null:
			return from_bdg
	for n in [object_a, object_b]:
		if n != null and n.is_in_group("b_tool"):
			return n
	return null


func _find_movable_box() -> RigidBody3D:
	for n in [object_a, object_b]:
		if n is RigidBody3D and "MovableBox" in String(n.name):
			return n as RigidBody3D
	for n in [object_a, object_b]:
		if n is RigidBody3D and not n.is_in_group("b_tool"):
			return n as RigidBody3D
	return null


func _enable_movable_gravity(node: Node3D) -> void:
	if node == null or not (node is RigidBody3D):
		return
	if node.is_in_group("b_tool"):
		return
	var rb := node as RigidBody3D
	rb.gravity_scale = 1.0
	rb.freeze = false
	rb.sleeping = false
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO


func _resolve_tools_bdg() -> Node:
	if tools_bdg != null and is_instance_valid(tools_bdg):
		return tools_bdg

	for n in [object_a, object_b]:
		if n == null or not is_instance_valid(n):
			continue
		var p: Node = n.get_parent()
		while p != null:
			if p.has_method("restore_after_g_collected"):
				return p
			p = p.get_parent()

	var parent := get_parent()
	if parent != null:
		var sibling := parent.get_node_or_null("Tool_B_D_G")
		if sibling != null and sibling.has_method("restore_after_g_collected"):
			return sibling
	return null


func _find_cube_world() -> Node:
	var n: Node = self
	while n != null:
		if n.has_method("update_cutaway_visibility"):
			return n
		n = n.get_parent()
	return null

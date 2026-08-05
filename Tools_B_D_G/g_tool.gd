extends RigidBody3D

## G 道具：当 MovableBox_C 完全进入 G 所在方格时被收集。
## 不用一碰到就触发，避免「磁吸」感。
## 收集后通知 B 开启重力，并让 G 消失。


signal g_collected

## 默认指向同组里的 B_Tool；也可在检查器里手动指定。
@export var b_tool_path: NodePath = ^"../B_Tool"

## 触发收集的刚体名字需包含该字符串（默认 MovableBox_C）。
@export var collector_name_filter := "MovableBox_C"
## 水平方向中心距上限（米）；箱子中心需足够靠近 G 格心。
@export var activate_lateral_max := 0.35
## 竖直方向中心距上限（米）。
@export var activate_vertical_max := 0.35
## 速度上限；仍在快速滑入时不激活。
@export var activate_speed_max := 1.2

var _collected := false
var _area: Area3D


func _ready() -> void:
	gravity_scale = 0.0
	freeze = true
	# 不挡箱子：箱子要能推进到同一格。
	collision_layer = 0
	collision_mask = 0
	_set_own_solid_disabled(true)

	_area = Area3D.new()
	_area.name = "DetectionArea"
	_area.collision_layer = 0
	# Layer 1：默认 MovableBox / 玩家所在层。
	_area.collision_mask = 1
	_area.monitoring = true
	_area.monitorable = false

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# 略大于 1，粗检测；真正收集看 _is_fully_on_g。
	box.size = Vector3(1.05, 1.05, 1.05)
	col_shape.shape = box
	_area.add_child(col_shape)
	add_child(_area)

	set_physics_process(true)
	call_deferred("_check_overlaps")


func _physics_process(_delta: float) -> void:
	if _collected:
		return
	_check_overlaps()


func _resolve_b_tool() -> RigidBody3D:
	if not b_tool_path.is_empty():
		var from_path := get_node_or_null(b_tool_path)
		if from_path is RigidBody3D:
			return from_path as RigidBody3D
	var parent := get_parent()
	if parent != null:
		return parent.get_node_or_null("B_Tool") as RigidBody3D
	return null


func _is_collector(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body is RigidBody3D and collector_name_filter in String(body.name):
		return true
	return false


func _check_overlaps() -> void:
	if _collected or _area == null or not is_instance_valid(_area):
		return
	for body in _area.get_overlapping_bodies():
		if not _is_collector(body):
			continue
		var box := body as RigidBody3D
		if _is_fully_on_g(box):
			_collect()
			return


## 箱子碰撞中心已贴近 G 且基本停稳，才算完全到达该格。
## 不用 RigidBody 原点：部分关卡 CollisionShape 有偏移（如 level5）。
func _is_fully_on_g(box: RigidBody3D) -> bool:
	if box == null or not is_instance_valid(box):
		return false
	var box_pos := _collision_center(box)
	var offset := box_pos - global_position
	var along_up := offset.dot(Vector3.UP)
	var lateral := offset - Vector3.UP * along_up
	if lateral.length() > activate_lateral_max:
		return false
	if absf(along_up) > activate_vertical_max:
		return false
	if box.linear_velocity.length() > activate_speed_max:
		return false
	return true


func _collision_center(body: Node3D) -> Vector3:
	for child in body.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return (child as CollisionShape3D).global_position
	return body.global_position


func _set_own_solid_disabled(disabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = disabled


func _collect() -> void:
	if _collected:
		return
	_collected = true
	set_physics_process(false)
	if _area != null:
		_area.monitoring = false

	var b_tool := _resolve_b_tool()
	if b_tool and b_tool.has_method("enable_gravity"):
		b_tool.enable_gravity()
	else:
		push_warning("G_Tool: could not find B_Tool to enable gravity")

	g_collected.emit()
	queue_free()

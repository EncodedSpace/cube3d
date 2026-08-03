extends RigidBody3D

## G 道具：当 MovableBox_C 与 G 重合（进入检测范围）时被收集。
## 收集后通知 B 开启重力，并让 G 消失。


signal g_collected

## 默认指向同组里的 B_Tool；也可在检查器里手动指定。
@export var b_tool_path: NodePath = ^"../B_Tool"

## 触发收集的刚体名字需包含该字符串（默认 MovableBox_C）。
@export var collector_name_filter := "MovableBox_C"

var _collected := false


func _ready() -> void:
	gravity_scale = 0.0
	freeze = true

	# Area 检测可动物体；不依赖玩家。
	var area := Area3D.new()
	area.name = "DetectionArea"
	area.collision_layer = 0
	# Layer 1：默认 MovableBox / 玩家所在层。
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	col_shape.shape = box
	area.add_child(col_shape)
	add_child(area)

	area.body_entered.connect(_on_body_entered)

	# 若开局已重合，下一帧补检一次。
	call_deferred("_check_initial_overlaps", area)


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


func _check_initial_overlaps(area: Area3D) -> void:
	if _collected or area == null or not is_instance_valid(area):
		return
	for body in area.get_overlapping_bodies():
		if _is_collector(body):
			_collect()
			return


func _on_body_entered(body: Node3D) -> void:
	if not _is_collector(body):
		return
	_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true

	var b_tool := _resolve_b_tool()
	if b_tool and b_tool.has_method("enable_gravity"):
		b_tool.enable_gravity()
	else:
		push_warning("G_Tool: could not find B_Tool to enable gravity")

	g_collected.emit()
	queue_free()

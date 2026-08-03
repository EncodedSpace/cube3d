extends RigidBody3D

## G 道具：被玩家吃到后消失，并通知 B 道具开启重力。
## 使用 Area3D 子节点检测玩家，避免 freeze 导致的接触监测失效。


signal g_collected

## 默认指向同组里的 B_Tool；也可在检查器里手动指定。
@export var b_tool_path: NodePath = ^"../B_Tool"


func _ready() -> void:
	gravity_scale = 0.0
	freeze = true

	# 创建一个 Area3D 子节点专门检测玩家碰撞。
	var area := Area3D.new()
	area.name = "DetectionArea"
	area.collision_layer = 0
	area.collision_mask = 3  # 检测 layer 1（Player）和 layer 2
	area.monitoring = true
	area.monitorable = false

	var col_shape := CollisionShape3D.new()
	col_shape.shape = BoxShape3D.new()
	col_shape.shape.size = Vector3(1.0, 1.0, 1.0)
	area.add_child(col_shape)
	add_child(area)

	area.body_entered.connect(_on_body_entered)


func _resolve_b_tool() -> RigidBody3D:
	if not b_tool_path.is_empty():
		var from_path := get_node_or_null(b_tool_path)
		if from_path is RigidBody3D:
			return from_path as RigidBody3D
	var parent := get_parent()
	if parent != null:
		return parent.get_node_or_null("B_Tool") as RigidBody3D
	return null


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	var b_tool := _resolve_b_tool()
	if b_tool and b_tool.has_method("enable_gravity"):
		b_tool.enable_gravity()
	else:
		push_warning("G_Tool: could not find B_Tool to enable gravity")

	g_collected.emit()
	queue_free()

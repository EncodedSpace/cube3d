extends Area3D

## 终局钥匙：直径 0.5 圆球。玩家碰到后消失，并激活终点大门。
## 裁切显隐与其它道具统一：等距多面绑定后，由 cube_world 调用
## apply_cutaway_visibility；任一面亮起则可见。


var tools_root: Node3D
var _collected := false


func setup(root: Node3D) -> void:
	tools_root = root
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	call_deferred("_check_initial_overlaps")


## 由 cube_world 裁切刷新调用：跟绑定墙显隐。
func apply_cutaway_visibility(wall_visible: bool) -> void:
	if _collected:
		return
	visible = wall_visible
	monitoring = wall_visible
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not wall_visible


func _check_initial_overlaps() -> void:
	if _collected or not monitoring:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_collect()
			return


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true

	if tools_root != null and tools_root.has_method("unlock_exit"):
		tools_root.unlock_exit()

	queue_free()

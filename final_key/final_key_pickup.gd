extends Area3D

## 终局钥匙：直径 0.5 圆球。玩家碰到后消失，并激活终点大门。


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


func _check_initial_overlaps() -> void:
	if _collected:
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

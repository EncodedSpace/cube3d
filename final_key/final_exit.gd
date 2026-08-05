extends Area3D

## 终点大门：1×1×1 检测区。钥匙激活后，玩家进入即通关。
## 裁切显隐与其它道具统一：等距多面绑定后，由 cube_world 调用
## apply_cutaway_visibility；任一面亮起则可见。


var tools_root: Node3D
var _active := false


func setup(root: Node3D) -> void:
	tools_root = root
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	set_active(false)
	call_deferred("_check_initial_overlaps")


## 由 cube_world 裁切刷新调用：跟绑定墙显隐。
func apply_cutaway_visibility(wall_visible: bool) -> void:
	visible = wall_visible
	# 未激活时本来就不能通关；激活后隐藏时也不应误触。
	monitoring = wall_visible and _active
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not wall_visible


func set_active(active: bool) -> void:
	_active = active
	set_active_look(active)
	# 保持与当前裁切显隐一致。
	if visible:
		monitoring = active
	call_deferred("_check_initial_overlaps")


func set_active_look(active: bool) -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return
	var mat := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if mat == null:
		mat = mesh.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	mat.emission_energy_multiplier = 2.4 if active else 0.6
	var c := mat.albedo_color
	c.a = 0.85 if active else 0.55
	mat.albedo_color = c


func _check_initial_overlaps() -> void:
	if not _active or not monitoring:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_try_win(body)
			return


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_try_win(body)


func _try_win(player: Node3D) -> void:
	if not _active:
		return
	if tools_root != null and tools_root.has_method("trigger_win"):
		tools_root.trigger_win(player)

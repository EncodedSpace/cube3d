extends Area3D

## 终点大门：1×1×1 检测区。钥匙激活后，玩家进入即通关。


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


func set_active(active: bool) -> void:
	_active = active
	set_active_look(active)


func set_active_look(active: bool) -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return
	var mat := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if mat == null:
		mat = mesh.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	mat.emission_energy_multiplier = 2.0 if active else 0.3
	var c := mat.albedo_color
	c.a = 0.55 if active else 0.2
	mat.albedo_color = c


func _check_initial_overlaps() -> void:
	if not _active:
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

extends Area3D

## 单扇传送门：1×1×1 检测体。
## 玩家进入后，由根节点传送到配对门（需先收集钥匙）。


var tools_root: Node3D
var exit_portal: Area3D


func setup(root: Node3D, other: Area3D) -> void:
	tools_root = root
	exit_portal = other
	monitoring = true
	monitorable = false
	# 检测默认层上的 Player（CharacterBody3D）。
	collision_layer = 0
	collision_mask = 1

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func set_active_look(active: bool) -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return
	var mat := mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if mat == null:
		mat = mesh.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	# 未解锁：更暗更淡；解锁后恢复高亮。
	mat.emission_energy_multiplier = 1.5 if active else 0.35
	var c := mat.albedo_color
	c.a = 0.45 if active else 0.18
	mat.albedo_color = c


func _on_body_entered(body: Node3D) -> void:
	if tools_root == null or exit_portal == null:
		return
	if not body.is_in_group("player"):
		return
	if not tools_root.has_method("teleport_player"):
		return
	tools_root.teleport_player(body, exit_portal)

extends Area3D

## 单扇传送门：1×1×1 检测体。
## 玩家进入后，由根节点传送到配对门（需先收集钥匙）。
## 裁切显隐与其它道具统一：等距多面绑定后，由 cube_world 调用
## apply_cutaway_visibility；任一面亮起则可见。


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


## 由 cube_world 裁切刷新调用：跟绑定墙显隐。
func apply_cutaway_visibility(wall_visible: bool) -> void:
	visible = wall_visible
	monitoring = wall_visible
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not wall_visible


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
	mat.emission_energy_multiplier = 2.0 if active else 0.6
	var c := mat.albedo_color
	c.a = 0.75 if active else 0.4
	mat.albedo_color = c


func _on_body_entered(body: Node3D) -> void:
	if tools_root == null or exit_portal == null:
		return
	if not body.is_in_group("player"):
		return
	if not tools_root.has_method("teleport_player"):
		return
	tools_root.teleport_player(body, exit_portal)

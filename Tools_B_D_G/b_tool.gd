extends RigidBody3D

## B 道具：玩家可自由进出。
## 初始冻结；G 被收集后启用真实物理重力，并与 WALLS 碰撞。
## 落入 D 空间后被吸附，不再移动。
## 裁切显隐与其它道具统一：等距多面绑定后，由 cube_world 调用
## apply_cutaway_visibility；任一面亮起则可见。


var gravity_enabled := false
var adsorbed := false


func _ready() -> void:
	gravity_scale = 0.0
	freeze = true
	# Layer 4: D_Wall Area 可检测；Mask 1: 与 WALLS（默认 layer 1）碰撞。
	collision_layer = 4
	collision_mask = 1
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 4
	add_to_group("b_tool")


## 由 cube_world 裁切刷新调用：跟绑定墙显隐（与 Portal / StaticBox 等一致）。
func apply_cutaway_visibility(wall_visible: bool) -> void:
	visible = wall_visible

	# 下落中必须保持与墙的碰撞，否则会掉出立方体。
	if gravity_enabled and not adsorbed:
		_set_collision_shapes_disabled(false)
		var hold := _is_cube_holding_fallables()
		if hold:
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			freeze = true
		elif get_tree() != null and not get_tree().paused:
			freeze = false
		return

	# 静止 / 吸附：隐藏时关掉碰撞，与其它道具一致。
	_set_collision_shapes_disabled(not wall_visible)


func _set_collision_shapes_disabled(disabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = disabled


func _is_cube_holding_fallables() -> bool:
	var cube := _find_cube_world()
	if cube == null:
		return false
	return bool(cube.get("_hold_props_frozen"))


func _find_cube_world() -> Node:
	var n: Node = self
	while n != null:
		if n.has_method("update_cutaway_visibility"):
			return n
		n = n.get_parent()
	return null


## 由 G 道具调用，开启重力。
func enable_gravity() -> void:
	if adsorbed:
		return
	gravity_enabled = true
	gravity_scale = 1.0
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## 由 D_Wall 调用，B 被吸附到 D 上。
func adsorb_to_d(d_global_pos: Vector3) -> void:
	adsorbed = true
	gravity_enabled = false
	gravity_scale = 0.0
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform.origin = d_global_pos


## 复原到「G 已收集、尚未落入 D」：取消吸附、不透明。
## defer_gravity：先保持冻结，等外部换完位置再 enable_gravity（避免还在 D 上就掉进去）。
func restore_after_g_collected(defer_gravity: bool = false) -> void:
	adsorbed = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	set_transparency(1.0)
	if defer_gravity:
		gravity_enabled = false
		gravity_scale = 0.0
		freeze = true
	else:
		gravity_enabled = true
		gravity_scale = 1.0
		freeze = false
		sleeping = false


## 外部调用，设置 B 的透明度。
func set_transparency(alpha: float) -> void:
	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mi:
		return
	var src_mat := mi.get_active_material(0)
	var mat: StandardMaterial3D
	if src_mat != null and src_mat is StandardMaterial3D:
		mat = (src_mat as StandardMaterial3D).duplicate()
	else:
		mat = StandardMaterial3D.new()
		if src_mat != null:
			mat.albedo_color = src_mat.albedo_color
	mi.material_override = mat
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = alpha

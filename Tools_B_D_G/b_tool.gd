extends RigidBody3D

## B 道具：玩家可自由进出。
## 初始冻结；G 被收集后启用真实物理重力，并与 WALLS 碰撞。
## 落入 D 空间后被吸附，不再移动。


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

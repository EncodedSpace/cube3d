extends Node3D

## D 墙壁：
## - G 未收集：同时绑多个面时，任一面亮起则显示且有碰撞
## - G 已收集且未开门：始终显示且有碰撞（方便 B 落入）
## - B 落入后开门：取消固体碰撞，半透明，玩家可通过


var is_open := false
var g_collected := false

@onready var static_body: StaticBody3D = $StaticBody3D
@onready var area: Area3D = $Area3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	# 与墙面同层，确保 CharacterBody 玩家撞得到。
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	_set_blocking_shapes_disabled(false)
	area.body_entered.connect(_on_body_entered)


func notify_g_collected() -> void:
	g_collected = true


func _on_body_entered(body: Node3D) -> void:
	if is_open:
		return
	if not body.is_in_group("b_tool"):
		return

	open_door(body)


func open_door(b_tool: Node3D) -> void:
	is_open = true

	# B 吸附到 D 的位置。
	if b_tool.has_method("adsorb_to_d"):
		b_tool.adsorb_to_d(global_position)

	# 取消碰撞 —— 玩家可通过。
	static_body.collision_layer = 0
	_set_blocking_shapes_disabled(true)

	# D 半透明，不消失。
	if mesh_instance:
		_set_mesh_transparency(mesh_instance, 0.5)

	# B 也半透明。
	if b_tool.has_method("set_transparency"):
		b_tool.set_transparency(0.5)


## 未开门时仍需要挡人。
func should_keep_player_block() -> bool:
	return not is_open


## G 收集后、开门前：忽略裁切，始终亮着并挡人。
func should_force_visible_block() -> bool:
	return g_collected and not is_open


## 恢复挡人碰撞与 B 检测 Area。
func ensure_player_block() -> void:
	if is_open or static_body == null:
		return
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	_set_blocking_shapes_disabled(false)
	if area != null:
		for child in area.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = false


func _set_blocking_shapes_disabled(disabled: bool) -> void:
	if static_body == null:
		return
	for child in static_body.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = disabled


func _set_mesh_transparency(mi: MeshInstance3D, alpha: float) -> void:
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

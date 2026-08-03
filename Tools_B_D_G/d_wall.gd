extends Node3D

## D 墙壁：
## - G 未收集：同时绑多个面时，任一面亮起则显示且有碰撞
## - G 已收集且未开门：始终显示且有碰撞（方便 B 落入）
## - B 落入后开门：取消固体碰撞，半透明，玩家可通过
## 名字以 D_Wall 开头的节点共用本脚本（含 D_Wall2）。


var is_open := false
var g_collected := false

## B 落在 D 顶面上时，中心距约 1m；邻格同高约 1m，需用「水平贴格」区分。
@export var adsorb_lateral_max := 0.55
@export var adsorb_up_max := 1.35
@export var adsorb_down_max := 0.55

@onready var static_body: StaticBody3D = $StaticBody3D
@onready var area: Area3D = $Area3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	# 与墙面同层，确保 CharacterBody 玩家撞得到。
	if static_body:
		static_body.collision_layer = 1
		static_body.collision_mask = 1
	_set_blocking_shapes_disabled(false)

	if area:
		area.monitoring = true
		area.monitorable = false
		# 检测 B_Tool（collision_layer = 4）。
		area.collision_layer = 4
		area.collision_mask = 4
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)

	set_physics_process(false)
	call_deferred("check_b_overlap")


func _physics_process(_delta: float) -> void:
	if is_open or not g_collected:
		set_physics_process(false)
		return
	check_b_overlap()


func notify_g_collected() -> void:
	g_collected = true
	set_physics_process(true)
	# G 收集后强制可接 B：补检一次已重叠。
	call_deferred("check_b_overlap")


## 复原到「G 已收集、门未开」：挡人、不透明、可再接 B。
func restore_after_g_collected() -> void:
	is_open = false
	g_collected = true
	if static_body:
		static_body.collision_layer = 1
		static_body.collision_mask = 1
	_set_blocking_shapes_disabled(false)
	if area != null:
		area.monitoring = true
		for child in area.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = false
	if mesh_instance:
		_set_mesh_transparency(mesh_instance, 1.0)
	set_physics_process(true)
	call_deferred("check_b_overlap")


## 暂时保持开门（无固体），让换进来的箱子靠重力掉出去，稍后再 restore 关门。
func keep_open_for_exit() -> void:
	is_open = true
	g_collected = true
	set_physics_process(false)
	if static_body:
		static_body.collision_layer = 0
	_set_blocking_shapes_disabled(true)
	if mesh_instance:
		_set_mesh_transparency(mesh_instance, 0.5)


## B 已在检测区内时 body_entered 不会再触发，需主动补检。
## 另外：B 常停在 D 固体顶面，Area 刚好擦边会漏检，故加水平贴格判定。
func check_b_overlap() -> void:
	if is_open:
		return
	if area != null and is_instance_valid(area):
		for body in area.get_overlapping_bodies():
			if body != null and body.is_in_group("b_tool"):
				open_door(body)
				return
	_check_b_on_top()


func _check_b_on_top() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for body in tree.get_nodes_in_group("b_tool"):
		if body == null or not is_instance_valid(body) or not (body is Node3D):
			continue
		if _is_b_resting_on_d(body as Node3D):
			open_door(body as Node3D)
			return


func _is_b_resting_on_d(body: Node3D) -> bool:
	var offset := body.global_position - global_position
	# 世界重力坐标系：同格（水平近）且大致在 D 上方/重合，排除邻格同高。
	var lateral := offset - Vector3.UP * offset.dot(Vector3.UP)
	if lateral.length() > adsorb_lateral_max:
		return false
	var along_up := offset.dot(Vector3.UP)
	if along_up > adsorb_up_max:
		return false
	if along_up < -adsorb_down_max:
		return false
	return true


func _on_body_entered(body: Node3D) -> void:
	if is_open:
		return
	if not body.is_in_group("b_tool"):
		return
	open_door(body)


func open_door(b_tool: Node3D) -> void:
	if is_open:
		return
	is_open = true
	set_physics_process(false)

	# B 吸附到 D 的位置。
	if b_tool.has_method("adsorb_to_d"):
		b_tool.adsorb_to_d(global_position)

	# 取消碰撞 —— 玩家可通过。
	if static_body:
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


## 恢复挡人碰撞与 B 检测 Area。
func ensure_player_block() -> void:
	if is_open or static_body == null:
		return
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	_set_blocking_shapes_disabled(false)
	if area != null:
		area.monitoring = true
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

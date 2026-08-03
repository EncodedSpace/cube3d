extends StaticBody3D

## StaticBox_E2：初始挡住玩家；E1 内叠入 MovableBox 后打开，玩家可自由通行。


## false = 挡玩家；true = 已打开，玩家可通行。
var allows_player_enter := false
var is_open := false

var _unlocked := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	_set_solid_shapes_disabled(false)


func unlock_for_player() -> void:
	if _unlocked:
		return
	_unlocked = true
	is_open = true
	allows_player_enter = true
	collision_layer = 0
	collision_mask = 0
	_set_solid_shapes_disabled(true)
	_set_mesh_transparency(0.35)


func apply_cutaway_visibility(wall_visible: bool) -> void:
	visible = wall_visible
	if _unlocked or allows_player_enter or is_open:
		# 已打开：永远不挡人，只随墙显隐。
		collision_layer = 0
		collision_mask = 0
		_set_solid_shapes_disabled(true)
	elif wall_visible:
		collision_layer = 1
		collision_mask = 1
		_set_solid_shapes_disabled(false)
	else:
		_set_solid_shapes_disabled(true)


func _set_solid_shapes_disabled(disabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = disabled


func _set_mesh_transparency(alpha: float) -> void:
	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
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

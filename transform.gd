extends Node3D

@export var wall_rotation_duration := 1.1
@export var z_axis := Vector3(0, 0, 1)
@export var x_axis := Vector3(1, 0, 0)
@export var y_axis := Vector3(0, 1, 0)
@export var camera_transition_duration := 1.8

# 墙体变成透明所需的时间与目标透明度 (0.0 表示完全透明)
@export var fade_duration := 1.0
@export_range(0.0, 1.0) var target_alpha := 0.0

# 新增：玩家重置场景的 Y 轴临界值
@export var reset_y_threshold := -100.0

@onready var wall6: Node3D = $m6
@onready var wall3: Node3D = $m3
@onready var wall5: Node3D = $m5
@onready var wall2: Node3D = $m2
@onready var wall4: Node3D = $m2/m4

# 获取 Player 节点的引用
@onready var player: Node3D = get_node("../Player") as Node3D
@onready var player_marker: Marker3D = get_node("../Player/Marker3D2") as Marker3D
@onready var player_camera: Camera3D = get_node("../Player/Marker3D2/Camera3D") as Camera3D
@onready var box_marker: Marker3D = $Marker3D
@onready var box_camera: Camera3D = $Marker3D/Camera3D

var rotated := false
var _wall_tweens: Dictionary = {}
var _camera_tween: Tween

func _ready() -> void:
	# The Player camera remains active until this BOX is entered.
	player_camera.make_current()

func _process(_delta: float) -> void:
	# 检查玩家 Y 轴坐标，若低于阈值则重置场景
	if is_instance_valid(player) and player.global_position.y < reset_y_threshold:
		get_tree().reload_current_scene()

# Reusable rotation tween for any wall, axis, and angle.
func rotate_wall(wall_node: Node3D, axis: Vector3, degrees: float) -> Tween:
	if not is_instance_valid(wall_node):
		push_warning("Wall node is null or invalid.")
		return null
	if axis.is_zero_approx():
		push_warning("Rotation axis must not be Vector3.ZERO.")
		return null

	if _wall_tweens.has(wall_node) and is_instance_valid(_wall_tweens[wall_node]):
		var old_tween: Tween = _wall_tweens[wall_node]
		if old_tween.is_running():
			old_tween.kill()

	var target_rotation := wall_node.quaternion * Quaternion(axis.normalized(), deg_to_rad(degrees))
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(wall_node, "quaternion", target_rotation, wall_rotation_duration)
	_wall_tweens[wall_node] = tween
	return tween

func is_wall_rotating(wall_node: Node3D) -> bool:
	return _wall_tweens.has(wall_node) \
		and is_instance_valid(_wall_tweens[wall_node]) \
		and _wall_tweens[wall_node].is_running()

# Moves the active Player camera to this BOX camera without a final visual jump.
func transition_to_box_camera() -> void:
	if is_instance_valid(_camera_tween) and _camera_tween.is_running():
		_camera_tween.kill()

	player_camera.projection = box_camera.projection
	player_camera.keep_aspect = box_camera.keep_aspect
	player_camera.cull_mask = box_camera.cull_mask

	_camera_tween = create_tween().set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_camera_tween.tween_method(
		_set_player_marker_transform,
		player_marker.global_transform,
		box_marker.global_transform,
		camera_transition_duration
	)
	
	_camera_tween.tween_property(player_camera, "fov", box_camera.fov, camera_transition_duration)
	_camera_tween.tween_property(player_camera, "size", box_camera.size, camera_transition_duration)
	_camera_tween.tween_property(player_camera, "near", box_camera.near, camera_transition_duration)
	_camera_tween.tween_property(player_camera, "far", box_camera.far, camera_transition_duration)
	_camera_tween.tween_property(player_camera, "h_offset", box_camera.h_offset, camera_transition_duration)
	_camera_tween.tween_property(player_camera, "v_offset", box_camera.v_offset, camera_transition_duration)
	_camera_tween.tween_property(player_camera, "frustum_offset", box_camera.frustum_offset, camera_transition_duration)
	_camera_tween.finished.connect(_activate_box_camera)

func _set_player_marker_transform(value: Transform3D) -> void:
	player_marker.global_transform = value

func _set_player_camera_transform(value: Transform3D) -> void:
	player_camera.transform = value

func _activate_box_camera() -> void:
	box_camera.make_current()

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and not rotated \
		and not is_wall_rotating(wall6) \
		and not is_wall_rotating(wall3) \
		and not is_wall_rotating(wall5) \
		and not is_wall_rotating(wall2) \
		and not is_wall_rotating(wall4):
		
		# 1. 启动旋转和相机平移
		var last_wall_tween := rotate_wall(wall6, z_axis, 180)
		rotate_wall(wall3, z_axis, -180)
		rotate_wall(wall5, x_axis, -90)
		rotate_wall(wall2, x_axis, 90)
		rotate_wall(wall4, x_axis, 90)
		transition_to_box_camera()
		
		rotated = true
		if player is CharacterBody3D:
			player.set_physics_process(false)
			(player as CharacterBody3D).velocity = Vector3.ZERO

		# 2. 等待墙体旋转与相机过渡全部结束（正方体合拢）后立刻进入正式关卡
		if last_wall_tween != null:
			await last_wall_tween.finished
		if _camera_tween != null:
			await _camera_tween.finished

		get_tree().change_scene_to_file("res://teach/main.tscn")


# 渐变淡出墙体函数
func fade_walls_out(walls: Array[Node3D]) -> Tween:
	var fade_tween := create_tween().set_parallel(true)
	fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var animated := false

	for wall in walls:
		if not is_instance_valid(wall):
			continue

		var mesh_node := _find_mesh_instance(wall)
		if not mesh_node:
			continue

		# 获取 override 材质或网格资源上的材质
		var mat: Material = mesh_node.get_surface_override_material(0)
		if not mat and mesh_node.mesh and mesh_node.mesh.get_surface_count() > 0 \
			and mesh_node.mesh.surface_get_material(0):
			mat = mesh_node.mesh.surface_get_material(0).duplicate()
			mesh_node.set_surface_override_material(0, mat)

		if not mat:
			continue

		# 1. 如果使用了自定义 ShaderMaterial
		if mat is ShaderMaterial:
			var s_mat := mat as ShaderMaterial
			fade_tween.tween_property(s_mat, "shader_parameter/albedo:a", target_alpha, fade_duration)
			animated = true

		# 2. 如果使用的是 Godot 内置 StandardMaterial3D
		elif mat is StandardMaterial3D:
			var std_mat := mat as StandardMaterial3D
			std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fade_tween.tween_property(std_mat, "albedo_color:a", target_alpha, fade_duration)
			animated = true

	if not animated:
		fade_tween.kill()
		return null
	return fade_tween


# 辅助方法：递归找寻节点下的 MeshInstance3D
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var res := _find_mesh_instance(child)
		if res:
			return res
	return null

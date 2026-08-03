extends Node


signal finished(on_floor: bool)


# 每次翻滚 90° 所需时间。
@export var roll_duration := 0.20

# 玩家向墙面推动达到此强度时，触发世界翻转。
@export var flip_push_threshold := 0.35


var player: CharacterBody3D
var visual_body: Node3D
var visual_face: Node3D
var collision_shape: CollisionShape3D
var cube_world: Node3D

# 当前是否正在执行翻滚。
var active := false

# 用来终止旧的异步翻滚。
var _request_id := 0


func setup(
	player_node: CharacterBody3D,
	body_node: Node3D,
	face_node: Node3D,
	collision_node: CollisionShape3D,
	world_node: Node3D
) -> void:
	player = player_node
	visual_body = body_node
	visual_face = face_node
	collision_shape = collision_node
	cube_world = world_node


# 开始连续格子翻滚。
func start(
	first_direction: Vector3,
	grid_step: float
) -> void:
	if active:
		return

	if first_direction == Vector3.ZERO:
		return

	if (
		player == null
		or visual_body == null
		or visual_face == null
	):
		return

	_request_id += 1
	var current_request := _request_id

	active = true
	player.velocity = Vector3.ZERO

	var direction := first_direction

	visual_face.look_direction(direction)

	await visual_body.start_squash()

	if not _is_request_active(current_request):
		return

	while (
		direction != Vector3.ZERO
		and _is_request_active(current_request)
	):
		var destination := (
			player.global_position
			+ direction * grid_step
		)

		# 提前检查下一格是否有墙或障碍。
		var test_collision := player.move_and_collide(
			direction * grid_step,
			true
		)

		if test_collision:
			var collider := test_collision.get_collider()

			if _is_cube_wall_collider(collider):
				_try_world_flip(
					test_collision.get_normal(),
					direction
				)
				break

			# D_Wall / StaticBox / other solids: never roll into them.
			# (Destination name checks alone miss D_Wall's child StaticBody3D.)
			if _destination_has_obstacle(destination) or collider != null:
				break

		visual_face.look_direction(direction)

		var roll_succeeded := await _roll_step(
			direction,
			grid_step,
			current_request
		)

		if not _is_request_active(current_request):
			return

		if not roll_succeeded:
			break

		# 前方没有地面，结束翻滚并开始自然下落。
		if not player.has_floor_below():
			break

		direction = player.get_input_direction()

	if not _is_request_active(current_request):
		return

	var on_floor: bool = bool(player.has_floor_below())

	if on_floor:
		await visual_body.end_squash()

		if not _is_request_active(current_request):
			return

	active = false
	finished.emit(on_floor)


# 执行一次 90° 翻滚。
func _roll_step(
	direction: Vector3,
	step_distance: float,
	request_id: int
) -> bool:
	var start_position := player.global_position
	var start_body_basis := visual_body.basis

	var final_position := (
		start_position
		+ direction * step_distance
	)

	var half_height := _get_cube_height() * 0.5
	var half_step := step_distance * 0.5

	# 方块绕前方底边旋转。
	var pivot_position := (
		start_position
		+ direction * half_step
		+ Vector3.DOWN * half_height
	)

	var axis := (
		Vector3.UP
		.cross(direction)
		.normalized()
	)

	var safe_duration := maxf(
		roll_duration,
		0.001
	)

	var elapsed := 0.0

	while elapsed < safe_duration:
		await get_tree().physics_frame

		# 外部重置或世界翻转后直接结束，
		# 不再修改角色位置。
		if not _is_request_active(request_id):
			return false

		elapsed += get_physics_process_delta_time()

		var progress := clampf(
			elapsed / safe_duration,
			0.0,
			1.0
		)

		var angle := deg_to_rad(90.0) * progress

		var desired_position := (
			pivot_position
			+ (
				start_position
				- pivot_position
			).rotated(axis, angle)
		)

		var frame_motion := (
			desired_position
			- player.global_position
		)

		var collision := player.move_and_collide(
			frame_motion
		)

		if collision:
			if _should_abort_roll_on_collision(
				collision.get_collider(),
				final_position
			):
				player.global_position = start_position
				visual_body.basis = start_body_basis
				return false

			# 忽略碰撞裕度产生的轻微误报。
			player.global_position = desired_position

		visual_body.basis = (
			Basis(axis, angle)
			* start_body_basis
		).orthonormalized()

	if not _is_request_active(request_id):
		return false

	var correction := (
		final_position
		- player.global_position
	)

	if correction.length() > 0.0001:
		var final_collision := player.move_and_collide(
			correction
		)

		if final_collision:
			if _should_abort_roll_on_collision(
				final_collision.get_collider(),
				final_position
			):
				player.global_position = start_position
				visual_body.basis = start_body_basis
				return false

			player.global_position = final_position

	# 严格对齐到完整格子。
	player.global_position = final_position

	visual_body.basis = (
		Basis(
			axis,
			deg_to_rad(90.0)
		)
		* start_body_basis
	).orthonormalized()

	return true


func _should_abort_roll_on_collision(
	collider: Object,
	final_position: Vector3
) -> bool:
	return (
		_is_cube_wall_collider(collider)
		or _destination_has_obstacle(final_position)
	)


# 获取角色碰撞盒的真实高度。
func _get_cube_height() -> float:
	if collision_shape == null:
		return 1.0

	var box_shape := (
		collision_shape.shape
		as BoxShape3D
	)

	if box_shape == null:
		return 1.0

	var shape_scale := (
		collision_shape
		.global_basis
		.get_scale()
	)

	return (
		box_shape.size.y
		* absf(shape_scale.y)
	)


# 判断碰撞对象是否属于立方体外墙。
func _is_cube_wall_collider(
	collider: Object
) -> bool:
	if collider == null or cube_world == null:
		return false

	var walls := cube_world.get_node_or_null(
		"WALLS"
	)

	if walls == null:
		return false

	var node := collider as Node

	while node != null:
		if node.get_parent() == walls:
			return true

		node = node.get_parent()

	return false


# 判断目标格是否存在箱子或其他障碍。
func _destination_has_obstacle(
	destination: Vector3
) -> bool:
	if (
		cube_world == null
		or not cube_world.has_method(
			"_collect_obstacle_boxes"
		)
	):
		return false

	const HALF_CELL := 0.51

	for box in cube_world._collect_obstacle_boxes():
		if (
			box == null
			or not is_instance_valid(box)
		):
			continue

		var offset: Vector3 = (
			box.global_position
			- destination
		)

		if (
			absf(offset.x) < HALF_CELL
			and absf(offset.y) < HALF_CELL
			and absf(offset.z) < HALF_CELL
		):
			return true

	return false


# 撞到立方体外墙时尝试翻转世界。
func _try_world_flip(
	normal: Vector3,
	input_direction: Vector3
) -> void:
	if cube_world == null:
		return

	if not cube_world.has_method("can_flip"):
		return

	if not cube_world.can_flip():
		return

	# 地面不触发世界翻转。
	if normal.y > 0.55:
		return

	var push_strength := (
		input_direction.dot(-normal)
	)

	if push_strength < flip_push_threshold:
		return

	cube_world.request_flip(
		normal,
		player
	)


# 重置关卡或世界翻转时取消翻滚。
func cancel() -> void:
	_request_id += 1
	active = false

	if player:
		player.velocity = Vector3.ZERO

	if (
		visual_body
		and visual_body.has_method("stop_shape_tween")
	):
		visual_body.stop_shape_tween()
		visual_body.scale = Vector3.ONE


func _is_request_active(
	request_id: int
) -> bool:
	return (
		active
		and request_id == _request_id
	)

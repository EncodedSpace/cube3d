extends Node


@export_group("箱子下落音效")

@export_range(0.01, 5.0, 0.01)
var fall_trigger_speed: float = 0.1

# 一格的距离。
@export_range(0.1, 10.0, 0.1)
var minimum_fall_distance: float = 1.0

@export_range(1.0, 100.0, 1.0)
var fall_check_distance: float = 20.0

# 小于这个距离，认为箱子正贴着支撑面。
@export_range(0.01, 0.5, 0.01)
var support_tolerance: float = 0.12

@export_range(-80.0, 6.0, 0.1)
var fall_sfx_volume_db: float = -6.0


@onready var box: RigidBody3D = (
	get_parent() as RigidBody3D
)

@onready var fall_sfx_player: AudioStreamPlayer = (
	get_node_or_null("../FallSfx")
	as AudioStreamPlayer
)


var box_collision: CollisionShape3D

var previous_velocity: Vector3 = Vector3.ZERO
var fall_sound_armed: bool = true
var crush_started: bool = false


func _ready() -> void:
	if box == null:
		push_error(
			"CrushDetector 的父节点必须是 RigidBody3D"
		)
		return

	box_collision = box.find_child(
		"CollisionShape3D",
		true,
		false
	) as CollisionShape3D

	box.contact_monitor = true
	box.max_contacts_reported = 8

	if not box.body_entered.is_connected(
		_on_body_entered
	):
		box.body_entered.connect(
			_on_body_entered
		)

	if fall_sfx_player == null:
		push_warning(
			"没有找到同级节点 FallSfx"
		)
	else:
		fall_sfx_player.volume_db = (
			fall_sfx_volume_db
		)

		fall_sfx_player.process_mode = (
			Node.PROCESS_MODE_ALWAYS
		)


func _physics_process(_delta: float) -> void:
	if box == null:
		return

	var velocity: Vector3 = box.linear_velocity
	var fall_direction: Vector3 = _get_fall_direction()

	if crush_started:
		previous_velocity = velocity
		return

	if fall_direction == Vector3.ZERO:
		previous_velocity = velocity
		return

	# 大立方体翻转时，如果箱子被冻结，
	# 为翻转结束后的新一次下落重新准备音效。
	if box.freeze:
		fall_sound_armed = true
		previous_velocity = velocity
		return

	# 箱子贴着当前支撑面时，
	# 允许下一次离开支撑面后播放。
	if _is_supported(fall_direction):
		fall_sound_armed = true
		previous_velocity = velocity
		return

	var fall_speed: float = velocity.dot(
		fall_direction
	)

	# 已经离开支撑面，并开始沿重力方向运动。
	if (
		fall_sound_armed
		and fall_speed > fall_trigger_speed
		and _will_fall_far_enough(fall_direction)
	):
		fall_sound_armed = false
		_play_fall_sfx()

	previous_velocity = velocity


func _get_fall_direction() -> Vector3:
	if box == null:
		return Vector3.ZERO

	var gravity: Vector3 = box.get_gravity()

	if gravity.length_squared() < 0.000001:
		return Vector3.ZERO

	return gravity.normalized()


func _cast_below(
	fall_direction: Vector3
) -> Dictionary:
	var empty_result: Dictionary = {}

	if box == null:
		return empty_result

	var world: World3D = box.get_world_3d()

	if world == null:
		return empty_result

	var ray_start: Vector3 = box.global_position

	var ray_end: Vector3 = (
		ray_start
		+ fall_direction * fall_check_distance
	)

	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			ray_start,
			ray_end
		)
	)

	var excluded: Array[RID] = [
		box.get_rid()
	]

	query.exclude = excluded
	query.collision_mask = box.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	return world.direct_space_state.intersect_ray(
		query
	)


func _is_supported(
	fall_direction: Vector3
) -> bool:
	var result: Dictionary = _cast_below(
		fall_direction
	)

	if result.is_empty():
		return false

	var collider: Node = (
		result.get("collider") as Node
	)

	# 主角不算支撑面。
	if _is_player(collider):
		return false

	var gap: float = _get_available_distance(
		result,
		fall_direction
	)

	return gap <= support_tolerance


func _will_fall_far_enough(
	fall_direction: Vector3
) -> bool:
	var result: Dictionary = _cast_below(
		fall_direction
	)

	# 检测距离内没有障碍，说明会下落很远。
	if result.is_empty():
		return true

	var collider: Node = (
		result.get("collider") as Node
	)

	# 预计砸到主角时也播放。
	if _is_player(collider):
		return true

	var available_distance: float = (
		_get_available_distance(
			result,
			fall_direction
		)
	)

	return (
		available_distance
		>= minimum_fall_distance
	)


func _get_available_distance(
	result: Dictionary,
	fall_direction: Vector3
) -> float:
	var hit_position: Vector3 = (
		result.get(
			"position",
			box.global_position
		) as Vector3
	)

	var center_distance: float = (
		(hit_position - box.global_position).dot(
			fall_direction
		)
	)

	var front_distance: float = (
		_get_box_front_distance(
			fall_direction
		)
	)

	return maxf(
		0.0,
		center_distance - front_distance
	)


func _get_box_front_distance(
	direction: Vector3
) -> float:
	if box_collision == null:
		return 0.5

	var shape: BoxShape3D = (
		box_collision.shape as BoxShape3D
	)

	if shape == null:
		return 0.5

	var offset: float = (
		(
			box_collision.global_position
			- box.global_position
		).dot(direction)
	)

	var extent: float = _get_shape_extent(
		box_collision,
		shape,
		direction
	)

	return maxf(
		0.0,
		offset + extent
	)


func _get_shape_extent(
	collision: CollisionShape3D,
	shape: BoxShape3D,
	direction: Vector3
) -> float:
	var half_size: Vector3 = (
		shape.size * 0.5
	)

	var basis: Basis = (
		collision.global_transform.basis
	)

	return (
		absf(direction.dot(basis.x))
		* half_size.x
		+ absf(direction.dot(basis.y))
		* half_size.y
		+ absf(direction.dot(basis.z))
		* half_size.z
	)


func _is_player(node: Node) -> bool:
	if node == null:
		return false

	return (
		node.is_in_group("player")
		or node.has_method("die")
	)


func _play_fall_sfx() -> void:
	if fall_sfx_player == null:
		return

	if fall_sfx_player.stream == null:
		push_warning(
			"FallSfx 没有设置音频文件"
		)
		return

	fall_sfx_player.volume_db = (
		fall_sfx_volume_db
	)

	fall_sfx_player.play()


func _on_body_entered(body: Node) -> void:
	if crush_started:
		return

	if not body.has_method("die"):
		return

	if not body.has_method(
		"get_death_height_scale"
	):
		return

	var player: Node3D = body as Node3D

	if player == null:
		return

	var fall_direction: Vector3 = (
		_get_fall_direction()
	)

	if fall_direction == Vector3.ZERO:
		return

	var previous_fall_speed: float = (
		previous_velocity.dot(
			fall_direction
		)
	)

	if previous_fall_speed <= 0.5:
		return

	# 主角必须位于箱子的下落方向。
	var player_below_distance: float = (
		(
			player.global_position
			- box.global_position
		).dot(fall_direction)
	)

	if player_below_distance <= 0.25:
		return

	var player_collision: CollisionShape3D = (
		body.find_child(
			"CollisionShape3D",
			true,
			false
		) as CollisionShape3D
	)

	if player_collision == null:
		return

	var player_shape: BoxShape3D = (
		player_collision.shape as BoxShape3D
	)

	if player_shape == null:
		return

	# 进入压扁流程后，彻底关闭本次下落的音效判断。
	crush_started = true
	fall_sound_armed = false

	var player_height: float = (
		_get_shape_extent(
			player_collision,
			player_shape,
			fall_direction
		) * 2.0
	)

	box.freeze_mode = (
		RigidBody3D.FREEZE_MODE_KINEMATIC
	)

	box.freeze = true
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO

	body.call("die")

	var height_scale: float = float(
		body.call(
			"get_death_height_scale"
		)
	)

	var crush_distance: float = (
		player_height
		* (1.0 - height_scale)
	)

	var start_transform: Transform3D = (
		box.global_transform
	)

	var target_transform: Transform3D = (
		start_transform
	)

	target_transform.origin += (
		fall_direction * crush_distance
	)

	var tween: Tween = create_tween()

	tween.set_process_mode(
		Tween.TWEEN_PROCESS_PHYSICS
	)

	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_method(
		func(progress: float) -> void:
			box.global_transform = (
				start_transform.interpolate_with(
					target_transform,
					progress
				)
			),
		0.0,
		1.0,
		0.35
	)

	await tween.finished

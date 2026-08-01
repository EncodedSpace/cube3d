extends CharacterBody3D


# 每次翻滚90度所需时间。
# 数值越大，滚动越慢。
@export var roll_duration := 0.20

# 重力和跳跃力度。
@export var fall_acceleration := 75
@export var jump_impulse := 15

# 角色向下检测地面的距离。
@export var floor_probe_distance := 0.08

# 玩家推向墙面达到这个强度时，允许触发世界翻转。
@export var flip_push_threshold := 0.35


# 根据实际节点名称调整这里。
@onready var visual_body: Node3D = $Pivot/PlayerCube/Body
@onready var visual_face: Node3D = $Pivot/PlayerCube/Face

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

@onready var cube_world: Node3D = \
	get_parent().get_node_or_null("Node3D")


# 正在执行连续翻滚时为 true。
var moving_chain := false

# 正在播放起跳前蓄力时为 true。
var jump_preparing := false

# 记录上一帧是否在地面上，用于检测落地瞬间。
var was_on_floor := true


func _physics_process(delta: float) -> void:
	# 翻滚由 roll_step() 单独控制。
	# 此时不要再执行普通 CharacterBody3D 移动。
	if moving_chain:
		velocity = Vector3.ZERO
		return

	# 起跳蓄力期间保持角色静止。
	if jump_preparing:
		velocity = Vector3.ZERO
		return

	var direction := get_input_direction()

	# is_on_floor() 在 move_and_slide() 后最可靠。
	# 向下测试用于翻滚结束后的补充判断。
	var grounded := is_on_floor() or has_floor_below()

	if grounded:
		# 落地后清除向下速度。
		if velocity.y < 0.0:
			velocity.y = 0.0

		# 空格键起跳。
		if Input.is_action_just_pressed("jump"):
			start_jump()
			return

		# 地面上有方向输入时开始翻滚。
		if direction != Vector3.ZERO:
			start_move_chain(direction)
			return
	else:
		# 空中持续施加重力。
		velocity.y -= fall_acceleration * delta

	# 不使用普通水平平移。
	# 水平运动全部由方块翻滚完成。
	velocity.x = 0.0
	velocity.z = 0.0

	move_and_slide()

	# 保留队友原来的墙面翻转检测。
	try_face_flip(direction)

	# 检测从空中落到地面的瞬间。
	var on_floor_now := is_on_floor()

	if not was_on_floor and on_floor_now:
		visual_body.land_squash()

	was_on_floor = on_floor_now


# 起跳流程：
# 先播放压缩蓄力，再赋予向上速度。
func start_jump() -> void:
	jump_preparing = true
	velocity = Vector3.ZERO

	await visual_body.jump_takeoff()

	velocity.y = jump_impulse
	jump_preparing = false
	was_on_floor = false


# 开始一串连续翻滚。
func start_move_chain(first_direction: Vector3) -> void:
	moving_chain = true
	velocity = Vector3.ZERO

	var direction := first_direction

	# 眼睛提前看向移动方向。
	visual_face.look_direction(direction)

	# 一串滚动只在最开始蓄力一次。
	await visual_body.start_squash()

	while direction != Vector3.ZERO:
		var step_distance := get_step_distance(direction)

		# 先测试前方是否存在墙体。
		# test_only = true，因此这里只检测，不真正移动。
		var test_collision := move_and_collide(
			direction * step_distance,
			true
		)

		if test_collision:
			try_flip_from_normal(
				test_collision.get_normal(),
				direction
			)
			break

		visual_face.look_direction(direction)

		# 执行一次碰撞安全的90度翻滚。
		var roll_succeeded := await roll_step(
			direction,
			step_distance
		)

		if not roll_succeeded:
			break

		# 翻滚后如果前方已经没有地面，则结束滚动并开始下落。
		if not has_floor_below():
			break

		# 继续读取当前按住的方向。
		direction = get_input_direction()

	# 只有仍在地面上时才播放落地回弹。
	if has_floor_below():
		await visual_body.end_squash()

	moving_chain = false

	# 翻滚函数没有调用 move_and_slide()，
	# 因此这里手动更新地面记录。
	was_on_floor = has_floor_below()


# 执行一次真正的方块翻滚。
# CharacterBody3D 的中心沿底边圆弧移动，
# Body 同时旋转90度。
func roll_step(
	direction: Vector3,
	step_distance: float
) -> bool:
	var start_position := global_position
	var start_body_basis := visual_body.basis

	var cube_height := get_cube_height()
	var half_height := cube_height * 0.5
	var half_step := step_distance * 0.5

	# 当前方块将围绕的底边中心。
	var pivot_position := (
		start_position
		+ direction * half_step
		+ Vector3.DOWN * half_height
	)

	# 翻滚旋转轴。
	var axis := Vector3.UP.cross(direction).normalized()

	var elapsed := 0.0

	while elapsed < roll_duration:
		await get_tree().physics_frame

		elapsed += get_physics_process_delta_time()

		var progress := clampf(
			elapsed / roll_duration,
			0.0,
			1.0
		)

		var angle := deg_to_rad(90.0) * progress

		# 计算这一帧角色中心应该处于的圆弧位置。
		var desired_position := (
			pivot_position
			+ (start_position - pivot_position).rotated(
				axis,
				angle
			)
		)

		var frame_motion := desired_position - global_position

		# 每一帧都使用 move_and_collide，
		# 防止 Tween 直接修改坐标造成穿墙。
		var collision := move_and_collide(frame_motion)

		if collision:
			# 中途发生碰撞时恢复到翻滚前状态。
			global_position = start_position
			visual_body.basis = start_body_basis
			return false

		# 身体同步旋转，但眼睛不会跟着翻。
		visual_body.basis = (
			Basis(axis, angle) *
			start_body_basis
		).orthonormalized()

	# 最终位置严格对齐一个方块边长。
	var final_position := (
		start_position
		+ direction * step_distance
	)

	var correction := final_position - global_position

	if correction.length() > 0.0001:
		var final_collision := move_and_collide(correction)

		if final_collision:
			global_position = start_position
			visual_body.basis = start_body_basis
			return false

	# 最终旋转严格对齐90度，消除浮点误差。
	visual_body.basis = (
		Basis(axis, deg_to_rad(90.0)) *
		start_body_basis
	).orthonormalized()

	return true


# 根据碰撞盒实际尺寸计算每一步的移动距离。
# 不再把步长写死为1。
func get_step_distance(direction: Vector3) -> float:
	var box_shape := collision_shape.shape as BoxShape3D

	if box_shape == null:
		return 1.0

	var shape_scale := collision_shape.global_basis.get_scale()
	var world_size := box_shape.size * shape_scale.abs()

	if absf(direction.x) > 0.5:
		return world_size.x

	return world_size.z


# 获取碰撞盒实际高度。
func get_cube_height() -> float:
	var box_shape := collision_shape.shape as BoxShape3D

	if box_shape == null:
		return 1.0

	var shape_scale := collision_shape.global_basis.get_scale()

	return box_shape.size.y * absf(shape_scale.y)


# 检测角色脚下是否仍然有地面。
func has_floor_below() -> bool:
	return test_move(
		global_transform,
		Vector3.DOWN * floor_probe_distance
	)


# 方格移动只允许四个方向，不允许斜向翻滚。
func get_input_direction() -> Vector3:
	if Input.is_action_pressed("move_right"):
		return Vector3.RIGHT

	elif Input.is_action_pressed("move_left"):
		return Vector3.LEFT

	elif Input.is_action_pressed("move_forward"):
		return Vector3.FORWARD

	elif Input.is_action_pressed("move_back"):
		return Vector3.BACK

	return Vector3.ZERO


# 翻滚前检测到墙体时，尝试触发大立方体世界翻转。
func try_flip_from_normal(
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

	var into_surface := -normal
	var push_strength := input_direction.dot(into_surface)

	if push_strength < flip_push_threshold:
		return

	cube_world.request_flip(normal, self)


# 普通物理移动后的墙面检测。
# 主要用于跳跃过程中撞到墙面等情况。
func try_face_flip(input_direction: Vector3) -> void:
	if cube_world == null:
		return

	if not cube_world.has_method("can_flip"):
		return

	if not cube_world.can_flip():
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()

		# 忽略地面。
		if normal.y > 0.55:
			continue

		var into_surface := -normal
		var push_strength := input_direction.dot(into_surface)

		if push_strength < flip_push_threshold:
			continue

		if cube_world.request_flip(normal, self):
			return

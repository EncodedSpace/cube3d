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

# 关卡内：WASD 相对屏幕（W=右上）。开场 transform 等场景应关掉。
@export var screen_relative_move := true

# 关卡用格子翻滚；开场 transform 长路应关掉，改用滑动移动。
@export var use_grid_roll := true

# 滑动移动速度（use_grid_roll == false 时）。
@export var walk_speed := 8.0

# 格子步长固定为 1，不随 player scale 缩小，避免错格。
@export var grid_step := 1.0


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

var start_transform: Transform3D


func _ready() -> void:
	start_transform = global_transform


func reset_to_start() -> void:
	global_transform = start_transform
	velocity = Vector3.ZERO
	moving_chain = false
	jump_preparing = false
	was_on_floor = true
	$Pivot.basis = Basis.IDENTITY
	if visual_body:
		visual_body.basis = Basis.IDENTITY
		visual_body.scale = Vector3.ONE


func sync_move_from_facing() -> void:
	# Movement stays camera/screen-relative; only reset visuals after world flips.
	$Pivot.basis = Basis.IDENTITY
	if visual_body:
		visual_body.basis = Basis.IDENTITY
		visual_body.scale = Vector3.ONE
	moving_chain = false
	jump_preparing = false


func _physics_process(delta: float) -> void:
	if not use_grid_roll:
		_physics_process_walk(delta)
		return

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


## 开场道路等场景：普通滑动，可沿 Z 自由前进。
func _physics_process_walk(delta: float) -> void:
	var direction := _get_walk_direction()

	if direction != Vector3.ZERO:
		visual_face.look_direction(direction)
		velocity.x = direction.x * walk_speed
		velocity.z = direction.z * walk_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if not is_on_floor():
		velocity.y -= fall_acceleration * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_impulse
	elif velocity.y < 0.0:
		velocity.y = 0.0

	move_and_slide()

	var on_floor_now := is_on_floor()
	if not was_on_floor and on_floor_now and visual_body:
		visual_body.land_squash()
	was_on_floor = on_floor_now


func _get_walk_direction() -> Vector3:
	if screen_relative_move:
		return get_input_direction()

	var input := Vector3.ZERO
	if Input.is_action_pressed("move_right"):
		input.x += 1.0
	if Input.is_action_pressed("move_left"):
		input.x -= 1.0
	if Input.is_action_pressed("move_back"):
		input.z += 1.0
	if Input.is_action_pressed("move_forward"):
		input.z -= 1.0
	if input == Vector3.ZERO:
		return Vector3.ZERO
	return input.normalized()


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

	while direction != Vector3.ZERO and moving_chain:
		var step_distance := get_step_distance(direction)
		var destination := global_position + direction * step_distance

		# 先测试前方是否挡住。碰撞裕度可能提前碰到远处箱子，
		# 因此只有撞到立方体墙面才尝试翻转；撞到箱子时按目标格是否被占决定能否滚入。
		var test_collision := move_and_collide(
			direction * step_distance,
			true
		)

		if test_collision:
			var collider := test_collision.get_collider()
			if _is_cube_wall_collider(collider):
				try_flip_from_normal(
					test_collision.get_normal(),
					direction
				)
				break
			if _destination_has_obstacle(destination):
				break
			# 目标格为空：视为裕度误报，允许滚入空格。

		visual_face.look_direction(direction)

		# 执行一次碰撞安全的90度翻滚。
		var roll_succeeded := await roll_step(
			direction,
			step_distance
		)

		if not roll_succeeded or not moving_chain:
			break

		# 翻滚后如果前方已经没有地面，则结束滚动并开始下落。
		if not has_floor_below():
			break

		# 继续读取当前按住的方向。
		direction = get_input_direction()

	# 只有仍在地面上时才播放落地回弹。
	if moving_chain and has_floor_below():
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
	var final_position := start_position + direction * step_distance

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

		if not moving_chain:
			global_position = start_position
			visual_body.basis = start_body_basis
			return false

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
			if _should_abort_roll_on_collision(
				collision.get_collider(),
				final_position
			):
				global_position = start_position
				visual_body.basis = start_body_basis
				return false
			# 目标格为空时，远处箱子的裕度误报可忽略。
			global_position = desired_position

		# 身体同步旋转，但眼睛不会跟着翻。
		visual_body.basis = (
			Basis(axis, angle) *
			start_body_basis
		).orthonormalized()

	var correction := final_position - global_position

	if correction.length() > 0.0001:
		var final_collision := move_and_collide(correction)

		if final_collision:
			if _should_abort_roll_on_collision(
				final_collision.get_collider(),
				final_position
			):
				global_position = start_position
				visual_body.basis = start_body_basis
				return false
			global_position = final_position

	# 最终旋转严格对齐90度，消除浮点误差。
	visual_body.basis = (
		Basis(axis, deg_to_rad(90.0)) *
		start_body_basis
	).orthonormalized()

	return true


## Abort roll only for real walls, or boxes that occupy the destination cell.
func _should_abort_roll_on_collision(
	collider: Object,
	final_position: Vector3
) -> bool:
	if _is_cube_wall_collider(collider):
		return true
	return _destination_has_obstacle(final_position)


# 根据碰撞盒实际尺寸计算每一步的移动距离。
# 不再把步长写死为1。
func get_step_distance(_direction: Vector3) -> float:
	return grid_step


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
	if not screen_relative_move:
		if Input.is_action_pressed("move_right"):
			return Vector3.RIGHT
		if Input.is_action_pressed("move_left"):
			return Vector3.LEFT
		if Input.is_action_pressed("move_forward"):
			return Vector3.FORWARD
		if Input.is_action_pressed("move_back"):
			return Vector3.BACK
		return Vector3.ZERO

	# 关卡：WASD 相对屏幕，W = 屏幕右上；与 Q/E、墙面翻转无关。
	var axes := _get_screen_move_axes()
	var screen_up: Vector3 = axes[0]
	var screen_right: Vector3 = axes[1]

	var world := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		world = screen_up + screen_right
	elif Input.is_action_pressed("move_back"):
		world = -(screen_up + screen_right)
	elif Input.is_action_pressed("move_right"):
		world = screen_right - screen_up
	elif Input.is_action_pressed("move_left"):
		world = -(screen_right - screen_up)
	else:
		return Vector3.ZERO

	world.y = 0.0
	if world.length_squared() < 0.0001:
		return Vector3.ZERO

	return _snap_horizontal_axis(world.normalized())


func _get_screen_move_axes() -> Array[Vector3]:
	var screen_up := Vector3(0.0, 0.0, -1.0)
	var screen_right := Vector3(1.0, 0.0, 0.0)

	var cam := get_viewport().get_camera_3d()
	if cam != null:
		screen_up = Vector3(-cam.global_basis.z.x, 0.0, -cam.global_basis.z.z)
		screen_right = Vector3(cam.global_basis.x.x, 0.0, cam.global_basis.x.z)
		if screen_up.length_squared() < 0.0001:
			screen_up = Vector3(0.0, 0.0, -1.0)
		else:
			screen_up = screen_up.normalized()
		if screen_right.length_squared() < 0.0001:
			screen_right = Vector3(1.0, 0.0, 0.0)
		else:
			screen_right = screen_right.normalized()

	return [screen_up, screen_right]


func _snap_horizontal_axis(v: Vector3) -> Vector3:
	if absf(v.x) >= absf(v.z):
		return Vector3(signf(v.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(v.z))


func _is_cube_wall_collider(collider: Object) -> bool:
	if collider == null or cube_world == null:
		return false
	var walls := cube_world.get_node_or_null("WALLS")
	if walls == null:
		return false
	var node := collider as Node
	while node != null:
		if node.get_parent() == walls:
			return true
		node = node.get_parent()
	return false


func _destination_has_obstacle(destination: Vector3) -> bool:
	if cube_world == null or not cube_world.has_method("_collect_obstacle_boxes"):
		return false
	const HALF_CELL := 0.51
	for box in cube_world._collect_obstacle_boxes():
		if box == null or not is_instance_valid(box):
			continue
		var offset: Vector3 = box.global_position - destination
		if (
			absf(offset.x) < HALF_CELL
			and absf(offset.y) < HALF_CELL
			and absf(offset.z) < HALF_CELL
		):
			return true
	return false


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
	# Don't start a wall flip while airborne.
	if not is_on_floor():
		return

	if cube_world == null:
		return

	if not cube_world.has_method("can_flip"):
		return

	if not cube_world.can_flip():
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if not _is_cube_wall_collider(collision.get_collider()):
			continue

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

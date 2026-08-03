extends CharacterBody3D


# 重力与起跳力度。
@export var fall_acceleration := 75.0
@export var jump_impulse := 15.0

# 方向跳跃的水平速度。
@export var jump_horizontal_speed := 3.5

# 向下检测地面的距离。
@export var floor_probe_distance := 0.08

# 是否使用相对屏幕方向。
@export var screen_relative_move := true

# true：格子翻滚；false：普通滑动。
@export var use_grid_roll := true

# 普通滑动速度。
@export var walk_speed := 8.0

# 公共格子边长。
@export var grid_step := 1.0


@onready var pivot: Node3D = \
	$Pivot

@onready var visual_root: Node3D = \
	$Pivot/PlayerCube

@onready var visual_body: Node3D = \
	$Pivot/PlayerCube/Body

@onready var visual_face: Node3D = \
	$Pivot/PlayerCube/Face

@onready var collision_shape: CollisionShape3D = \
	$CollisionShape3D

@onready var roll_controller = \
	$RollController

@onready var jump_controller = \
	$JumpController

@onready var cube_world: Node3D = \
	get_parent().get_node_or_null("Node3D")


# 用于检测落地瞬间。
var was_on_floor := true

# 关卡重置位置。
var start_transform: Transform3D


func _ready() -> void:
	start_transform = global_transform
	add_to_group("player")

	jump_controller.setup(
		self,
		visual_root,
		visual_body
	)

	roll_controller.setup(
		self,
		visual_body,
		visual_face,
		collision_shape,
		cube_world
	)

	roll_controller.finished.connect(
		_on_roll_finished
	)


func reset_to_start() -> void:
	jump_controller.cancel()
	roll_controller.cancel()

	global_transform = start_transform
	velocity = Vector3.ZERO
	was_on_floor = true

	_reset_visual_state()


# 世界翻转完成后同步角色状态。
func sync_move_from_facing() -> void:
	jump_controller.cancel()
	roll_controller.cancel()

	velocity = Vector3.ZERO
	_reset_visual_state()

	was_on_floor = (
		is_on_floor()
		or has_floor_below()
	)


func _reset_visual_state() -> void:
	pivot.basis = Basis.IDENTITY
	visual_root.basis = Basis.IDENTITY
	visual_body.basis = Basis.IDENTITY
	visual_body.scale = Vector3.ONE


func _physics_process(delta: float) -> void:
	if not use_grid_roll:
		_physics_process_walk(delta)
		return

	var direction := get_input_direction()

	# 起跳蓄力期间保持静止，
	# 但仍然允许更新跳跃方向。
	if jump_controller.preparing:
		jump_controller.update_preparing_direction(
			direction,
		)

		velocity = Vector3.ZERO
		return

	# 跳跃期间由 JumpController 控制。
	if jump_controller.active:
		jump_controller.physics_update(
			delta,
			fall_acceleration,
			jump_horizontal_speed
		)

		move_and_slide()

		if is_on_floor() and velocity.y <= 0.0:
			jump_controller.finish()
			visual_body.land_squash()
			was_on_floor = true
		else:
			was_on_floor = false

		return

	# 翻滚期间由 RollController 控制位置。
	if roll_controller.active:
		velocity = Vector3.ZERO
		return

	var grounded := (
		is_on_floor()
		or has_floor_below()
	)

	if grounded:
		if velocity.y < 0.0:
			velocity.y = 0.0

		# 跳跃输入优先于翻滚。
		if Input.is_action_just_pressed("jump"):
			_start_jump(direction)
			return

		# 方向跳跃落地后等待方向键松开，
		# 防止自动补一次地面翻滚。
		if jump_controller.wait_for_move_release:
			if direction == Vector3.ZERO:
				jump_controller.wait_for_move_release = false
			else:
				velocity = Vector3.ZERO
				return

		if direction != Vector3.ZERO:
			roll_controller.start(
				direction,
				grid_step
			)
			return
	else:
		velocity.y -= fall_acceleration * delta

	# 非跳跃状态不进行水平滑动。
	velocity.x = 0.0
	velocity.z = 0.0

	move_and_slide()

	var on_floor_now := is_on_floor()

	if not was_on_floor and on_floor_now:
		visual_body.land_squash()

	was_on_floor = on_floor_now


# 开场道路等场景使用普通滑动模式。
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
		jump_controller.play_jump_sfx()
	elif velocity.y < 0.0:
		velocity.y = 0.0

	move_and_slide()

	var on_floor_now := is_on_floor()

	if (
		not was_on_floor
		and on_floor_now
		and visual_body
	):
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


func _start_jump(
	direction: Vector3
) -> void:
	if direction != Vector3.ZERO:
		visual_face.look_direction(direction)

	var started: bool = await jump_controller.start(
		jump_impulse,
		direction,
		grid_step
	)

	if started:
		was_on_floor = false


func _on_roll_finished(
	on_floor: bool
) -> void:
	was_on_floor = on_floor


# 检查角色脚下是否仍有地面。
func has_floor_below() -> bool:
	return test_move(
		global_transform,
		Vector3.DOWN * floor_probe_distance
	)


# 获取四方向格子输入。
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

	return _snap_horizontal_axis(
		world.normalized()
	)


func _get_screen_move_axes() -> Array[Vector3]:
	var screen_up := Vector3(
		0.0,
		0.0,
		-1.0
	)

	var screen_right := Vector3(
		1.0,
		0.0,
		0.0
	)

	var camera := get_viewport().get_camera_3d()

	if camera != null:
		screen_up = Vector3(
			-camera.global_basis.z.x,
			0.0,
			-camera.global_basis.z.z
		)

		screen_right = Vector3(
			camera.global_basis.x.x,
			0.0,
			camera.global_basis.x.z
		)

		if screen_up.length_squared() < 0.0001:
			screen_up = Vector3(
				0.0,
				0.0,
				-1.0
			)
		else:
			screen_up = screen_up.normalized()

		if screen_right.length_squared() < 0.0001:
			screen_right = Vector3(
				1.0,
				0.0,
				0.0
			)
		else:
			screen_right = screen_right.normalized()

	return [
		screen_up,
		screen_right
	]


func _snap_horizontal_axis(
	value: Vector3
) -> Vector3:
	if absf(value.x) >= absf(value.z):
		return Vector3(
			signf(value.x),
			0.0,
			0.0
		)

	return Vector3(
		0.0,
		0.0,
		signf(value.z)
	)

extends CharacterBody3D

signal died
var is_dead: bool = false

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

@export var jump_enabled_by_default: bool = false

@export_category("Debug")
@export var allow_jump_cheat: bool = true

var jump_enabled: bool = false

# 用于检测落地瞬间。
var was_on_floor := true

# 关卡重置位置。
var start_transform: Transform3D

var start_visual_body_position: Vector3

var start_collision_position: Vector3
var start_collision_size: Vector3

## 关卡边长 n（格数）。优先 cube_world.n，否则用 cube_half_extent*2。
func get_map_n() -> int:
	if cube_world != null:
		if "n" in cube_world:
			var n_val := int(cube_world.get("n"))
			if n_val > 0:
				return n_val
		if "cube_half_extent" in cube_world:
			var n_from_half := int(round(float(cube_world.get("cube_half_extent")) * 2.0))
			if n_from_half > 0:
				return n_from_half
	return 6


## 将水平轴校准到格子中心。
## 偶数 n → *.5；奇数 n → 整数。
func snap_grid_axis(value: float) -> float:
	if get_map_n() % 2 == 0:
		return snappedf(value - 0.5, 1.0) + 0.5
	return snappedf(value, 1.0)


## 只校准 XZ，保留 Y。
func snap_grid_xz(pos: Vector3) -> Vector3:
	return Vector3(snap_grid_axis(pos.x), pos.y, snap_grid_axis(pos.z))


func _ready() -> void:
	jump_enabled = jump_enabled_by_default
	
	if collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	
	start_transform = global_transform
	start_visual_body_position = visual_body.position
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
	
	start_collision_position = collision_shape.position

	var box_shape := collision_shape.shape as BoxShape3D
	if box_shape:
		start_collision_size = box_shape.size


func reset_to_start() -> void:
	# 每次关卡重置后恢复默认跳跃权限。
	jump_enabled = jump_enabled_by_default

	var box_shape := collision_shape.shape as BoxShape3D

	if box_shape:
		box_shape.size = start_collision_size
		collision_shape.position = start_collision_position
		
	is_dead = false
	collision_shape.set_deferred("disabled", false)
	
	jump_controller.cancel()
	roll_controller.cancel()

	global_transform = start_transform
	# XZ 按奇偶格校准到格子中心，Y 不变。
	global_position = snap_grid_xz(global_position)
	velocity = Vector3.ZERO
	was_on_floor = true

	_reset_visual_state()


func set_start_transform(xform: Transform3D) -> void:
	start_transform = xform


# 世界翻转完成后同步角色状态。
func sync_move_from_facing() -> void:
	jump_controller.cancel()
	roll_controller.cancel()

	velocity = Vector3.ZERO
	# XZ 按奇偶格校准到格子中心，Y 不变。
	global_position = snap_grid_xz(global_position)
	_reset_visual_state()

	was_on_floor = (
		is_on_floor()
		or has_floor_below()
	)

func _reset_visual_state() -> void:
	if visual_body.has_method("stop_shape_tween"):
		visual_body.stop_shape_tween()

	pivot.basis = Basis.IDENTITY
	visual_root.basis = Basis.IDENTITY

	visual_body.position = start_visual_body_position
	visual_body.basis = Basis.IDENTITY
	visual_body.scale = Vector3.ONE

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector3.ZERO
		return
		
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

		# 默认禁止跳跃；只有获得跳跃权限时才允许原地跳或方向跳。
		if (
			Input.is_action_just_pressed("jump")
			and can_jump()
		):
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
	elif (
		Input.is_action_just_pressed("jump")
		and can_jump()
	):
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
	# 防止其他调用路径绕过跳跃权限。
	if not can_jump():
		return

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

func die() -> void:
	if is_dead:
		return

	is_dead = true
	velocity = Vector3.ZERO

	if is_instance_valid(jump_controller):
		jump_controller.cancel()

	if is_instance_valid(roll_controller):
		roll_controller.cancel()
	
	# 死亡时让身体重新对齐世界坐标，
	# 保证压扁方向永远朝向地面。
	visual_body.basis = Basis.IDENTITY
	

	var box_shape := collision_shape.shape as BoxShape3D

	if box_shape:
		var height_scale: float = visual_body.death_height_scale
		var original_height: float = 1.0
		var new_height: float = original_height * height_scale

		box_shape.size.y = new_height

		# 保持碰撞体底面位置不变。
		collision_shape.position.y = -(
			original_height - new_height
		) * 0.5
	
	await visual_body.death_squash()
	
	died.emit()

# 临时测试：按 K 触发死亡。
func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_K
	):
		die()

func get_death_height_scale() -> float:
	return visual_body.death_height_scale

# 由弹跳板等机关调用：只控制“能否开始新的跳跃”。
# 离开弹跳板后不会打断已经开始的跳跃。
func set_jump_enabled(enabled: bool) -> void:
	jump_enabled = enabled

	# 若权限在蓄力阶段被收回，则取消尚未真正起跳的动作。
	if (
		not jump_enabled
		and is_instance_valid(jump_controller)
		and jump_controller.preparing
	):
		jump_controller.cancel()


func is_jump_enabled() -> bool:
	return jump_enabled


# 原地跳和“跳跃 + 移动”统一经过这里。
func can_jump() -> bool:
	return (
		jump_enabled
		and not is_dead
		and (
			is_on_floor()
			or has_floor_below()
		)
		and not roll_controller.active
		and not jump_controller.preparing
		and not jump_controller.active
	)

func _unhandled_key_input(event: InputEvent) -> void:
	if not allow_jump_cheat:
		return

	if is_dead:
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_J
	):
		set_jump_enabled(true)
		print("DEBUG：本关跳跃技能已解锁")
		get_viewport().set_input_as_handled()

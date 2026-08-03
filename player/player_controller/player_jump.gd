extends Node


# 完成一圈空翻所需时间。
@export var flip_duration := 0.40

# 跳跃音效：放到 res://audio/jump.mp3（或 .ogg / .wav）
@export var jump_sfx_path := "res://audio/jump.mp3"
@export var jump_sfx_volume_db := -4.0


var player: CharacterBody3D
var visual_root: Node3D
var visual_body: Node3D

# 跳跃状态。
var preparing := false
var active := false
var wait_for_move_release := false

# 当前跳跃数据。
var direction := Vector3.ZERO
var start_position := Vector3.ZERO
var target_position := Vector3.ZERO
var step_size := 1.0

var jump_elapsed := 0.0
var start_visual_basis := Basis.IDENTITY

# 用于取消尚未完成的异步起跳。
var _request_id := 0
var _jump_sfx: AudioStreamPlayer


func setup(
	player_node: CharacterBody3D,
	root_node: Node3D,
	body_node: Node3D
) -> void:
	player = player_node
	visual_root = root_node
	visual_body = body_node
	_setup_jump_sfx()


# 没有方向时原地跳，有方向时向相邻一格跳。
func start(
	jump_impulse: float,
	jump_direction: Vector3,
	grid_step: float
) -> bool:
	if (
		player == null
		or visual_root == null
		or visual_body == null
		or preparing
		or active
	):
		return false

	_request_id += 1
	var current_request := _request_id

	preparing = true
	active = false
	wait_for_move_release = false

	direction = jump_direction
	start_position = player.global_position
	step_size = grid_step
	target_position = start_position + direction * step_size

	jump_elapsed = 0.0
	start_visual_basis = visual_root.basis
	player.velocity = Vector3.ZERO

	# 起跳前压缩蓄力。
	await visual_body.jump_takeoff()

	# 重置关卡或世界翻转后，不再继续起跳。
	if current_request != _request_id:
		return false

	visual_body.jump_stretch()
	player.velocity.y = jump_impulse
	play_jump_sfx()

	preparing = false
	active = true
	return true


func _setup_jump_sfx() -> void:
	if _jump_sfx != null:
		return

	_jump_sfx = AudioStreamPlayer.new()
	_jump_sfx.name = "JumpSfx"
	_jump_sfx.bus = "Master"
	_jump_sfx.volume_db = jump_sfx_volume_db
	add_child(_jump_sfx)

	var resolved := jump_sfx_path
	if not ResourceLoader.exists(resolved):
		var found := ""
		for alt in ["res://audio/jump.ogg", "res://audio/jump.mp3", "res://audio/jump.wav"]:
			if alt != resolved and ResourceLoader.exists(alt):
				found = alt
				break
		if found.is_empty():
			return
		resolved = found

	var stream := load(resolved) as AudioStream
	if stream:
		_jump_sfx.stream = stream


func play_jump_sfx() -> void:
	if _jump_sfx and _jump_sfx.stream:
		_jump_sfx.play()


# 蓄力期间仍然可以读取方向键。
func update_preparing_direction(new_direction: Vector3) -> void:
	if not preparing or active or new_direction == Vector3.ZERO:
		return

	direction = new_direction
	target_position = start_position + direction * step_size


func physics_update(
	delta: float,
	fall_acceleration: float,
	horizontal_speed: float
) -> void:
	if not active:
		return

	jump_elapsed += delta
	player.velocity.y -= fall_acceleration * delta

	_update_horizontal_velocity(delta, horizontal_speed)
	_update_air_flip()


# 控制角色只向相邻一格移动。
func _update_horizontal_velocity(
	delta: float,
	horizontal_speed: float
) -> void:
	if direction == Vector3.ZERO:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		return

	var remaining := target_position - player.global_position
	remaining.y = 0.0

	var forward_distance := remaining.dot(direction)

	if forward_distance <= 0.001:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		return

	# 接近目标格时自动减速，避免越过目标。
	var allowed_speed := forward_distance / maxf(delta, 0.0001)
	var speed := minf(horizontal_speed, allowed_speed)

	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed


# 方向跳跃时，让整个 PlayerCube 完成一圈空翻。
func _update_air_flip() -> void:
	if direction == Vector3.ZERO:
		return

	var progress := clampf(
		jump_elapsed / maxf(flip_duration, 0.001),
		0.0,
		1.0
	)

	var axis := Vector3.UP.cross(direction).normalized()
	var angle := TAU * progress

	visual_root.basis = (
		Basis(axis, angle) * start_visual_basis
	).orthonormalized()


# 跳跃落地后结束动作，并对齐到完整格子。
func finish() -> void:
	wait_for_move_release = direction != Vector3.ZERO
	_snap_landing_to_grid()

	visual_root.basis = start_visual_basis
	player.velocity = Vector3.ZERO

	preparing = false
	active = false
	direction = Vector3.ZERO
	jump_elapsed = 0.0


# 落地结果只允许是起点格或相邻目标格。
# Y 高度保留物理落地结果，因此支持向上跳和向下跳。
func _snap_landing_to_grid() -> void:
	if direction == Vector3.ZERO:
		return

	var travelled := (
		player.global_position - start_position
	).dot(direction)

	var snapped_position := player.global_position

	if travelled >= step_size * 0.5:
		snapped_position.x = target_position.x
		snapped_position.z = target_position.z
	else:
		snapped_position.x = start_position.x
		snapped_position.z = start_position.z

	player.global_position = snapped_position


# 重置关卡或世界翻转时取消跳跃。
func cancel() -> void:
	_request_id += 1

	preparing = false
	active = false
	wait_for_move_release = false
	direction = Vector3.ZERO
	jump_elapsed = 0.0

	if is_instance_valid(player):
		player.velocity = Vector3.ZERO

	if is_instance_valid(visual_root):
		visual_root.basis = start_visual_basis

	if (
		is_instance_valid(visual_body)
		and visual_body.has_method("stop_shape_tween")
	):
		visual_body.stop_shape_tween()
		visual_body.scale = Vector3.ONE

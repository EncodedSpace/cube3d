extends CharacterBody3D

@export var speed = 8
@export var fall_acceleration = 75
@export var jump_impulse = 15
## How strongly the player must push into a wall before a face flip starts.
@export var flip_push_threshold = 0.35

var target_velocity = Vector3.ZERO
## Cumulative WASD frame; updated after each scene yaw so W follows player facing.
var move_basis: Basis = Basis.IDENTITY

@onready var cube_world: Node3D = get_parent().get_node_or_null("Node3D")


func sync_move_from_facing() -> void:
	var forward: Vector3 = -$Pivot.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	else:
		forward = forward.normalized()
	# looking_at makes -Z point along forward, so W (0,0,-1) maps to facing.
	move_basis = Basis.looking_at(forward)


func _physics_process(delta):
	var input := Vector3.ZERO

	if Input.is_action_pressed("move_right"):
		input.x += 1
	if Input.is_action_pressed("move_left"):
		input.x -= 1
	if Input.is_action_pressed("move_back"):
		input.z += 1
	if Input.is_action_pressed("move_forward"):
		input.z -= 1

	var direction := Vector3.ZERO
	if input != Vector3.ZERO:
		input = input.normalized()
		direction = move_basis * input
		direction.y = 0.0
		direction = direction.normalized()

		var local_dir: Vector3 = global_basis.orthonormalized().inverse() * direction
		local_dir.y = 0.0
		if local_dir.length_squared() > 0.0001:
			$Pivot.basis = Basis.looking_at(local_dir.normalized())

	target_velocity.x = direction.x * speed
	target_velocity.z = direction.z * speed

	if not is_on_floor():
		target_velocity.y = target_velocity.y - (fall_acceleration * delta)
	elif Input.is_action_just_pressed("jump"):
		target_velocity.y = jump_impulse

	velocity = target_velocity
	move_and_slide()

	_try_face_flip(direction)


func _try_face_flip(input_dir: Vector3) -> void:
	# Don't start a wall flip while airborne (e.g. jumping next to a wall).
	if not is_on_floor():
		return
	if cube_world == null or not cube_world.has_method("can_flip"):
		return
	if not cube_world.can_flip():
		return

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var normal := col.get_normal()

		# Floor contact — ignore. Walls and ceiling can flip.
		if normal.y > 0.55:
			continue

		# Must be pressing into the surface.
		var into_surface := -normal
		var push := maxf(
			input_dir.dot(into_surface),
			velocity.dot(into_surface) / maxf(speed, 0.001)
		)
		if push < flip_push_threshold:
			continue

		if cube_world.request_flip(normal, self):
			return

var start_transform: Transform3D

func _ready() -> void:
	start_transform = global_transform

func reset_to_start() -> void:
	global_transform = start_transform
	velocity = Vector3.ZERO
	target_velocity = Vector3.ZERO
	move_basis = Basis.IDENTITY
	$Pivot.basis = Basis.IDENTITY

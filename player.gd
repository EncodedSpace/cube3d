extends CharacterBody3D

@export var speed = 14
@export var fall_acceleration = 75
@export var jump_impulse = 20
## How strongly the player must push into a wall before a face flip starts.
@export var flip_push_threshold = 0.35

var target_velocity = Vector3.ZERO

@onready var cube_world: Node3D = get_parent().get_node_or_null("Node3D")


func _physics_process(delta):
	var direction = Vector3.ZERO

	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_back"):
		direction.z += 1
	if Input.is_action_pressed("move_forward"):
		direction.z -= 1

	if direction != Vector3.ZERO:
		direction = direction.normalized()
		$Pivot.basis = Basis.looking_at(direction)

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

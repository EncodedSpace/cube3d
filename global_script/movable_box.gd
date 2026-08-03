extends RigidBody3D

var start_transform: Transform3D


func _ready() -> void:
	start_transform = transform


func reset_to_start() -> void:
	# Clear motion first so physics won't shove the box after we restore pose.
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	transform = start_transform
	# Force the physics server to pick up the new transform immediately.
	if not freeze:
		sleeping = true

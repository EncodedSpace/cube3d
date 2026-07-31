extends Node3D

## Rotates the cube so a hit face becomes the new floor.
## Player is carried through the same rotation, then falls onto it.

@export var flip_duration: float = 0.55
@export var cube_half_extent: float = 3.0

var flipping: bool = false

signal flip_started
signal flip_finished


func get_center_global() -> Vector3:
	return to_global(Vector3(0.0, cube_half_extent, 0.0))


func can_flip() -> bool:
	return not flipping


func request_flip(collision_normal: Vector3, player: Node3D) -> bool:
	if flipping:
		return false

	# Collision normal points toward the player (into the room).
	# The face's outward direction is the opposite; that should become world down.
	var outward := _snap_to_axis(-collision_normal)
	if outward.dot(Vector3.DOWN) > 0.99:
		return false

	var rotation_quat := Quaternion(outward, Vector3.DOWN)
	if rotation_quat.get_angle() < 0.01:
		return false

	_animate_flip(rotation_quat, player)
	return true


func _snap_to_axis(v: Vector3) -> Vector3:
	var a := v.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector3(signf(v.x), 0.0, 0.0)
	if a.y >= a.z:
		return Vector3(0.0, signf(v.y), 0.0)
	return Vector3(0.0, 0.0, signf(v.z))


func _rotated_xform(xform: Transform3D, center: Vector3, q: Quaternion) -> Transform3D:
	return Transform3D(Basis(q) * xform.basis, center + q * (xform.origin - center))


func _animate_flip(rot: Quaternion, player: Node3D) -> void:
	flipping = true
	flip_started.emit()

	var center := get_center_global()
	var cube_start := global_transform
	var player_start := player.global_transform
	var player_scale := player.scale

	player.set_physics_process(false)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if "target_velocity" in player:
		player.target_velocity = Vector3.ZERO

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(
		func(t: float) -> void:
			var q := Quaternion.IDENTITY.slerp(rot, t)
			global_transform = _rotated_xform(cube_start, center, q)
			player.global_transform = _rotated_xform(player_start, center, q),
		0.0,
		1.0,
		flip_duration
	)

	await tween.finished

	global_transform.basis = global_transform.basis.orthonormalized()

	# Keep the player upright in world space so WASD stays camera-relative.
	var pos := player.global_position
	player.global_transform = Transform3D(Basis.IDENTITY, pos)
	player.scale = player_scale

	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if "target_velocity" in player:
		player.target_velocity = Vector3.ZERO

	player.set_physics_process(true)
	flipping = false
	flip_finished.emit()

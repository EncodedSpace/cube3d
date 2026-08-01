extends Node3D

@onready var eyes_visual: Node3D = $EyesVisual

@export var face_offset := 0.3
@export var base_height := 0.6

@export var move_time := 0.5
@export var rotate_time := 0.12

var face_tween: Tween


func look_direction(direction: Vector3) -> void:
	var target_position := Vector3(
		direction.x * face_offset,
		base_height,
		direction.z * face_offset
	)

	var target_rotation := 0.0

	if direction == Vector3.RIGHT:
		target_rotation = deg_to_rad(90.0)
	elif direction == Vector3.LEFT:
		target_rotation = deg_to_rad(-90.0)
	elif direction == Vector3.FORWARD:
		target_rotation = deg_to_rad(180.0)
	elif direction == Vector3.BACK:
		target_rotation = 0.0

	if face_tween:
		face_tween.kill()

	var start_position := eyes_visual.position
	var start_rotation := eyes_visual.rotation.y

	face_tween = create_tween()
	face_tween.set_parallel(true)
	face_tween.set_trans(Tween.TRANS_SINE)
	face_tween.set_ease(Tween.EASE_IN_OUT)

	# 位置平滑过渡
	face_tween.tween_method(
		func(value: float):
			eyes_visual.position = start_position.lerp(
				target_position,
				value
			),
		0.0,
		1.0,
		move_time
	)

	# 旋转平滑过渡
	face_tween.tween_method(
		func(value: float):
			eyes_visual.rotation.y = lerp_angle(
				start_rotation,
				target_rotation,
				value
			),
		0.0,
		1.0,
		rotate_time
	)
var travel_tween: Tween


func move_with_roll(direction: Vector3, duration: float) -> void:
	if travel_tween:
		travel_tween.kill()

	var pivot := (Vector3.DOWN + direction) * 0.5
	var axis := Vector3.UP.cross(direction).normalized()

	travel_tween = create_tween()
	travel_tween.set_trans(Tween.TRANS_LINEAR)

	travel_tween.tween_method(
		func(progress: float):
			# 沿着和方块相同的圆弧移动，但眼睛自身不翻转
			position = pivot + (-pivot).rotated(
				axis,
				deg_to_rad(90.0) * progress
			),
		0.0,
		1.0,
		duration
	)


func finish_roll() -> void:
	if travel_tween:
		travel_tween.kill()

	position = Vector3.ZERO

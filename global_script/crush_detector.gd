extends Node


@onready var box: RigidBody3D = get_parent() as RigidBody3D

var previous_velocity: Vector3 = Vector3.ZERO
var crush_started: bool = false

func _physics_process(_delta: float) -> void:
	previous_velocity = box.linear_velocity
	
func _ready() -> void:
	if box == null:
		push_error("CrushDetector 的父节点必须是 RigidBody3D")
		return

	box.contact_monitor = true
	box.max_contacts_reported = 8
	box.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if crush_started:
		return

	if not body.has_method("die"):
		return
		
	if not body.has_method("get_death_height_scale"):
		return
	
	var was_falling: bool = previous_velocity.y < -0.5
	var was_above: bool = (
		box.global_position.y
		> body.global_position.y + 0.25
	)

	if not was_falling or not was_above:
		return

	var player_collision := (
		body.get_node_or_null("CollisionShape3D")
		as CollisionShape3D
	)

	if player_collision == null:
		return

	var player_shape := player_collision.shape as BoxShape3D
	if player_shape == null:
		return

	crush_started = true

	# 记录压扁前的真实碰撞高度。
	var height_before: float = player_shape.size.y

	box.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	box.freeze = true
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO

	body.die()

	var height_scale: float = float(body.get_death_height_scale())
	var height_after: float = height_before * height_scale
	var fall_distance: float = height_before - height_after


	var start_transform: Transform3D = box.global_transform
	var target_transform: Transform3D = start_transform
	target_transform.origin += Vector3.DOWN * fall_distance

	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_method(
		func(progress: float) -> void:
			box.global_transform = start_transform.interpolate_with(
				target_transform,
				progress
			),
		0.0,
		1.0,
		0.35
	)
	await tween.finished

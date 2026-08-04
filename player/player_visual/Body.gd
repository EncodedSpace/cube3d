extends Node3D

@export_range(0.1, 1.0, 0.05)
var death_height_scale: float = 0.5

# 所有身体形变共用一个 Tween。
var shape_tween: Tween


func _ready() -> void:
	scale = Vector3.ONE


func stop_shape_tween() -> void:
	if shape_tween:
		shape_tween.kill()

	shape_tween = null


func _create_shape_tween() -> Tween:
	stop_shape_tween()

	shape_tween = create_tween()
	shape_tween.set_trans(Tween.TRANS_SINE)
	shape_tween.set_ease(Tween.EASE_OUT)
	return shape_tween


# 连续滚动开始前的轻微蓄力。
func start_squash() -> void:
	var tween := _create_shape_tween()

	tween.tween_property(
		self,
		"scale",
		Vector3(1.04, 0.96, 1.04),
		0.02
	)
	tween.tween_property(
		self,
		"scale",
		Vector3.ONE,
		0.02
	)

	# 用计时器等待，可避免 Tween 被取消后协程永久卡住。
	await get_tree().create_timer(0.04).timeout


# 一串连续滚动结束后的落地回弹。
func end_squash() -> void:
	var tween := _create_shape_tween()

	tween.tween_property(
		self,
		"scale",
		Vector3(1.10, 0.90, 1.10),
		0.08
	)
	tween.tween_property(
		self,
		"scale",
		Vector3.ONE,
		0.20
	)

	await get_tree().create_timer(0.28).timeout


# 起跳前压缩；结束后由 JumpController 决定是否真正起跳。
func jump_takeoff() -> void:
	var tween := _create_shape_tween()

	tween.tween_property(
		self,
		"scale",
		Vector3(1.10, 0.85, 1.10),
		0.09
	)

	await get_tree().create_timer(0.09).timeout


# 真正离地后播放拉伸和恢复。
func jump_stretch() -> void:
	var tween := _create_shape_tween()

	tween.tween_property(
		self,
		"scale",
		Vector3(0.80, 1.50, 0.80),
		0.10
	)
	tween.tween_property(
		self,
		"scale",
		Vector3.ONE,
		0.20
	)


# 跳跃落地动画。
func land_squash() -> void:
	var tween := _create_shape_tween()

	tween.tween_property(
		self,
		"scale",
		Vector3(1.12, 0.50, 1.12),
		0.08
	)
	tween.tween_property(
		self,
		"scale",
		Vector3(0.90, 1.20, 0.90),
		0.10
	)
	tween.tween_property(
		self,
		"scale",
		Vector3.ONE,
		0.22
	)

# 被重物压扁后的死亡动画。
# 被重物从上方压扁。
# 缩放的同时向下移动，保证底面固定在地面上。
func death_squash() -> void:
	var tween := _create_shape_tween()
	var start_position := position

	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)

	var final_scale := Vector3(1.20, death_height_scale, 1.20)

	# 向下移动，保证底面贴着地面。
	var final_position := (
		start_position
		+ Vector3.DOWN * ((1.0 - final_scale.y) * 0.2)
	)

	tween.tween_property(
		self,
		"scale",
		final_scale,
		0.35
	)

	tween.tween_property(
		self,
		"position",
		final_position,
		0.35
	)

	await tween.finished

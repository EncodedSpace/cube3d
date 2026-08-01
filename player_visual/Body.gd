extends Node3D

# 所有身体形变共用一个 Tween。
# 新动作开始时会停止旧动作，避免多个缩放动画互相打架。
var shape_tween: Tween


func _ready() -> void:
	scale = Vector3.ONE


# 停止当前身体形变动画。
func stop_shape_tween() -> void:
	if shape_tween:
		shape_tween.kill()

	shape_tween = null


# 连续滚动开始前的轻微蓄力。
func start_squash() -> void:
	stop_shape_tween()

	shape_tween = create_tween()
	shape_tween.set_trans(Tween.TRANS_SINE)
	shape_tween.set_ease(Tween.EASE_OUT)

	# 快速轻微压缩。
	shape_tween.tween_property(
		self,
		"scale",
		Vector3(1.04, 0.96, 1.04),
		0.02
	)

	# 快速恢复。
	shape_tween.tween_property(
		self,
		"scale",
		Vector3.ONE,
		0.02
	)

	await shape_tween.finished


# 一串连续滚动结束后的落地回弹。
func end_squash() -> void:
	stop_shape_tween()

	shape_tween = create_tween()
	shape_tween.set_trans(Tween.TRANS_SINE)
	shape_tween.set_ease(Tween.EASE_OUT)

	# 落地瞬间压扁。
	shape_tween.tween_property(
		self,
		"scale",
		Vector3(1.10, 0.90, 1.10),
		0.08
	)

	# 较慢地恢复原形。
	shape_tween.tween_property(
		self,
		"scale",
		Vector3.ONE,
		0.20
	)

	await shape_tween.finished


# 起跳动画。
# 先压缩，压缩结束后函数返回，让 Player 真正起跳。
# 随后的拉伸与恢复会自动继续播放。
func jump_takeoff() -> void:
	stop_shape_tween()

	shape_tween = create_tween()
	shape_tween.set_trans(Tween.TRANS_SINE)
	shape_tween.set_ease(Tween.EASE_OUT)

	# 起跳前短暂压缩蓄力。
	shape_tween.tween_property(
		self,
		"scale",
		Vector3(1.1, 0.85, 1.10),
		0.09
	)

	await shape_tween.finished

	# 离地时纵向拉长。
	shape_tween = create_tween()
	shape_tween.set_trans(Tween.TRANS_SINE)
	shape_tween.set_ease(Tween.EASE_OUT)

	shape_tween.tween_property(
		self,
		"scale",
		Vector3(0.80,1.50,0.80),
		0.10
	)

	# 空中恢复正常形状。
	shape_tween.tween_property(
		self,
		"scale",
		Vector3.ONE,
		0.20
	)


# 跳跃落地动画。
func land_squash() -> void:
	stop_shape_tween()

	shape_tween = create_tween()
	shape_tween.set_trans(Tween.TRANS_SINE)
	shape_tween.set_ease(Tween.EASE_OUT)

	# 落地瞬间明显压扁。
	shape_tween.tween_property(
		self,
		"scale",
		Vector3(1.12, 0.50, 1.12),
		0.08
	)
	# 轻微反向回弹
	shape_tween.tween_property(
		self,
		"scale",
		Vector3(0.90, 1.20, 0.90),
		0.10
	)
	# 柔和恢复。
	shape_tween.tween_property(
		self,
		"scale",
		Vector3.ONE,
		0.22
	)

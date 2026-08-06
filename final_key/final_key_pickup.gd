extends Area3D

## 终局按钮：
## 玩家碰到后按钮下压并保持，不再消失，同时激活终点出口。

@export var press_depth: float = 0.10
@export var press_duration: float = 0.18

@onready var button_cap: Node3D = (
	get_node_or_null("ButtonVisual/ButtonCap") as Node3D
)

var tools_root: Node3D
var _pressed: bool = false
var _cap_start_position: Vector3


func _ready() -> void:
	if button_cap != null:
		_cap_start_position = button_cap.position


func setup(root: Node3D) -> void:
	tools_root = root

	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	call_deferred("_check_initial_overlaps")


## 由 cube_world 调用，使按钮跟随所在墙面裁切显隐。
func apply_cutaway_visibility(wall_visible: bool) -> void:
	visible = wall_visible

	# 按下后不再检测，但按钮模型仍然保留。
	set_deferred(
		"monitoring",
		wall_visible and not _pressed
	)

	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(
				"disabled",
				not wall_visible or _pressed
			)


func _check_initial_overlaps() -> void:
	await get_tree().physics_frame

	if _pressed or not monitoring:
		return

	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_press_button()
			return


func _on_body_entered(body: Node3D) -> void:
	if _pressed:
		return

	if not body.is_in_group("player"):
		return

	_press_button()


func _press_button() -> void:
	if _pressed:
		return

	_pressed = true

	# 关闭后续触发，按钮节点本身不删除。
	set_deferred("monitoring", false)

	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(
				"disabled",
				true
			)

	# 按钮帽沿自身局部 Y 轴向下移动，并保持按下状态。
	if button_cap != null:
		var target_position := _cap_start_position
		target_position.y -= press_depth

		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(
			button_cap,
			"position",
			target_position,
			press_duration
		)

	# 激活终点锅。
	if (
		tools_root != null
		and tools_root.has_method("unlock_exit")
	):
		tools_root.unlock_exit()

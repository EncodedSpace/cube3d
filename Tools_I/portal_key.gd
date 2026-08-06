extends Area3D

## 传送门机关：
## 玩家接触后扳动拉杆、解锁传送门，并保留在场景中。


var tools_root: Node3D
var _activated := false

@onready var lever_pivot: Node3D = get_node_or_null(
	"SwitchVisual/LeverPivot"
) as Node3D

@onready var collision_shape: CollisionShape3D = get_node_or_null(
	"CollisionShape3D"
) as CollisionShape3D


func setup(root: Node3D) -> void:
	tools_root = root

	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	call_deferred("_check_initial_overlaps")


## 跟随机关所在墙面的裁切显隐。
func apply_cutaway_visibility(wall_visible: bool) -> void:
	visible = wall_visible

	# 激活后机关保留，但不再检测玩家。
	monitoring = wall_visible and not _activated

	if collision_shape != null:
		collision_shape.disabled = not wall_visible or _activated


func _check_initial_overlaps() -> void:
	if _activated or not monitoring:
		return

	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_activate_switch()
			return


func _on_body_entered(body: Node3D) -> void:
	if _activated:
		return

	if not body.is_in_group("player"):
		return

	_activate_switch()


func _activate_switch() -> void:
	if _activated:
		return

	_activated = true

	# body_entered 信号执行期间不能直接修改 monitoring，
	# 必须延迟到当前物理回调结束后再关闭。
	set_deferred("monitoring", false)

	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)

	_play_lever_animation()

	if tools_root != null and tools_root.has_method("unlock_portals"):
		tools_root.unlock_portals()


func _play_lever_animation() -> void:
	if lever_pivot == null:
		push_warning("Portal_Key 没有找到 SwitchVisual/LeverPivot")
		return

	var tween := create_tween()

	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)

	# 从初始的负角度扳到另一侧。
	tween.tween_property(
		lever_pivot,
		"rotation:z",
		deg_to_rad(40.0),
		0.28
	)

	# 轻微回弹，让动作不那么僵硬。
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		lever_pivot,
		"rotation:z",
		deg_to_rad(32.0),
		0.14
	)

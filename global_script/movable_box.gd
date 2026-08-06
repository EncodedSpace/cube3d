extends RigidBody3D

## 可推动箱子。
## fall_when_on_ceiling：
## - 只绑天花板 → 强制显示、重力下落；落地停在 StaticBox 上才死亡
## - 天花板+侧墙（或地板）→ 普通随墙显隐，不强制显示、不掉落、不触发死亡
## - 已经真正掉起来之后，即使中途绑定变化，仍会把这次下落完成
## 下落期间由 is_blocking_cube_motion() 阻止立方体翻转/旋转。


@export var fall_when_on_ceiling := false

## 认为已经「开始掉落」的向下速度阈值。
const FALL_SPEED := 0.35
## 落地停稳速度阈值。
const SETTLE_SPEED := 0.12
## 停稳后连续多少物理帧才允许判死（避免下落途中短暂减速误判）。
const SETTLE_FRAMES_REQUIRED := 8
## 砸中判定：水平中心距上限。旁落/擦边不算压在箱子上。
const LAND_LATERAL_MAX := 0.4
## 砸中判定：相对 StaticBox，箱子中心至少高出这么多（世界 Y）。
const LAND_MIN_ABOVE := 0.55
## 砸中判定：相对 StaticBox，箱子中心最多高出这么多（一格叠放约 1）。
const LAND_MAX_ABOVE := 1.25

var start_transform: Transform3D
var ceiling_falling := false
var _fail_triggered := false
## 已离开天花板并产生过明显下落，才允许判定砸到 StaticBox。
var _has_fallen_from_ceiling := false
var _settle_frames := 0
## 记录开局的 fall_when_on_ceiling，reset 时恢复。
var _fall_when_on_ceiling_default := false


func _ready() -> void:
	start_transform = transform
	_fall_when_on_ceiling_default = fall_when_on_ceiling
	if fall_when_on_ceiling:
		lock_rotation = true
		gravity_scale = 1.0
		contact_monitor = true
		max_contacts_reported = 8
		continuous_cd = true
		set_physics_process(true)
	else:
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if is_locked_as_static() or not fall_when_on_ceiling or _fail_triggered:
		return

	var cube := _find_cube_world()
	var hold := cube != null and bool(cube.get("_hold_props_frozen"))
	if hold:
		_settle_frames = 0
		return

	_update_ceiling_fall_state(cube)

	if not ceiling_falling:
		_settle_frames = 0
		return

	# 记录是否已经真正掉起来了（离开天花板后向下运动）。
	if _has_fallen_from_ceiling == false and linear_velocity.y < -FALL_SPEED:
		_has_fallen_from_ceiling = true
		_settle_frames = 0

	if not _has_fallen_from_ceiling:
		_settle_frames = 0
		return

	if _is_nearly_settled():
		_settle_frames += 1
	else:
		_settle_frames = 0

	# 必须：已下落过 + 连续停稳 + 正压在 StaticBox 上，才判死。
	if _settle_frames >= SETTLE_FRAMES_REQUIRED and _contacting_staticbox():
		_trigger_fail_on_staticbox()


func reset_to_start() -> void:
	if has_meta("locked_as_static"):
		remove_meta("locked_as_static")
	fall_when_on_ceiling = _fall_when_on_ceiling_default
	ceiling_falling = false
	_fail_triggered = false
	_has_fallen_from_ceiling = false
	_settle_frames = 0
	gravity_scale = 1.0 if fall_when_on_ceiling else 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	transform = start_transform
	freeze = false
	set_physics_process(fall_when_on_ceiling)
	if fall_when_on_ceiling:
		sleeping = true


func is_blocking_cube_motion() -> bool:
	return fall_when_on_ceiling and ceiling_falling and not is_locked_as_static()


## G 收集后等：变成与 StaticBox 相同的固定块（冻住、不再下落/重绑）。
func lock_as_static() -> void:
	if is_locked_as_static():
		return
	set_meta("locked_as_static", true)
	fall_when_on_ceiling = false
	ceiling_falling = false
	_has_fallen_from_ceiling = false
	_fail_triggered = false
	_settle_frames = 0
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	sleeping = true
	set_physics_process(false)
	# 保证碰撞可用；显隐交给裁切。
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = false
	var cube := _find_cube_world()
	if cube != null and cube.has_method("mark_prop_fixed_like_static"):
		cube.mark_prop_fixed_like_static(self)


func is_locked_as_static() -> bool:
	return has_meta("locked_as_static") and bool(get_meta("locked_as_static"))


## 由 cube_world 裁切刷新调用。
## 返回 true：本帧自管显隐（只绑天花板 / 已真正下落中）。
## 返回 false：走普通随墙显隐。
## 注意：下落用更严的绑墙判定，不能直接用裁切传入的 bound_walls（容差 0.25 会把贴边误判成天花板+侧墙）。
func sync_ceiling_fall(_bound_walls: Array, hold_frozen: bool) -> bool:
	if is_locked_as_static() or not fall_when_on_ceiling or _fail_triggered:
		return false
	if has_meta("locked_in_e1") and bool(get_meta("locked_in_e1")):
		_exit_ceiling_fall_mode()
		return false

	var ceiling_only := _is_ceiling_only_for_fall()
	if ceiling_only:
		_enter_ceiling_fall_mode()
	elif ceiling_falling and not _has_fallen_from_ceiling:
		# 还没真正掉下来，已不是「只绑天花板」（如真正的天花板+侧墙棱角）→ 取消特殊规则。
		_exit_ceiling_fall_mode()
		return false
	# 已真正掉起来：即使绑定变成天花板+侧墙，也继续完成这次下落。

	if not ceiling_falling:
		return false

	if hold_frozen:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
		_force_visible_solid()
		return true

	_force_visible_solid()
	freeze = false
	sleeping = false
	return true


func _update_ceiling_fall_state(cube: Node) -> void:
	if cube == null:
		return
	if has_meta("locked_in_e1") and bool(get_meta("locked_in_e1")):
		return

	var ceiling_only := _is_ceiling_only_for_fall()

	if ceiling_only:
		_enter_ceiling_fall_mode()
		_force_visible_solid()
		freeze = false
		sleeping = false
		return

	if not ceiling_falling:
		return

	# 尚未真正下落却已不是「只绑天花板」：退出特殊状态。
	if not _has_fallen_from_ceiling:
		_exit_ceiling_fall_mode()
		return

	# 已真正掉起来：即使中途绑定变化，仍完成这次下落。
	if not _is_nearly_settled():
		_force_visible_solid()
		freeze = false
		sleeping = false
		return

	if _settle_frames < SETTLE_FRAMES_REQUIRED:
		_force_visible_solid()
		freeze = false
		sleeping = false
		return

	# 砸在 StaticBox 正上方 → 死亡。
	if _contacting_staticbox():
		_trigger_fail_on_staticbox()
		return

	# 落到地板上 → 正常结束下落。
	if _has_floor_support_for_fall():
		_exit_ceiling_fall_mode()
		return

	# 擦侧墙导致短暂「停稳」：不算落地，继续下落。
	# 若此处退出，裁切会把箱子冻在半空（level6/7 侧墙掉落卡住的主因）。
	_force_visible_solid()
	freeze = false
	sleeping = false
	_settle_frames = 0


## 下落专用「只绑天花板」：用更严绑墙，避免裁切宽容差导致贴边要多转几次才掉。
func _is_ceiling_only_for_fall() -> bool:
	return _is_ceiling_only_bound(_fall_bind_walls())


func _fall_bind_walls() -> Array:
	var cube := _find_cube_world()
	if cube == null:
		return []
	if cube.has_method("get_nearest_walls_for_fall"):
		return cube.get_nearest_walls_for_fall(self)
	if cube.has_method("get_nearest_walls_for"):
		return cube.get_nearest_walls_for(self)
	return []


func _has_floor_support_for_fall() -> bool:
	for item in _fall_bind_walls():
		var wall := item as Node3D
		if wall != null and is_instance_valid(wall) and _wall_is_floor(wall):
			return true
	return false


func _enter_ceiling_fall_mode() -> void:
	if not ceiling_falling:
		_has_fallen_from_ceiling = false
		_settle_frames = 0
	ceiling_falling = true
	gravity_scale = 1.0


func _exit_ceiling_fall_mode() -> void:
	ceiling_falling = false
	_has_fallen_from_ceiling = false
	_settle_frames = 0
	gravity_scale = 1.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _contacting_staticbox() -> bool:
	for collider in get_colliding_bodies():
		var static_box := _find_static_box_root(collider)
		if static_box != null and _is_resting_on_top_of(static_box):
			return true
	return false


## 必须大致叠在 StaticBox 正上方才算砸中；侧碰/掉旁边不算。
func _is_resting_on_top_of(static_box: Node3D) -> bool:
	var my_pos := _collision_center(self)
	var box_pos := _collision_center(static_box)
	var offset := my_pos - box_pos
	var lateral := Vector3(offset.x, 0.0, offset.z)
	if lateral.length() > LAND_LATERAL_MAX:
		return false
	if offset.y < LAND_MIN_ABOVE or offset.y > LAND_MAX_ABOVE:
		return false
	return true


func _collision_center(body: Node3D) -> Vector3:
	for child in body.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return (child as CollisionShape3D).global_position
	return body.global_position


func _find_static_box_root(node: Node) -> Node3D:
	var n: Node = node
	while n != null:
		var name_str := String(n.name)
		if "StaticBox" in name_str and "MovableBox" not in name_str and n is Node3D:
			return n as Node3D
		n = n.get_parent()
	return null


func _is_static_box(node: Node) -> bool:
	return _find_static_box_root(node) != null


func _trigger_fail_on_staticbox() -> void:
	if _fail_triggered:
		return
	_fail_triggered = true
	ceiling_falling = false
	_has_fallen_from_ceiling = false
	_settle_frames = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true

	var player := _find_player()
	if player != null and player.has_method("die"):
		player.call_deferred("die")
	else:
		push_warning("MovableBox: landed on StaticBox but Player.die() not found")


func _force_visible_solid() -> void:
	visible = true
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = false


## 绑定面里只有天花板（不含侧墙/地板）时才启用掉落规则。
func _is_ceiling_only_bound(bound_walls: Array) -> bool:
	if bound_walls.is_empty():
		return false
	var has_ceiling := false
	for item in bound_walls:
		var wall := item as Node3D
		if wall == null or not is_instance_valid(wall):
			continue
		if _wall_is_ceiling(wall):
			has_ceiling = true
		else:
			return false
	return has_ceiling


func _wall_is_ceiling(wall: Node3D) -> bool:
	var outward := -wall.global_transform.basis.y.normalized()
	return outward.y > 0.7


func _wall_is_floor(wall: Node3D) -> bool:
	var outward := -wall.global_transform.basis.y.normalized()
	return outward.y < -0.7


func _is_nearly_settled() -> bool:
	# 不要把 freeze 当成落稳：翻转 hold 时也会 freeze，会误判死。
	return linear_velocity.length() <= SETTLE_SPEED and angular_velocity.length() <= SETTLE_SPEED


func _find_cube_world() -> Node:
	var n: Node = self
	while n != null:
		if n.has_method("update_cutaway_visibility"):
			return n
		n = n.get_parent()
	return null


func _find_player() -> Node:
	var cube := _find_cube_world()
	if cube == null:
		return null
	var host := cube.get_parent()
	if host == null:
		return null
	return host.get_node_or_null("Player")

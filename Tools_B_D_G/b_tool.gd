extends RigidBody3D

## B 道具：玩家可自由进出。
## 初始冻结；G 被收集后启用真实物理重力，并与 WALLS 碰撞。
## 开重力后贴面显隐 / 天花板下落与 MovableBox 相同：
## - 只绑天花板 → 强制显示、重力下落
## - 天花板+侧墙（或地板）→ 普通随墙显隐，不强制显示、不特殊下落
## - 已经真正掉起来之后，即使中途绑定变化，仍会把这次下落完成
## 落入 D 后吸附，不再移动。
## B 砸到 StaticBox 不会让玩家死亡（与 MovableBox 的唯一差异）。


var gravity_enabled := false
var adsorbed := false

## 与 MovableBox 相同的天花板下落状态。
var ceiling_falling := false
var _has_fallen_from_ceiling := false
var _settle_frames := 0

const FALL_SPEED := 0.35
const SETTLE_SPEED := 0.12
const SETTLE_FRAMES_REQUIRED := 8


func _ready() -> void:
	gravity_scale = 0.0
	freeze = true
	# Layer 4: D_Wall Area 可检测；Mask 1: 与 WALLS（默认 layer 1）碰撞。
	collision_layer = 4
	collision_mask = 1
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	add_to_group("b_tool")
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if not gravity_enabled or adsorbed:
		return

	var cube := _find_cube_world()
	var hold := cube != null and bool(cube.get("_hold_props_frozen"))
	if hold:
		_settle_frames = 0
		return

	_update_ceiling_fall_state()

	if not ceiling_falling:
		_settle_frames = 0
		return

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


## 下落期间阻止立方体翻转（与 MovableBox 一致）。
func is_blocking_cube_motion() -> bool:
	return gravity_enabled and not adsorbed and ceiling_falling


## 由 cube_world 裁切刷新调用。
## 返回 true：本帧自管显隐（只绑天花板 / 已真正下落中）。
## 返回 false：走普通随墙显隐（apply_cutaway_visibility）。
func sync_ceiling_fall(_bound_walls: Array, hold_frozen: bool) -> bool:
	if not gravity_enabled or adsorbed:
		_exit_ceiling_fall_mode()
		return false

	var ceiling_only := _is_ceiling_only_for_fall()
	if ceiling_only:
		_enter_ceiling_fall_mode()
	elif ceiling_falling and not _has_fallen_from_ceiling:
		_exit_ceiling_fall_mode()
		return false

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


## 普通贴面显隐（非天花板特殊下落时）：与 MovableBox 相同——隐则冻、关碰撞。
func apply_cutaway_visibility(wall_visible: bool) -> void:
	if adsorbed:
		# 与 D 合体后：跟墙贴面隐藏，半透明外观在可见时保留。
		visible = wall_visible
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_set_collision_shapes_disabled(true)
		collision_layer = 0
		return

	if not gravity_enabled:
		visible = wall_visible
		_set_collision_shapes_disabled(not wall_visible)
		return

	# 开重力后：跟墙显隐；隐藏时冻结（与 MovableBox 一致）。
	visible = wall_visible
	_set_collision_shapes_disabled(not wall_visible)
	var hold := _is_cube_holding_fallables()
	if not wall_visible or hold:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
	elif get_tree() != null and not get_tree().paused:
		freeze = false
		sleeping = false


## 由 D_Wall 调用，B 被吸附到 D 上。
func adsorb_to_d(d_global_pos: Vector3, _host_d: Node3D = null) -> void:
	adsorbed = true
	gravity_enabled = false
	gravity_scale = 0.0
	_exit_ceiling_fall_mode()
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform.origin = d_global_pos
	# 可通过合体：不再挡人；显隐交给贴面裁切。
	collision_layer = 0
	collision_mask = 0
	_set_collision_shapes_disabled(true)
	set_physics_process(false)
	var cube := _find_cube_world()
	if cube != null and cube.has_method("invalidate_prop_cutaway_cache"):
		cube.invalidate_prop_cutaway_cache(self)


## 由 G 道具调用，开启重力。
func enable_gravity() -> void:
	if adsorbed:
		return
	gravity_enabled = true
	gravity_scale = 1.0
	collision_layer = 4
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_set_collision_shapes_disabled(false)
	set_physics_process(true)
	var cube := _find_cube_world()
	if cube == null:
		return
	if cube.has_method("invalidate_prop_cutaway_cache"):
		cube.invalidate_prop_cutaway_cache(self)
	# 即便没有缓存 API（如 level5），也要立刻刷新，否则 B 可能一直保持隐藏/冻结观感。
	if cube.has_method("update_cutaway_visibility"):
		cube.update_cutaway_visibility()


## 复原到「G 已收集、尚未落入 D」：取消吸附、不透明。
func restore_after_g_collected(defer_gravity: bool = false) -> void:
	adsorbed = false
	collision_layer = 4
	collision_mask = 1
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_exit_ceiling_fall_mode()
	set_transparency(1.0)
	if defer_gravity:
		gravity_enabled = false
		gravity_scale = 0.0
		freeze = true
		set_physics_process(false)
	else:
		enable_gravity()


func set_transparency(alpha: float) -> void:
	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mi:
		return
	var src_mat := mi.get_active_material(0)
	var mat: StandardMaterial3D
	if src_mat != null and src_mat is StandardMaterial3D:
		mat = (src_mat as StandardMaterial3D).duplicate()
	else:
		mat = StandardMaterial3D.new()
		if src_mat != null:
			mat.albedo_color = src_mat.albedo_color
	mi.material_override = mat
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = alpha


func _update_ceiling_fall_state() -> void:
	var ceiling_only := _is_ceiling_only_for_fall()

	if ceiling_only:
		_enter_ceiling_fall_mode()
		_force_visible_solid()
		freeze = false
		sleeping = false
		return

	if not ceiling_falling:
		return

	if not _has_fallen_from_ceiling:
		_exit_ceiling_fall_mode()
		return

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

	# B 不因砸中 StaticBox 弄死玩家；落到地板或停稳有支撑则结束特殊下落。
	if _has_floor_support_for_fall():
		_exit_ceiling_fall_mode()
		return

	# 擦侧墙短暂停稳：继续下落。
	_force_visible_solid()
	freeze = false
	sleeping = false
	_settle_frames = 0


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
	if gravity_enabled and not adsorbed:
		gravity_scale = 1.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _force_visible_solid() -> void:
	visible = true
	_set_collision_shapes_disabled(false)


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
	return linear_velocity.length() <= SETTLE_SPEED and angular_velocity.length() <= SETTLE_SPEED


func _set_collision_shapes_disabled(disabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = disabled


func _is_cube_holding_fallables() -> bool:
	var cube := _find_cube_world()
	if cube == null:
		return false
	return bool(cube.get("_hold_props_frozen"))


func _find_cube_world() -> Node:
	var n: Node = self
	while n != null:
		if n.has_method("update_cutaway_visibility"):
			return n
		n = n.get_parent()
	return null

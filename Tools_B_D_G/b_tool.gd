extends RigidBody3D

@export var adsorb_duration: float = 0.58
@export var adsorb_lift: float = 0.16
@export var cage_fade_duration: float = 0.6
@export_range(0.1, 1.0, 0.01) var cage_end_scale_ratio: float = 0.9
## B 道具：玩家可自由进出。
## 初始冻结；G 被收集后启用真实物理重力，并与 WALLS 碰撞。
## 开重力后贴面显隐 / 天花板下落与 MovableBox 相同：
## - 只绑天花板 → 强制显示、重力下落
## - 天花板+侧墙（或地板）→ 普通随墙显隐，不强制显示、不特殊下落
## - 已经真正掉起来之后，即使中途绑定变化，仍会把这次下落完成
## 落入 D 后吸附，不再移动。
## B 砸到 StaticBox 不会让玩家死亡（与 MovableBox 的唯一差异）。

@onready var cage_visual: Node3D = get_node_or_null("CageVisual") as Node3D
@onready var cage_blocker: StaticBody3D = (
	get_node_or_null("CageBlocker") as StaticBody3D
)

var gravity_enabled := false
var adsorbed := false

var _unlocking := false
var _cage_removed := false
var _adsorb_tween: Tween
var _cage_tween: Tween
var _cage_start_scale := Vector3.ONE
var _cage_materials: Array[BaseMaterial3D] = []
var _cage_base_colors: Array[Color] = []
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
	collision_layer = 4
	collision_mask = 1
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	add_to_group("b_tool")
	set_physics_process(false)

	if cage_visual != null:
		_cage_start_scale = cage_visual.scale
		_prepare_cage_materials()
		_restore_cage()
	else:
		_set_cage_collision_enabled(false)

	call_deferred("_ignore_player_collision")


func _physics_process(_delta: float) -> void:
	if not gravity_enabled or adsorbed:
		return

	if _is_cube_holding_fallables():
		_settle_frames = 0
		return

	_update_ceiling_fall_state()

	if not ceiling_falling:
		_settle_frames = 0
		return

	if not _has_fallen_from_ceiling and linear_velocity.y < -FALL_SPEED:
		_has_fallen_from_ceiling = true
		_settle_frames = 0

	if not _has_fallen_from_ceiling:
		_settle_frames = 0
		return

	if _is_nearly_settled():
		_settle_frames += 1
	else:
		_settle_frames = 0


func is_blocking_cube_motion() -> bool:
	return gravity_enabled and ceiling_falling and not adsorbed


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

	_force_visible_solid()

	if hold_frozen:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
	else:
		freeze = false
		sleeping = false

	return true


func apply_cutaway_visibility(wall_visible: bool) -> void:
	var hold := _is_cube_holding_fallables()

	if adsorbed:
		visible = wall_visible
		_set_collision_shapes_disabled(true)
		_set_cage_collision_enabled(false)
		collision_layer = 0
		collision_mask = 0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
		return

	if gravity_enabled and sync_ceiling_fall([], hold):
		_set_collision_shapes_disabled(false)
		return

	visible = wall_visible

	if not _cage_removed:
		_set_cage_collision_enabled(wall_visible)

	if not gravity_enabled:
		_set_collision_shapes_disabled(not wall_visible)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
		return

	_set_collision_shapes_disabled(not wall_visible)
	if not wall_visible or hold:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
	elif get_tree() != null and not get_tree().paused:
		freeze = false
		sleeping = false


## 由 D_Wall 调用，B 被吸附到 D 上。
func adsorb_to_d(target_global_position: Vector3, _host_d: Node3D = null) -> void:
	if adsorbed:
		return

	_kill_adsorb_tween()
	_hide_cage_immediately()

	adsorbed = true
	gravity_enabled = false
	_unlocking = false
	gravity_scale = 0.0
	_exit_ceiling_fall_mode()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	sleeping = false
	collision_layer = 0
	collision_mask = 0
	_set_collision_shapes_disabled(true)
	set_physics_process(false)

	var duration := maxf(adsorb_duration, 0.05)
	var middle_position := global_position.lerp(
		target_global_position,
		0.42
	)
	middle_position += Vector3.UP * adsorb_lift

	_adsorb_tween = create_tween()
	_adsorb_tween.tween_property(
		self,
		"global_position",
		middle_position,
		duration * 0.42
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_adsorb_tween.tween_property(
		self,
		"global_position",
		target_global_position,
		duration * 0.58
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	var cube := _find_cube_world()
	if cube != null and cube.has_method("invalidate_prop_cutaway_cache"):
		cube.invalidate_prop_cutaway_cache(self)


## 由 G 道具调用，开启重力。
func enable_gravity() -> void:
	if adsorbed or gravity_enabled or _unlocking:
		return

	if cage_visual == null or _cage_removed:
		_set_cage_collision_enabled(false)
		_activate_gravity()
		return

	_unlocking = true
	_fade_cage()


## 复原到「G 已收集、尚未落入 D」：取消吸附、不透明。
func restore_after_g_collected(defer_gravity: bool = false) -> void:
	_kill_adsorb_tween()
	_hide_cage_immediately()

	adsorbed = false
	collision_layer = 4
	collision_mask = 1
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_exit_ceiling_fall_mode()
	set_transparency(1.0)
	_set_collision_shapes_disabled(false)

	if defer_gravity:
		gravity_enabled = false
		gravity_scale = 0.0
		freeze = true
		set_physics_process(false)
	else:
		_activate_gravity()


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


func _activate_gravity() -> void:
	if adsorbed:
		return

	_unlocking = false
	gravity_enabled = true
	gravity_scale = 1.0
	collision_layer = 4
	collision_mask = 1
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_set_collision_shapes_disabled(false)
	_set_cage_collision_enabled(false)
	set_physics_process(true)

	if _is_cube_holding_fallables():
		freeze = true
	else:
		freeze = false
		sleeping = false

	var cube := _find_cube_world()
	if cube == null:
		return
	if cube.has_method("invalidate_prop_cutaway_cache"):
		cube.invalidate_prop_cutaway_cache(self)
	if cube.has_method("update_cutaway_visibility"):
		cube.update_cutaway_visibility()


func _fade_cage() -> void:
	_kill_cage_tween()

	cage_visual.visible = true
	cage_visual.scale = _cage_start_scale
	_set_cage_alpha(1.0)
	_set_cage_collision_enabled(true)

	var duration := maxf(cage_fade_duration, 0.05)
	var end_scale := _cage_start_scale * cage_end_scale_ratio

	_cage_tween = create_tween()
	_cage_tween.tween_method(
		_set_cage_alpha,
		1.0,
		0.0,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_cage_tween.parallel().tween_property(
		cage_visual,
		"scale",
		end_scale,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_cage_tween.tween_callback(_finish_cage_unlock)


func _finish_cage_unlock() -> void:
	_cage_removed = true
	_set_cage_collision_enabled(false)

	if cage_visual != null:
		cage_visual.visible = false

	_activate_gravity()


func _prepare_cage_materials() -> void:
	_cage_materials.clear()
	_cage_base_colors.clear()
	_collect_cage_materials(cage_visual)


func _collect_cage_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D

		if mesh_instance.mesh != null:
			for surface_index in range(
				mesh_instance.mesh.get_surface_count()
			):
				var source := mesh_instance.get_active_material(
					surface_index
				)
				var material: BaseMaterial3D

				if source is BaseMaterial3D:
					material = source.duplicate(true) as BaseMaterial3D
				elif source == null:
					material = StandardMaterial3D.new()
				else:
					continue

				material.resource_local_to_scene = true
				material.transparency = (
					BaseMaterial3D.TRANSPARENCY_ALPHA
				)

				mesh_instance.set_surface_override_material(
					surface_index,
					material
				)

				_cage_materials.append(material)
				_cage_base_colors.append(material.albedo_color)

	for child in node.get_children():
		_collect_cage_materials(child)


func _set_cage_alpha(value: float) -> void:
	var alpha := clampf(value, 0.0, 1.0)

	for index in range(_cage_materials.size()):
		var material := _cage_materials[index]

		if not is_instance_valid(material):
			continue

		var color := _cage_base_colors[index]
		color.a *= alpha
		material.albedo_color = color


func _restore_cage() -> void:
	_kill_cage_tween()
	_cage_removed = false
	_unlocking = false
	cage_visual.visible = true
	cage_visual.scale = _cage_start_scale
	_set_cage_alpha(1.0)
	_set_cage_collision_enabled(true)


func _hide_cage_immediately() -> void:
	_kill_cage_tween()
	_cage_removed = true
	_unlocking = false
	_set_cage_collision_enabled(false)

	if cage_visual != null:
		_set_cage_alpha(0.0)
		cage_visual.visible = false


func _set_cage_collision_enabled(enabled: bool) -> void:
	if cage_blocker == null:
		return

	cage_blocker.collision_layer = 1 if enabled else 0
	cage_blocker.collision_mask = 1 if enabled else 0

	for child in cage_blocker.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(
				"disabled",
				not enabled
			)


func _set_collision_shapes_disabled(disabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(
				"disabled",
				disabled
			)


func _is_cube_holding_fallables() -> bool:
	var cube := _find_cube_world()

	if cube == null:
		return false

	return bool(cube.get("_hold_props_frozen"))


func _find_cube_world() -> Node:
	var node: Node = self

	while node != null:
		if node.has_method("update_cutaway_visibility"):
			return node

		node = node.get_parent()

	return null


func _ignore_player_collision() -> void:
	var tree := get_tree()

	if tree == null:
		return

	await tree.physics_frame

	var player := tree.get_first_node_in_group(
		"player"
	) as PhysicsBody3D

	if player == null and tree.current_scene != null:
		player = tree.current_scene.get_node_or_null(
			"Player"
		) as PhysicsBody3D

	if player == null:
		return

	add_collision_exception_with(player)
	player.add_collision_exception_with(self)


func _kill_adsorb_tween() -> void:
	if _adsorb_tween != null and _adsorb_tween.is_valid():
		_adsorb_tween.kill()

	_adsorb_tween = null


func _kill_cage_tween() -> void:
	if _cage_tween != null and _cage_tween.is_valid():
		_cage_tween.kill()

	_cage_tween = null

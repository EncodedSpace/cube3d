extends RigidBody3D

@export var adsorb_duration: float = 0.58
@export var adsorb_lift: float = 0.16
@export var cage_fade_duration: float = 0.6
@export_range(0.1, 1.0, 0.01) var cage_end_scale_ratio: float = 0.9

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


func _ready() -> void:
	gravity_scale = 0.0
	freeze = true
	collision_layer = 4
	collision_mask = 1
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 4
	add_to_group("b_tool")

	if cage_visual != null:
		_cage_start_scale = cage_visual.scale
		_prepare_cage_materials()
		_restore_cage()
	else:
		_set_cage_collision_enabled(false)

	call_deferred("_ignore_player_collision")


func apply_cutaway_visibility(wall_visible: bool) -> void:
	visible = wall_visible

	if not _cage_removed:
		_set_cage_collision_enabled(wall_visible)

	if gravity_enabled and not adsorbed:
		_set_collision_shapes_disabled(false)

		if _is_cube_holding_fallables():
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			freeze = true
		elif get_tree() != null and not get_tree().paused:
			freeze = false
			sleeping = false

		return

	_set_collision_shapes_disabled(not wall_visible)


func enable_gravity() -> void:
	if adsorbed or gravity_enabled or _unlocking:
		return

	if cage_visual == null or _cage_removed:
		_set_cage_collision_enabled(false)
		_activate_gravity()
		return

	_unlocking = true
	_fade_cage()


func adsorb_to_d(target_global_position: Vector3) -> void:
	if adsorbed:
		return

	adsorbed = true
	gravity_enabled = false
	_unlocking = false
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	sleeping = false
	_set_cage_collision_enabled(false)

	_kill_adsorb_tween()

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


func restore_after_g_collected(defer_gravity: bool = false) -> void:
	_kill_adsorb_tween()
	_hide_cage_immediately()

	adsorbed = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_set_collision_shapes_disabled(false)

	if defer_gravity:
		gravity_enabled = false
		gravity_scale = 0.0
		freeze = true
	else:
		_activate_gravity()


func _activate_gravity() -> void:
	if adsorbed:
		return

	_unlocking = false
	gravity_enabled = true
	gravity_scale = 1.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_set_collision_shapes_disabled(false)
	_set_cage_collision_enabled(false)

	if _is_cube_holding_fallables():
		freeze = true
	else:
		freeze = false
		sleeping = false


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

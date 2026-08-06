extends Node3D

@export var adsorb_lateral_max: float = 0.55
@export var adsorb_up_max: float = 1.35
@export var adsorb_down_max: float = 0.55
@export var cake_fade_delay: float = 0.10
@export var cake_fade_duration: float = 1.0
@export var cake_end_scale_ratio: float = 0.85
@export var fork_sink_offset: Vector3 = Vector3.ZERO

@onready var static_body: StaticBody3D = $StaticBody3D
@onready var area: Area3D = $Area3D
@onready var cake_visual: Node3D = $CakeVisual

var is_open: bool = false
var g_collected: bool = false

var _cake_materials: Array[BaseMaterial3D] = []
var _cake_base_colors: Array[Color] = []
var _cake_start_scale: Vector3
var _cake_tween: Tween


func _ready() -> void:
	static_body.collision_layer = 1
	static_body.collision_mask = 1

	area.collision_layer = 0
	area.collision_mask = 4
	area.monitoring = true
	area.monitorable = false

	if not area.body_entered.is_connected(_on_body_entered):
		area.body_entered.connect(_on_body_entered)

	_cake_start_scale = cake_visual.scale
	_prepare_cake_materials()
	_restore_cake()

	set_physics_process(false)
	call_deferred("check_b_overlap")


func _physics_process(_delta: float) -> void:
	if is_open or not g_collected:
		set_physics_process(false)
		return

	check_b_overlap()


func notify_g_collected() -> void:
	g_collected = true
	set_physics_process(true)
	call_deferred("check_b_overlap")


func restore_after_g_collected() -> void:
	is_open = false
	g_collected = true

	_restore_cake()
	_set_blocking_enabled(true)
	_set_area_enabled(true)

	set_physics_process(true)
	call_deferred("check_b_overlap")


func keep_open_for_exit() -> void:
	is_open = true
	g_collected = true

	set_physics_process(false)
	_set_blocking_enabled(false)
	_set_area_enabled(false)

	if cake_visual.visible:
		_fade_out_cake()


func check_b_overlap() -> void:
	if is_open or not g_collected:
		return

	for body in area.get_overlapping_bodies():
		if body.is_in_group("b_tool"):
			open_door(body)
			return

	for body in get_tree().get_nodes_in_group("b_tool"):
		if body is Node3D and _is_b_near_d(body):
			open_door(body)
			return


func _on_body_entered(body: Node3D) -> void:
	if not is_open and g_collected and body.is_in_group("b_tool"):
		open_door(body)


func open_door(b_tool: Node3D) -> void:
	if is_open:
		return

	is_open = true
	set_physics_process(false)

	if b_tool.has_method("adsorb_to_d"):
		b_tool.adsorb_to_d(to_global(fork_sink_offset))

	_set_blocking_enabled(false)
	_set_area_enabled(false)
	_fade_out_cake()


func should_keep_player_block() -> bool:
	return not is_open


func ensure_player_block() -> void:
	if is_open:
		return

	_set_blocking_enabled(true)
	_set_area_enabled(true)


func _is_b_near_d(body: Node3D) -> bool:
	var offset := body.global_position - global_position
	var height := offset.dot(Vector3.UP)
	var lateral := offset - Vector3.UP * height

	return (
		lateral.length() <= adsorb_lateral_max
		and height <= adsorb_up_max
		and height >= -adsorb_down_max
	)


func _set_blocking_enabled(enabled: bool) -> void:
	static_body.collision_layer = 1 if enabled else 0
	static_body.collision_mask = 1 if enabled else 0

	for child in static_body.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(
				"disabled",
				not enabled
			)


func _set_area_enabled(enabled: bool) -> void:
	area.set_deferred("monitoring", enabled)

	for child in area.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(
				"disabled",
				not enabled
			)


func _prepare_cake_materials() -> void:
	_cake_materials.clear()
	_cake_base_colors.clear()
	_collect_cake_materials(cake_visual)


func _collect_cake_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D

		if mesh_instance.mesh != null:
			for surface_index in range(
				mesh_instance.mesh.get_surface_count()
			):
				var source := mesh_instance.get_active_material(
					surface_index
				)

				if source is BaseMaterial3D:
					var material := source.duplicate(true) as BaseMaterial3D
					material.resource_local_to_scene = true
					material.transparency = (
						BaseMaterial3D.TRANSPARENCY_ALPHA
					)

					mesh_instance.set_surface_override_material(
						surface_index,
						material
					)

					_cake_materials.append(material)
					_cake_base_colors.append(material.albedo_color)

	for child in node.get_children():
		_collect_cake_materials(child)


func _set_cake_visibility(value: float) -> void:
	var visibility := clampf(value, 0.0, 1.0)

	for index in range(_cake_materials.size()):
		var material := _cake_materials[index]

		if not is_instance_valid(material):
			continue

		var color := _cake_base_colors[index]
		color.a *= visibility
		material.albedo_color = color


func _fade_out_cake() -> void:
	_kill_cake_tween()

	cake_visual.visible = true
	cake_visual.scale = _cake_start_scale
	_set_cake_visibility(1.0)

	var duration := maxf(cake_fade_duration, 0.05)
	var delay := maxf(cake_fade_delay, 0.0)
	var end_scale := _cake_start_scale * cake_end_scale_ratio

	_cake_tween = create_tween()
	_cake_tween.tween_interval(delay)

	_cake_tween.tween_method(
		_set_cake_visibility,
		1.0,
		0.0,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_cake_tween.parallel().tween_property(
		cake_visual,
		"scale",
		end_scale,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_cake_tween.tween_callback(
		func() -> void:
			cake_visual.visible = false
	)


func _restore_cake() -> void:
	_kill_cake_tween()
	cake_visual.visible = true
	cake_visual.scale = _cake_start_scale
	_set_cake_visibility(1.0)


func _kill_cake_tween() -> void:
	if _cake_tween != null and _cake_tween.is_valid():
		_cake_tween.kill()

	_cake_tween = null

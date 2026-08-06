extends Node3D

## D 机关（蛋糕 + 盘子）：
## - G 未收集：B 叉子保持冻结，D 仍然阻挡玩家。
## - G 已收集：B 叉子开始受重力，可以落入蛋糕。
## - B 落入后：叉子吸附并保留；蛋糕渐隐；盘子始终保留；
##   蛋糕的固体碰撞关闭，玩家可以从盘子位置通过。
## - 名字以 D_Wall 开头的节点可共用本脚本（包括 D_Wall2）。


var is_open: bool = false
var g_collected: bool = false

## B 落在 D 顶面时，中心距约 1m；邻格同高也约 1m，
## 因此用“水平贴格 + 高度范围”区分。
@export var adsorb_lateral_max: float = 0.55
@export var adsorb_up_max: float = 1.35
@export var adsorb_down_max: float = 0.55

## 蛋糕从完全可见到完全消失的时间。
@export var cake_fade_duration: float = 0.8

## 叉子吸附后的局部位置偏移。
## 默认 Vector3.ZERO 与旧逻辑相同；位置不自然时可在检查器里微调。
@export var fork_sink_offset: Vector3 = Vector3.ZERO

@onready var static_body: StaticBody3D = (
	get_node_or_null("StaticBody3D") as StaticBody3D
)
@onready var area: Area3D = (
	get_node_or_null("Area3D") as Area3D
)
@onready var plate_visual: Node3D = (
	get_node_or_null("PlateVisual") as Node3D
)
@onready var cake_visual: Node3D = (
	get_node_or_null("CakeVisual") as Node3D
)

var _cake_meshes: Array[MeshInstance3D] = []
var _cake_fade_tween: Tween


func _ready() -> void:
	if static_body == null:
		push_warning("D_Wall：找不到 StaticBody3D")
	else:
		# 与墙面同层，确保 CharacterBody3D 玩家会被蛋糕挡住。
		static_body.collision_layer = 1
		static_body.collision_mask = 1
		_set_blocking_shapes_disabled(false)

	if area == null:
		push_warning("D_Wall：找不到 Area3D")
	else:
		area.monitoring = true
		area.monitorable = false

		# B_Tool 使用 collision_layer = 4。
		area.collision_layer = 4
		area.collision_mask = 4

		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)

	if plate_visual == null:
		push_warning("D_Wall：找不到 PlateVisual；盘子不会显示")

	if cake_visual == null:
		push_warning("D_Wall：找不到 CakeVisual；无法播放蛋糕渐隐")
	else:
		_cache_cake_meshes()
		_restore_cake_visual()

	set_physics_process(false)
	call_deferred("check_b_overlap")


func _physics_process(_delta: float) -> void:
	if is_open or not g_collected:
		set_physics_process(false)
		return

	check_b_overlap()


## G 道具收集后调用：允许持续检测已经开始下落的 B。
func notify_g_collected() -> void:
	g_collected = true
	set_physics_process(true)

	# B 可能已经与 Area 重叠，因此主动补检一次。
	call_deferred("check_b_overlap")


## 复原到“G 已收集、蛋糕未被叉子吃掉”的状态：
## 蛋糕重新出现并挡人，盘子始终保留，D 可以再次接收 B。
func restore_after_g_collected() -> void:
	is_open = false
	g_collected = true

	_restore_cake_visual()

	if static_body != null:
		static_body.collision_layer = 1
		static_body.collision_mask = 1

	_set_blocking_shapes_disabled(false)

	if area != null:
		area.monitoring = true

		for child in area.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = false

	set_physics_process(true)
	call_deferred("check_b_overlap")


## 外部机关临时要求 D 保持打开时调用：
## 蛋糕立即隐藏、固体碰撞关闭，但盘子仍然显示。
func keep_open_for_exit() -> void:
	is_open = true
	g_collected = true
	set_physics_process(false)

	if static_body != null:
		static_body.collision_layer = 0
		static_body.collision_mask = 0

	_set_blocking_shapes_disabled(true)
	_set_area_enabled(false)
	_hide_cake_immediately()


## B 已经在 Area 内时，body_entered 不会再次触发，所以需要主动补检。
## B 也可能停在蛋糕固体顶面、与 Area 仅擦边，因此再做一次位置判定。
func check_b_overlap() -> void:
	if is_open:
		return

	if area != null and is_instance_valid(area):
		for body in area.get_overlapping_bodies():
			if body != null and body.is_in_group("b_tool"):
				open_door(body as Node3D)
				return

	_check_b_on_top()


func _check_b_on_top() -> void:
	var tree := get_tree()

	if tree == null:
		return

	for body in tree.get_nodes_in_group("b_tool"):
		if (
			body == null
			or not is_instance_valid(body)
			or not (body is Node3D)
		):
			continue

		var body_3d := body as Node3D

		if _is_b_resting_on_d(body_3d):
			open_door(body_3d)
			return


func _is_b_resting_on_d(body: Node3D) -> bool:
	var offset := body.global_position - global_position

	# 使用世界重力方向判断：水平距离足够近，且高度在允许范围内。
	var lateral := offset - Vector3.UP * offset.dot(Vector3.UP)

	if lateral.length() > adsorb_lateral_max:
		return false

	var along_up := offset.dot(Vector3.UP)

	if along_up > adsorb_up_max:
		return false

	if along_up < -adsorb_down_max:
		return false

	return true


func _on_body_entered(body: Node3D) -> void:
	if is_open:
		return

	if body == null or not body.is_in_group("b_tool"):
		return

	open_door(body)


func open_door(b_tool: Node3D) -> void:
	if is_open or b_tool == null:
		return

	is_open = true
	set_physics_process(false)

	# 叉子吸附到蛋糕所在位置并保留。
	# fork_sink_offset 使用 D_Wall 的局部坐标，翻面后方向仍然正确。
	if b_tool.has_method("adsorb_to_d"):
		b_tool.adsorb_to_d(to_global(fork_sink_offset))

	# 蛋糕不再阻挡玩家；盘子本身没有碰撞，因此可以直接经过。
	if static_body != null:
		static_body.collision_layer = 0
		static_body.collision_mask = 0

	# 这里可能正处于 body_entered 信号中，使用 deferred 避免 PhysicsServer 报错。
	_set_blocking_shapes_disabled(true, true)
	_set_area_enabled(false)

	# 只让蛋糕消失；PlateVisual 和叉子都不做透明处理。
	_fade_out_cake()


## cube_world 用它判断 D 是否仍应阻挡玩家。
func should_keep_player_block() -> bool:
	return not is_open


## cube_world 在 D 所在墙面重新可见时调用：
## 未打开的 D 必须恢复蛋糕阻挡碰撞和 B 检测。
func ensure_player_block() -> void:
	if is_open or static_body == null:
		return

	static_body.collision_layer = 1
	static_body.collision_mask = 1
	_set_blocking_shapes_disabled(false)

	if area != null:
		area.monitoring = true

		for child in area.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = false


func _set_blocking_shapes_disabled(
	disabled: bool,
	deferred: bool = false
) -> void:
	if static_body == null:
		return

	for child in static_body.get_children():
		if not child is CollisionShape3D:
			continue

		var shape := child as CollisionShape3D

		if deferred:
			shape.set_deferred("disabled", disabled)
		else:
			shape.disabled = disabled


func _set_area_enabled(enabled: bool) -> void:
	if area == null:
		return

	# monitoring 和 CollisionShape3D.disabled 都不能在进入/退出信号刷新中直接改。
	area.set_deferred("monitoring", enabled)

	for child in area.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(
				"disabled",
				not enabled
			)


## 缓存 CakeVisual 自身及其所有后代中的 MeshInstance3D。
## 使用 GeometryInstance3D.transparency 渐隐，不会修改共享材质资源，
## 因此不会连带影响盘子、其他蛋糕或场景中的同款模型。
func _cache_cake_meshes() -> void:
	_cake_meshes.clear()

	if cake_visual == null:
		return

	if cake_visual is MeshInstance3D:
		_cake_meshes.append(cake_visual as MeshInstance3D)

	for node in cake_visual.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	):
		var mesh_instance := node as MeshInstance3D

		if mesh_instance != null and mesh_instance not in _cake_meshes:
			_cake_meshes.append(mesh_instance)


## amount：0.0 = 完全不透明，1.0 = 完全透明。
func _set_cake_fade(amount: float) -> void:
	var safe_amount := clampf(amount, 0.0, 1.0)

	for mesh_instance in _cake_meshes:
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue

		mesh_instance.transparency = safe_amount


func _fade_out_cake() -> void:
	if cake_visual == null:
		return

	_kill_cake_tween()

	cake_visual.visible = true
	_set_cake_fade(0.0)

	_cake_fade_tween = create_tween()
	_cake_fade_tween.set_trans(Tween.TRANS_QUAD)
	_cake_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_cake_fade_tween.tween_method(
		_set_cake_fade,
		0.0,
		1.0,
		maxf(cake_fade_duration, 0.01)
	)
	_cake_fade_tween.tween_callback(_finish_cake_fade)


func _finish_cake_fade() -> void:
	if cake_visual != null and is_instance_valid(cake_visual):
		cake_visual.visible = false


func _restore_cake_visual() -> void:
	if cake_visual == null:
		return

	_kill_cake_tween()
	cake_visual.visible = true
	_set_cake_fade(0.0)


func _hide_cake_immediately() -> void:
	if cake_visual == null:
		return

	_kill_cake_tween()
	_set_cake_fade(1.0)
	cake_visual.visible = false


func _kill_cake_tween() -> void:
	if (
		_cake_fade_tween != null
		and _cake_fade_tween.is_valid()
	):
		_cake_fade_tween.kill()

	_cake_fade_tween = null

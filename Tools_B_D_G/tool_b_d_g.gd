@tool
extends Node3D

## B / D / G 道具组根节点脚本。
##
## B_Tool：仍然是可下落的 RigidBody3D。
## G_Tool：现在是固定在大方块上的 AnimatableBody3D。
## D_Wall、D_Wall2……：统一作为 D 墙处理。
##
## @tool 用于在编辑器中实时同步各道具的位置。


@export_category("道具位置")

@export var b_position := Vector3(2.0, 2.0, 0.0)
@export var g_position := Vector3(2.0, 0.0, 1.5)
@export var d_position := Vector3(0.0, 0.0, 0.0)

## 任一 D 被 B 打开后，同组其它 D 也一并变为可通行（level7 等多门关卡用）。
@export var open_all_d_walls_together := false
## G 收集后，把关卡里的 MovableBox 锁成 StaticBox 一样的固定块（level7）。
@export var lock_movable_boxes_on_g_collect := false


## B 仍然是受重力控制的刚体。
@onready var b_tool: RigidBody3D = get_node_or_null(
	"B_Tool"
) as RigidBody3D

## G 已改成 AnimatableBody3D。
## 这里使用 Node3D 类型，避免以后更换固定物体类型时再次报类型错误。
@onready var g_tool: Node3D = get_node_or_null(
	"G_Tool"
) as Node3D

@onready var d_wall: Node3D = get_node_or_null(
	"D_Wall"
) as Node3D


func _ready() -> void:
	_apply_positions()

	if Engine.is_editor_hint():
		return

	_connect_g_tool()

	# 运行时不需要每帧同步编辑器位置。
	set_process(false)


func _connect_g_tool() -> void:
	if g_tool == null or not is_instance_valid(g_tool):
		return

	# 保证 G_Tool 能找到同组中的 B_Tool。
	if b_tool != null and is_instance_valid(b_tool):
		g_tool.set(
			"b_tool_path",
			g_tool.get_path_to(b_tool)
		)

	# 连接披萨进入盒子后的触发信号。
	if g_tool.has_signal("g_collected"):
		var collected_callback := Callable(
			self,
			"_on_g_collected"
		)

		if not g_tool.is_connected(
			"g_collected",
			collected_callback
		):
			g_tool.connect(
				"g_collected",
				collected_callback
			)


func _on_g_collected() -> void:
	for d in get_all_d_walls():
		if d.has_method("notify_g_collected"):
			d.notify_g_collected()
	if lock_movable_boxes_on_g_collect:
		_lock_all_movable_boxes_as_static()


func _lock_all_movable_boxes_as_static() -> void:
	var cube := get_parent()
	if cube == null:
		return
	for node in cube.find_children("*MovableBox*", "RigidBody3D", true, false):
		if node != null and node.has_method("lock_as_static"):
			node.lock_as_static()


## 由某个 D_Wall.open_door 调用：按需同步打开同组其它门（不再吸附 B）。
func notify_d_opened(opened_wall: Node3D, _b_tool: Node3D) -> void:
	if not open_all_d_walls_together:
		return
	for d in get_all_d_walls():
		if d == opened_wall:
			continue
		if d.has_method("open_as_passable"):
			d.open_as_passable()


## 复原到“G 已经触发”之后的机关状态。
##
## 现在 G_Tool 是披萨盒，不能再 queue_free()。
## 它会继续保留在场景中，并跟随大方块旋转。
##
## defer_b_gravity：
## 等外部完成换位后再开启 B 的重力。
##
## keep_open_walls：
## 指定的 D 墙暂时保持开启，等箱子掉出后再关闭。
func restore_after_g_collected(
	defer_b_gravity: bool = false,
	keep_open_walls: Array = []
) -> void:
	_refresh_node_references()

	# G_Tool 不再删除。
	# 若之后给 g_tool.gd 添加了对应恢复方法，这里会自动调用。
	if (
		g_tool != null
		and is_instance_valid(g_tool)
		and g_tool.has_method("restore_after_g_collected")
	):
		g_tool.restore_after_g_collected()

	for d in get_all_d_walls():
		if (
			d in keep_open_walls
			and d.has_method("keep_open_for_exit")
		):
			d.keep_open_for_exit()
			continue

		if d.has_method("restore_after_g_collected"):
			d.restore_after_g_collected()
		elif d.has_method("notify_g_collected"):
			d.notify_g_collected()

	if (
		b_tool != null
		and is_instance_valid(b_tool)
		and b_tool.has_method("restore_after_g_collected")
	):
		b_tool.restore_after_g_collected(
			defer_b_gravity
		)


## 换位或开启重力后，
## 让所有 D 墙重新检查是否已经与 B_Tool 重叠。
func check_all_d_b_overlaps() -> void:
	for d in get_all_d_walls():
		if d.has_method("check_b_overlap"):
			d.check_b_overlap()


## 获取当前道具组中所有 D_Wall、D_Wall2、D_Wall3……
func get_all_d_walls() -> Array[Node3D]:
	var result: Array[Node3D] = []

	for child in get_children():
		if child == null or not child is Node3D:
			continue

		var child_name := String(child.name)

		if (
			child_name == "D_Wall"
			or child_name.begins_with("D_Wall")
		):
			result.append(child as Node3D)

	return result


func _refresh_node_references() -> void:
	if b_tool == null or not is_instance_valid(b_tool):
		b_tool = get_node_or_null(
			"B_Tool"
		) as RigidBody3D

	if g_tool == null or not is_instance_valid(g_tool):
		g_tool = get_node_or_null(
			"G_Tool"
		) as Node3D

	if d_wall == null or not is_instance_valid(d_wall):
		d_wall = get_node_or_null(
			"D_Wall"
		) as Node3D


func _process(_delta: float) -> void:
	# 只在编辑器中实时同步检查器位置。
	if Engine.is_editor_hint():
		_apply_positions()


func _apply_positions() -> void:
	if b_tool != null and is_instance_valid(b_tool):
		b_tool.position = b_position

	if g_tool != null and is_instance_valid(g_tool):
		g_tool.position = g_position

	# 只同步主 D_Wall。
	# D_Wall2 等节点可以在关卡中独立摆放。
	if d_wall != null and is_instance_valid(d_wall):
		d_wall.position = d_position

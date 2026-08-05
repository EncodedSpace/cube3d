@tool
extends Node3D

## B/D/G 道具组根节点脚本。
## @tool 确保编辑器内修改导出变量后实时在视口中同步位置。
## 所有名字以 D_Wall 开头的子节点（D_Wall、D_Wall2…）同等对待。


@export var b_position := Vector3(2.0, 2.0, 0.0)
@export var g_position := Vector3(2.0, 0.0, 1.5)
@export var d_position := Vector3(0.0, 0.0, 0.0)

## 任一 D 被 B 打开后，同组其它 D 也一并变为可通行（level7 等多门关卡用）。
@export var open_all_d_walls_together := false
## G 收集后，把关卡里的 MovableBox 锁成 StaticBox 一样的固定块（level7）。
@export var lock_movable_boxes_on_g_collect := false


@onready var b_tool: RigidBody3D = $B_Tool
@onready var g_tool: RigidBody3D = $G_Tool
@onready var d_wall: Node3D = $D_Wall


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_apply_positions()
	# Ensure G can always find B even if the export path was left empty.
	if g_tool != null and b_tool != null:
		g_tool.b_tool_path = g_tool.get_path_to(b_tool)
	if g_tool != null and g_tool.has_signal("g_collected"):
		g_tool.g_collected.connect(_on_g_collected)
	# 运行时关闭 process，避免空转。
	set_process(false)


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


## 复原到「G 已被收集」之后的状态（门未开、B 可下落），供 Tools_F 等外部触发。
## 不改 B 的坐标；defer_b_gravity 时等换位后再开重力。
## keep_open_walls：这些 D 先保持开门，等箱子掉出去再关。
func restore_after_g_collected(defer_b_gravity: bool = false, keep_open_walls: Array = []) -> void:
	# 若 G 还在，直接移除（效果等同已收集）。
	var g := get_node_or_null("G_Tool")
	if g != null and is_instance_valid(g):
		g.queue_free()

	# 刷新子节点引用（编辑器改名 / 运行时释放后）。
	if not is_instance_valid(b_tool):
		b_tool = get_node_or_null("B_Tool") as RigidBody3D
	if not is_instance_valid(d_wall):
		d_wall = get_node_or_null("D_Wall") as Node3D

	for d in get_all_d_walls():
		if d in keep_open_walls and d.has_method("keep_open_for_exit"):
			d.keep_open_for_exit()
			continue
		if d.has_method("restore_after_g_collected"):
			d.restore_after_g_collected()
		elif d.has_method("notify_g_collected"):
			d.notify_g_collected()

	if b_tool != null and b_tool.has_method("restore_after_g_collected"):
		b_tool.restore_after_g_collected(defer_b_gravity)


## 换位 / 开重力后，让所有 D 补检是否已与 B 重叠。
func check_all_d_b_overlaps() -> void:
	for d in get_all_d_walls():
		if d.has_method("check_b_overlap"):
			d.check_b_overlap()


func get_all_d_walls() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in get_children():
		if child == null or not (child is Node3D):
			continue
		var n := String(child.name)
		if n == "D_Wall" or n.begins_with("D_Wall"):
			result.append(child as Node3D)
	return result


func _process(_delta: float) -> void:
	# 仅在编辑器中每帧同步：导出变量 → 节点位置。
	if Engine.is_editor_hint():
		_apply_positions()


func _apply_positions() -> void:
	if b_tool:
		b_tool.position = b_position
	if g_tool:
		g_tool.position = g_position
	# 仅同步主 D_Wall；D_Wall2 等在关卡里单独摆放。
	if d_wall:
		d_wall.position = d_position

@tool
extends Node3D

## B/D/G 道具组根节点脚本。
## @tool 确保编辑器内修改导出变量后实时在视口中同步位置。


@export var b_position := Vector3(2.0, 2.0, 0.0)
@export var g_position := Vector3(2.0, 0.0, 1.5)
@export var d_position := Vector3(0.0, 0.0, 0.0)


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
	if d_wall != null and d_wall.has_method("notify_g_collected"):
		d_wall.notify_g_collected()


func _process(_delta: float) -> void:
	# 仅在编辑器中每帧同步：导出变量 → 节点位置。
	if Engine.is_editor_hint():
		_apply_positions()


func _apply_positions() -> void:
	if b_tool:
		b_tool.position = b_position
	if g_tool:
		g_tool.position = g_position
	if d_wall:
		d_wall.position = d_position

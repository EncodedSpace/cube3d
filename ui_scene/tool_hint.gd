extends Control

## Contextual item hint: cursor hover or a cardinal (front/back/left/right)
## one-cell approach. The panel lives at the left-side center, away from the map.
const CHECK_INTERVAL := 0.12
const CARDINAL_STEP_MIN := 0.55
const CARDINAL_STEP_MAX := 1.45
const CARDINAL_OFF_AXIS_MAX := 0.65
const SCREEN_HOVER_RADIUS := 34.0

var _title: Label
var _status: Label
var _description: Label
var _panel: PanelContainer
var _elapsed := 0.0
var _last_key := ""
var _near_enter_order: Dictionary = {}
var _enter_counter := 0
var _last_player_position: Vector3
var _has_last_player_position := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The hint root must fill the viewport; otherwise its centered child panel is
	# positioned relative to a 0 × 0 control and ends up off-screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	visible = false


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < CHECK_INTERVAL:
		return
	_elapsed = 0.0
	var candidate: Node3D = _find_hovered_tool()
	if candidate == null:
		candidate = _find_nearby_tool()
	_update_hint(candidate)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	# A larger, vertically centered left-side panel leaves the cube unobstructed.
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 28.0
	_panel.offset_top = -104.0
	_panel.offset_right = 448.0
	_panel.offset_bottom = 104.0
	_panel.custom_minimum_size = Vector2(420, 208)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _style(Color("#0a1728e8"), Color("#3c8fd1"), 12, 1))
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color("#f1f7ff"))
	box.add_child(_title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color("#5cb4ff"))
	box.add_child(_status)
	var line := HSeparator.new()
	box.add_child(line)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_font_size_override("font_size", 18)
	_description.add_theme_color_override("font_color", Color("#c9d9eb"))
	box.add_child(_description)


func _find_hovered_tool() -> Node3D:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return null
	var mouse: Vector2 = viewport.get_mouse_position()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		camera.project_ray_origin(mouse), camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * 1000.0
	)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collision_tool: Node3D = _find_tool_ancestor(hit.get("collider") as Node)
		if collision_tool != null:
			return collision_tool
	# Some interactable props intentionally have no active collision layer. Fall back
	# to a small screen-space hover area so they are still discoverable by mouse.
	return _find_screen_hovered_tool(camera, mouse)


func _find_screen_hovered_tool(camera: Camera3D, mouse: Vector2) -> Node3D:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var closest: Node3D
	var closest_distance: float = SCREEN_HOVER_RADIUS
	for node in _all_nodes(scene):
		var tool: Node3D = _find_tool_ancestor(node)
		if tool == null or tool != node or camera.is_position_behind(tool.global_position):
			continue
		var distance: float = mouse.distance_to(camera.unproject_position(tool.global_position))
		if distance < closest_distance:
			closest_distance = distance
			closest = tool
	return closest


func _find_nearby_tool() -> Node3D:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		player = scene.get_node_or_null("Player") as Node3D
	if player == null:
		return null
	var candidates: Array[Node3D] = []
	for node in _all_nodes(scene):
		var tool: Node3D = _find_tool_ancestor(node)
		if tool == null or tool != node:
			continue
		if _is_cardinally_adjacent(player, tool):
			candidates.append(tool)
	return _select_last_entered_tool(player, candidates)


func _is_cardinally_adjacent(player: Node3D, tool: Node3D) -> bool:
	# Use cube-local coordinates so the rule remains correct after the cube rotates.
	var delta: Vector3 = _grid_position(player) - _grid_position(tool)
	var steps := 0
	for amount: float in [absf(delta.x), absf(delta.y), absf(delta.z)]:
		if amount > CARDINAL_STEP_MAX:
			return false
		if amount >= CARDINAL_STEP_MIN:
			steps += 1
		elif amount > CARDINAL_OFF_AXIS_MAX:
			return false
	# Exactly one changed grid axis means front/back/left/right only; diagonals use two.
	return steps == 1


func _grid_position(node: Node3D) -> Vector3:
	var current: Node = node
	while current != null:
		if current is Node3D and (current.has_method("get_nearest_walls_for") or current.has_method("request_orient_wall_as_floor")):
			return (current as Node3D).to_local(node.global_position)
		current = current.get_parent()
	return node.global_position


func _select_last_entered_tool(player: Node3D, candidates: Array[Node3D]) -> Node3D:
	var present_ids: Dictionary = {}
	var just_entered: Array[Node3D] = []
	var newest: Node3D
	var newest_order: int = -1
	for tool in candidates:
		var id: int = tool.get_instance_id()
		present_ids[id] = true
		if not _near_enter_order.has(id):
			_enter_counter += 1
			_near_enter_order[id] = _enter_counter
			just_entered.append(tool)
		var order: int = int(_near_enter_order[id])
		if order > newest_order:
			newest_order = order
			newest = tool
	for id in _near_enter_order.keys():
		if not present_ids.has(id):
			_near_enter_order.erase(id)
	# If two regions are entered on the same polling frame, prefer the direction of
	# the player's most recent step. This resolves corner cases by the last action.
	if just_entered.size() > 1 and _has_last_player_position:
		var movement: Vector3 = player.global_position - _last_player_position
		if movement.length_squared() > 0.0001:
			var directional_choice: Node3D = just_entered[0]
			var best_score: float = -INF
			for tool in just_entered:
				var score: float = (tool.global_position - player.global_position).dot(movement)
				if score > best_score:
					best_score = score
					directional_choice = tool
			_last_player_position = player.global_position
			return directional_choice
	_last_player_position = player.global_position
	_has_last_player_position = true
	return newest


func _all_nodes(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	if root == null:
		return result
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		# Array.pop_back() is Variant in Godot's API; declare the expected type
		# explicitly because this project treats Variant-inference warnings as errors.
		var node: Node = stack.pop_back()
		result.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return result


func _find_tool_ancestor(node: Node) -> Node3D:
	var current: Node = node
	while current != null:
		if current is Node3D and not _tool_info(current).is_empty():
			return current as Node3D
		current = current.get_parent()
	return null


func _update_hint(tool: Node3D) -> void:
	if tool == null or not is_instance_valid(tool):
		visible = false
		_last_key = ""
		return
	var info: Dictionary = _tool_info(tool)
	if info.is_empty():
		visible = false
		return
	var key: String = "%s|%s|%s" % [info.title, info.status, info.description]
	if key != _last_key:
		_last_key = key
		_title.text = info.title
		_status.text = "【%s】" % info.status if not info.status.is_empty() else ""
		_description.text = info.description
	visible = true


func _tool_info(node: Node) -> Dictionary:
	match String(node.name):
		"B_Tool":
			if bool(node.get("gravity_enabled")):
				return _info("叉子", "已解锁", "一把拥有特殊力量的叉子，可随重力移动，并消除挡路的甜点。")
			return _info("叉子", "已锁定", "叉子似乎被封印了，需要完成某项料理准备。")
		"G_Tool":
			return _info("披萨盒", "", "一个普通的盒子，似乎在等待某种料理。")
		"D_Wall", "D_Wall2":
			if bool(node.get("is_open")):
				return _info("蛋糕盘", "蛋糕已消除", "蛋糕已经消失，可以继续前进。")
			return _info("蛋糕盘", "盛有蛋糕", "美味的蛋糕挡住了道路，需要想办法处理。")
		"StaticBox_E1":
			if bool(node.get("_unlocked")):
				return _info("料理检测台", "已激活", "料理检测完成，隐藏机关已启动。")
			return _info("料理检测台", "未激活", "等待指定料理，唤醒隐藏功能。")
		"StaticBox_E2":
			if bool(node.get("is_open")):
				return _info("暗门", "开启", "暗门开启，新的道路出现。")
			return _info("暗门", "关闭", "似乎隐藏着某个秘密，等待机关开启。")
		# F must use the child Area3D itself. ToolsF is only a container at the
		# scene origin; treating it as an interactable would ignore the final
		# trigger_position configured in the level.
		"F_Trigger":
			return _info("交换台", "", "两个特殊物品的位置或许会发生奇妙变化。")
		"Portal_A", "Portal_B":
			var root: Node = node.get_parent()
			if root != null and bool(root.get("portals_unlocked")):
				return _info("空间通道", "开启", "可通往另一处空间。")
			return _info("空间通道", "关闭", "等待启动机关，建立空间连接。")
		"Portal_Key":
			return _info("启动开关", "待交互", "玩家交互后，空间通道已建立。")
		"Final_Key":
			return _info("启动开关", "待交互", "玩家交互后，最终出口已开启。")
		"Final_Exit":
			var final_root: Node = node.get_parent()
			if final_root != null and bool(final_root.get("exit_unlocked")):
				return _info("逃生大门", "开启", "")
			return _info("逃生大门", "关闭", "还需要完成最后的准备。")
		"Tool_X":
			return _info("启动开关", "待交互", "玩家交互后，跳板已恢复动力。")
		"Tool_Y":
			var xyz_root: Node = node.get_parent()
			if xyz_root != null and bool(xyz_root.get("_pad_active")):
				return _info("跳板", "已解锁", "利用弹力跳跃，可突破上方障碍。")
			return _info("跳板", "未解锁", "似乎缺少动力。")
		"Tool_Z":
			return _info("脆弱岩体", "", "看起来并不牢固，也许可以被撞碎。")
	if String(node.name).begins_with("MovableBox_C"):
		return _info("披萨", "", "可随重力移动的魔法披萨，或许能唤醒沉睡的机关。")
	return {}


func _info(title: String, status: String, description: String) -> Dictionary:
	return {"title": title, "status": status, "description": description}


func _style(background: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style

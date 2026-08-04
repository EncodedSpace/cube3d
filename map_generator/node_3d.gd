extends Node3D

## Rotates the cube so a hit face becomes the new floor.
## Player is carried through the same rotation, then falls onto it.

@export var flip_duration: float = 0.55
@export var cube_half_extent: float = 3.0
## Zen-mode grid size (6–12).  Set before calling generate().
@export var n: int = 8
## How strongly an outer wall must face the camera to be cut away.
@export var wall_visible_dot: float = 0.2
## Half-size of the floor-wall junction cell that must be clear of boxes to flip.
@export var flip_junction_clearance: float = 0.75
## After orient: consider bodies settled when speed stays under this.
@export var settle_velocity_epsilon: float = 0.08
## Need this many consecutive settled physics frames before next flip/yaw.
@export var settle_stable_frames: int = 4
## Safety cap so a stuck body cannot block orient forever.
@export var settle_timeout: float = 4.0

var flipping: bool = false
var start_transform: Transform3D
## True while cube is rotating: fallable props stay frozen so falls aren't cut mid-air.
var _hold_props_frozen: bool = false

## Props attached to walls: each entry is { "prop": Node3D, "walls": Array[Node3D] }
## A prop can bind to multiple walls when equally close to each. Visible if ANY
## bound wall is shown; hidden only when ALL bound walls are cut away.
var _wall_props: Array[Dictionary] = []

signal flip_started
signal flip_finished
signal generation_finished


# ── map generation state ──────────────────────────────────────
var matrix: Array = []
var start_pos: Vector3i
var end_pos: Vector3i
var path: Array[Vector3i] = []
var rng := RandomNumberGenerator.new()
var _last_visited: Dictionary = {}
var _staticbox_template: StaticBody3D = null
# 保存最后一次成功生成的布局，供“重置本关”恢复而不是重新随机生成。
var _saved_matrix: Array = []
var _saved_start_pos: Vector3i
var _saved_end_pos: Vector3i
var _saved_path: Array[Vector3i] = []
var _map_saved: bool = false
# 生成时立方体的朝向（重置时恢复，否则用已翻转的坐标系算出生点会出错）。
var _saved_cube_transform: Transform3D
# 场景默认的立方体姿态（新地图生成前恢复到标准朝向）。
var _base_cube_transform: Transform3D


func _ready() -> void:
	start_transform = global_transform
	_base_cube_transform = global_transform
	# Disable the reference WALLS8_8 so its collision shapes don't block the player.
	var ref_walls := get_node_or_null("WALLS8_8")
	if ref_walls != null:
		for child in ref_walls.get_children():
			if child is StaticBody3D:
				var col := (child as StaticBody3D).get_node_or_null("CollisionShape3D") as CollisionShape3D
				if col != null:
					col.disabled = true
	# Zen mode: skip prop binding – static boxes are walls, not props.
	# Make sure the current wall template starts visible; the scene file has
	# several faces marked invisible for editor convenience.
	var walls := get_node_or_null("WALLS")
	if walls != null:
		for child in walls.get_children():
			if child is Node3D:
				(child as Node3D).visible = true
	await _bootstrap_cutaway()


func _bootstrap_cutaway() -> void:
	for _i in range(12):
		_ensure_level_camera()
		update_cutaway_visibility()
		if _has_cutaway_applied():
			return
		await get_tree().process_frame


func _has_cutaway_applied() -> bool:
	if get_viewport().get_camera_3d() == null:
		return false
	var walls := get_node_or_null("WALLS")
	if walls == null:
		return false
	var hidden := 0
	for child in walls.get_children():
		var mesh := (child as Node).get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh != null and not mesh.visible:
			hidden += 1
	return hidden >= 3


func _ensure_level_camera() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		var host := get_parent()
		if host != null:
			cam = host.find_child("Camera3D", true, false) as Camera3D
	if cam != null and not cam.current:
		cam.make_current()
	return cam


func get_center_global() -> Vector3:
	return to_global(Vector3(0.0, cube_half_extent, 0.0))


func can_flip() -> bool:
	return not flipping


func reset_to_start() -> void:
	flipping = false
	_hold_props_frozen = false
	if _map_saved:
		# 恢复上次生成的地图，而不是重新随机生成。
		restore_saved_map()
	else:
		generate()


func request_flip(collision_normal: Vector3, player: Node3D) -> bool:
	if flipping:
		print("[FlipBlocked] reason=flipping")
		return false

	# Collision normal points toward the player (into the room).
	# The face's outward direction is the opposite; that should become world down.
	var outward := _snap_to_axis(-collision_normal)
	if outward.dot(Vector3.DOWN) > 0.99:
		print("[FlipBlocked] reason=already_floor outward=", outward, " collision_normal=", collision_normal)
		return false

	var rotation_quat := Quaternion(outward, Vector3.DOWN)
	if rotation_quat.get_angle() < 0.01:
		print("[FlipBlocked] reason=zero_rotation outward=", outward, " collision_normal=", collision_normal)
		return false

	# Only empty floor-wall junctions can flip (no StaticBox / MovableBox there).
	if player != null and _is_flip_blocked_by_box(collision_normal, player):
		print("[FlipBlocked] reason=occupied_junction collision_normal=", collision_normal, " player=", player.global_position)
		return false

	_animate_flip(rotation_quat, player)
	return true


## Orient so this wall becomes the floor (portal teleport). Skips junction-box blocking.
func request_orient_wall_as_floor(wall: Node3D, player: Node3D) -> bool:
	if flipping or wall == null:
		print("[FlipBlocked] reason=flipping_or_null_wall wall=", wall)
		return false
	var inward := wall.global_transform.basis.y.normalized()
	var outward := _snap_to_axis(-inward)
	if outward.dot(Vector3.DOWN) > 0.99:
		print("[FlipBlocked] reason=already_floor_wall wall=", wall.name, " outward=", outward)
		return false
	var rotation_quat := Quaternion(outward, Vector3.DOWN)
	if rotation_quat.get_angle() < 0.01:
		print("[FlipBlocked] reason=zero_rotation_wall wall=", wall.name, " outward=", outward)
		return false
	_animate_flip(rotation_quat, player)
	return true


func get_nearest_walls_for(prop: Node3D) -> Array[Node3D]:
	var walls := get_node_or_null("WALLS")
	if walls == null or prop == null:
		var empty: Array[Node3D] = []
		return empty
	return _find_nearest_walls(prop, walls)


## True when a StaticBox/MovableBox occupies the wall junction the player is pressing into.
func _is_flip_blocked_by_box(collision_normal: Vector3, player: Node3D) -> bool:
	var toward_wall := -_snap_to_axis(collision_normal)
	if toward_wall.length_squared() < 0.5:
		return false

	var contact := player.global_position + toward_wall * 0.5
	var along_wall := Vector3.UP.cross(toward_wall)
	if along_wall.length_squared() < 0.0001:
		along_wall = Vector3.RIGHT
	else:
		along_wall = along_wall.normalized()

	var clearance := flip_junction_clearance
	for box in _collect_obstacle_boxes():
		if not is_instance_valid(box):
			continue
		var offset := box.global_position - contact
		var blocked := true
		if absf(offset.dot(Vector3.UP)) > clearance:
			blocked = false
		if absf(offset.dot(along_wall)) > clearance:
			blocked = false
		if absf(offset.dot(toward_wall)) > clearance:
			blocked = false
		if blocked:
			print("[FlipBlocked] box=", box.name, " box_pos=", box.global_position, " player=", player.global_position, " contact=", contact, " toward_wall=", toward_wall, " along_wall=", along_wall, " offset=", offset, " clearance=", clearance)
			return true
	return false


func _collect_obstacle_boxes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	_gather_obstacle_boxes(self, result)
	return result


## True when a prop at this cell explicitly allows the player to occupy it (e.g. open E2).
func is_passable_for_player(world_pos: Vector3) -> bool:
	const HALF_CELL := 0.51
	var passable := _has_passable_prop_at(self, world_pos, HALF_CELL)
	if passable:
		print("[PassableCell] world_pos=", world_pos)
	return passable


func _has_passable_prop_at(node: Node, world_pos: Vector3, half_cell: float) -> bool:
	for child in node.get_children():
		if child is Node3D:
			var n3 := child as Node3D
			if (
				(n3.get("allows_player_enter") == true or n3.get("is_open") == true)
				and "StaticBox" in String(n3.name)
			):
				var offset := n3.global_position - world_pos
				if (
					absf(offset.x) < half_cell
					and absf(offset.y) < half_cell
					and absf(offset.z) < half_cell
				):
					print("[PassableCell] prop=", n3.name, " prop_pos=", n3.global_position, " world_pos=", world_pos, " offset=", offset)
					return true
			if _has_passable_prop_at(child, world_pos, half_cell):
				return true
	return false


func _gather_obstacle_boxes(node: Node, result: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D:
			var n := String(child.name)
			# EXIT areas may contain "StaticBox" in the name — skip non-solid props.
			if (
				(child is StaticBody3D or child is RigidBody3D)
				and ("StaticBox" in n or "MovableBox" in n)
				and "EXIT" not in n
			):
				if child == _staticbox_template:
					continue
				var col := child.get_node_or_null("CollisionShape3D") as CollisionShape3D
				if col != null and col.disabled:
					continue
				if child.get("allows_player_enter") == true or child.get("is_open") == true:
					pass
				else:
					result.append(child as Node3D)
			_gather_obstacle_boxes(child, result)


func _on_left_pressed() -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	request_rotate_left(player)


## Rotate the whole cube (and player) 90° clockwise around world up.
func request_rotate_left(player: Node3D) -> bool:
	if flipping:
		return false
	if player == null:
		return false

	# Negative Y rotation is clockwise when viewed from above.
	var rotation_quat := Quaternion(Vector3.UP, -PI / 2.0)
	_animate_flip(rotation_quat, player, true)
	return true


func _on_right_pressed() -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	request_rotate_right(player)


## Rotate the whole cube (and player) 90° counterclockwise around world up.
func request_rotate_right(player: Node3D) -> bool:
	if flipping:
		return false
	if player == null:
		return false

	var rotation_quat := Quaternion(Vector3.UP, PI / 2.0)
	_animate_flip(rotation_quat, player, true)
	return true


func _snap_to_axis(v: Vector3) -> Vector3:
	var a := v.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector3(signf(v.x), 0.0, 0.0)
	if a.y >= a.z:
		return Vector3(0.0, signf(v.y), 0.0)
	return Vector3(0.0, 0.0, signf(v.z))


func _rotated_xform(xform: Transform3D, center: Vector3, q: Quaternion) -> Transform3D:
	return Transform3D(Basis(q) * xform.basis, center + q * (xform.origin - center))


## Bind StaticBox* and MovableBox* so they hide with their attached wall faces.
func _bind_props_to_walls() -> void:
	_wall_props.clear()
	var walls := get_node_or_null("WALLS")
	if walls == null:
		return

	var boxes_root := get_node_or_null("staticboxes")
	if boxes_root == null:
		boxes_root = get_node_or_null("staticbox")
	if boxes_root == null:
		boxes_root = self
		push_warning("Missing Node3D/staticbox(es); binding StaticBox props under cube root.")

	var props: Array[Node3D] = []
	_gather_wall_props(self, props)

	var host := get_parent()
	if host != null:
		for child in host.get_children():
			if child is Node3D and _is_wall_prop_name(String(child.name)):
				var found := child as Node3D
				if found not in props:
					props.append(found)

	for pattern in ["*StaticBox*", "*MovableBox*", "*Portal*", "*F_Trigger*"]:
		for node in walls.find_children(pattern, "Node3D", true, false):
			var found := node as Node3D
			if found != null and found not in props:
				props.append(found)

	for prop in props:
		var n := String(prop.name)
		if "StaticBox" in n:
			if prop.get_parent() != boxes_root:
				prop.reparent(boxes_root, true)
		elif "MovableBox" in n:
			# Keep under cube root so ui_ingame / physics still find them.
			if prop.get_parent() != self:
				prop.reparent(self, true)

		var bound_walls: Array[Node3D] = _bound_walls_for_prop(prop, walls)
		if bound_walls.is_empty():
			continue
		prop.add_to_group("wall_prop")
		_wall_props.append({"prop": prop, "walls": bound_walls})
		_set_prop_visible(prop, true)


func _is_wall_prop_name(n: String) -> bool:
	return (
		"StaticBox" in n
		or "MovableBox" in n
		or "Portal" in n
		or n == "F_Trigger"
		or n.begins_with("F_Trigger")
	)


func _gather_wall_props(node: Node, result: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D and _is_wall_prop_name(String(child.name)):
			result.append(child as Node3D)
		if child is Node3D and not _is_wall_prop_name(String(child.name)):
			_gather_wall_props(child, result)


## All walls at the minimum plane-distance (equal attach for corners/edges).
func _find_nearest_walls(prop: Node3D, walls: Node) -> Array[Node3D]:
	var dists: Dictionary = {} # wall -> dist
	var min_dist := INF
	var dbg_count := 0

	for child in walls.get_children():
		var wall := child as Node3D
		if wall == null:
			continue

		# 墙面的内向法线（即墙面垂直指向魔方内部的方向）
		var wall_inward := wall.global_transform.basis.y.normalized()

		# 计算 prop 到墙面平面的垂直距离
		var dist := absf(wall_inward.dot(prop.global_position - wall.global_position))
		dists[wall] = dist
		if dist < min_dist:
			min_dist = dist
		dbg_count += 1

	var result: Array[Node3D] = []
	if min_dist == INF:
		return result

	# 容差范围：0.65 可以确保位于格子内的 1x1x1 方块能准确匹配到贴近的墙面
	const EPS := 0.65
	for wall in dists:
		if dists[wall] <= min_dist + EPS:
			result.append(wall)
	return result


## Portal_Key sits on an edge/corner: always bind the two closest faces.
func _find_n_nearest_walls(prop: Node3D, walls: Node, count: int) -> Array[Node3D]:
	var scored: Array[Dictionary] = []
	for child in walls.get_children():
		var wall := child as Node3D
		if wall == null:
			continue
		var inward: Vector3 = wall.global_transform.basis.y.normalized()
		var dist := absf(inward.dot(prop.global_position - wall.global_position))
		scored.append({"d": dist, "wall": wall})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	var result: Array[Node3D] = []
	for i in range(mini(count, scored.size())):
		result.append(scored[i]["wall"] as Node3D)
	return result


func _bound_walls_for_prop(prop: Node3D, walls: Node) -> Array[Node3D]:
	var n := String(prop.name)
	# 钥匙固定贴最近两面：任一面裁切亮起即显示。
	if n == "Portal_Key" or n.begins_with("Portal_Key"):
		return _find_n_nearest_walls(prop, walls, 2)
	return _find_nearest_walls(prop, walls)


## Hide the 3 outer faces that point toward the camera so the room interior
## stays visible (needed when wall materials are double-sided).
## Props bound to multiple walls stay visible if any bound wall is shown.
func update_cutaway_visibility() -> void:
	var cam := _ensure_level_camera()
	if cam == null:
		return

	var walls := get_node_or_null("WALLS")
	if walls == null:
		return

	# 从魔方中心指向相机的方向向量
	var to_camera: Vector3 = (cam.global_position - get_center_global()).normalized()
	var wall_nodes: Dictionary = {} # wall name -> Node3D
	var wall_scores: Array[Dictionary] = []

	for wall_name in ["m1", "m2", "m3", "m4", "m5", "m6"]:
		var node := walls.get_node_or_null(wall_name)
		if node == null:
			continue
		if not (node is Node3D):
			continue
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue

		var wall := node as Node3D
		wall_nodes[wall_name] = wall

		var inward: Vector3 = wall.global_transform.basis.y.normalized()
		var outward: Vector3 = -inward
		var score := outward.dot(to_camera)
		wall_scores.append({"name": wall_name, "score": score})

	# Hide the three faces most facing the camera.
	wall_scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"])
	var hidden_names := {}
	for i in range(mini(3, wall_scores.size())):
		hidden_names[wall_scores[i]["name"]] = true

	for wall_name in wall_nodes.keys():
		var wall := wall_nodes[wall_name] as Node3D
		if wall == null or not is_instance_valid(wall) or wall.is_queued_for_deletion():
			continue
		var show_wall := not hidden_names.has(wall_name)
		var mesh := wall.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh != null:
			mesh.visible = show_wall

	# 更新绑定的实体块可见性
	var alive_props: Array[Dictionary] = []
	for entry in _wall_props:
		var prop := entry.get("prop") as Node3D
		if prop == null or not is_instance_valid(prop):
			continue

		var bound: Array = entry["walls"]
		# Filter out freed walls before use.
		var valid_bound: Array[Node3D] = []
		for wall in bound:
			if wall != null and is_instance_valid(wall) and not wall.is_queued_for_deletion():
				valid_bound.append(wall)
		if valid_bound.is_empty():
			continue

		alive_props.append({"prop": prop, "walls": valid_bound})

		# 只要绑定的墙壁中有任意一面是可见的，实体块就显示
		var show_prop := false
		for wall in valid_bound:
			if not hidden_names.has(String(wall.name)):
				show_prop = true
				break

		_set_prop_visible(prop, show_prop)

	_wall_props = alive_props


func _set_prop_visible(prop: Node3D, wall_visible: bool) -> void:
	if prop == null or not is_instance_valid(prop):
		return
	prop.visible = wall_visible
	for child in prop.get_children():
		if child != null and is_instance_valid(child) and child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not wall_visible
	if prop is RigidBody3D:
		var rb := prop as RigidBody3D
		if not wall_visible or _hold_props_frozen:
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.freeze = true
		elif not get_tree().paused:
			rb.freeze = false
	elif prop is CollisionObject3D:
		var body := prop as CollisionObject3D
		body.set_collision_layer_value(1, true)
		body.set_collision_mask_value(1, true)


func get_bound_wall_names_for_prop(prop: Node3D) -> Array[String]:
	var result: Array[String] = []
	if prop == null or not is_instance_valid(prop):
		return result
	for entry in _wall_props:
		var entry_prop := entry.get("prop") as Node3D
		if entry_prop == null or not is_instance_valid(entry_prop):
			continue
		if entry_prop != prop:
			continue
		var bound: Array = entry.get("walls", [])
		for wall in bound:
			if wall != null and is_instance_valid(wall):
				result.append(String((wall as Node3D).name))
		break
	return result


## Rotates cube and player together. Afterward the player stands upright but
## keeps the facing continuous with the rotation (no sudden yaw snap).
## Next flip/yaw waits until any gravity falls finish settling.
func _animate_flip(rot: Quaternion, player: Node3D, _keep_relative_facing: bool = false) -> void:
	flipping = true
	_hold_props_frozen = true
	flip_started.emit()
	_freeze_fallable_props()

	var center := get_center_global()
	var cube_start := global_transform
	var player_start := player.global_transform
	var player_scale := player.scale

	var pivot: Node3D = player.get_node_or_null("Pivot") as Node3D
	var facing_start := Vector3(0.0, 0.0, -1.0)
	if pivot != null:
		facing_start = -pivot.global_basis.z
	else:
		facing_start = -player_start.basis.z

	player.set_physics_process(false)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if "target_velocity" in player:
		player.target_velocity = Vector3.ZERO
	if "moving_chain" in player:
		player.moving_chain = false
	if "jump_preparing" in player:
		player.jump_preparing = false

	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(
		func(t: float) -> void:
			var q := Quaternion.IDENTITY.slerp(rot, t)
			global_transform = _rotated_xform(cube_start, center, q)
			player.global_transform = _rotated_xform(player_start, center, q)
			update_cutaway_visibility(),
		0.0,
		1.0,
		flip_duration
	)

	await tween.finished

	global_transform.basis = global_transform.basis.orthonormalized()

	var final_xform := _rotated_xform(player_start, center, rot)
	# Continue facing through the flip, then flatten onto the new floor (XZ).
	var facing: Vector3 = rot * facing_start
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		# Old facing became mostly vertical (e.g. walked straight into the wall).
		facing = rot * Vector3.UP
		facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3(0.0, 0.0, -1.0)
	else:
		facing = facing.normalized()

	# Stand upright; bake continued yaw into Pivot so WASD can sync to it.
	player.global_transform = Transform3D(Basis.IDENTITY, final_xform.origin)
	player.scale = player_scale
	if pivot != null:
		pivot.basis = Basis.looking_at(facing)
	if player.has_method("sync_move_from_facing"):
		player.sync_move_from_facing()

	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if "target_velocity" in player:
		player.target_velocity = Vector3.ZERO

	# Release hold so cutaway can unfreeze visible fallable props; then wait for settle.
	_hold_props_frozen = false
	update_cutaway_visibility()

	player.set_physics_process(true)
	await _wait_for_props_to_settle()
	flipping = false
	flip_finished.emit()


func _freeze_fallable_props() -> void:
	for rb in _gather_fallable_bodies():
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.freeze = true


func _gather_fallable_bodies() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	_gather_fallable_bodies_rec(self, result)
	return result


func _gather_fallable_bodies_rec(node: Node, result: Array[RigidBody3D]) -> void:
	for child in node.get_children():
		if child is RigidBody3D and _is_fallable_body(child as RigidBody3D):
			result.append(child as RigidBody3D)
		_gather_fallable_bodies_rec(child, result)


func _is_fallable_body(rb: RigidBody3D) -> bool:
	if rb == null or not is_instance_valid(rb):
		return false
	return "MovableBox" in String(rb.name)


func _body_is_settled(rb: RigidBody3D) -> bool:
	if rb == null or not is_instance_valid(rb):
		return true
	if rb.freeze or rb.sleeping:
		return true
	if rb.linear_velocity.length() > settle_velocity_epsilon:
		return false
	if rb.angular_velocity.length() > settle_velocity_epsilon:
		return false
	return true


func _all_fallable_props_settled() -> bool:
	for rb in _gather_fallable_bodies():
		if not _body_is_settled(rb):
			return false
	return true


func _wait_for_props_to_settle() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var stable := 0
	var elapsed := 0.0
	while elapsed < settle_timeout:
		if not is_inside_tree():
			return
		if get_tree().paused:
			await get_tree().process_frame
			if not is_inside_tree():
				return
			continue
		if _all_fallable_props_settled():
			stable += 1
			if stable >= settle_stable_frames:
				return
		else:
			stable = 0
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		elapsed += get_physics_process_delta_time()


# ═══════════════════════════════════════════════════════════════
#  Zen-mode map generation
# ═══════════════════════════════════════════════════════════════

func generate() -> void:
	# 新地图生成前：恢复到场景默认姿态，避免残留上一局的翻转/旋转。
	if is_instance_valid(self) and _map_saved:
		global_transform = _base_cube_transform
	_clear_generated()
	rng.randomize()

	var ok := false
	for _i in range(300):
		# Order matters: pick start/end first, then generate blocks around them.
		_init_matrix()
		if not _pick_start_end():
			continue
		_generate_surface()
		path = _find_path_with_retry()
		if path.is_empty():
			continue
		if _count_path_faces(path) >= 4:
			ok = true
			break

	if not ok:
		push_error("Zen: cannot generate a path across ≥4 faces.")
		return

	cube_half_extent = float(n) / 2.0
	_wall_props.clear()

	# 保存当前布局，供“重置本关”恢复同一张地图。
	_saved_matrix = matrix.duplicate(true)
	_saved_start_pos = start_pos
	_saved_end_pos = end_pos
	_saved_path = path.duplicate()
	_map_saved = true

	# 同步构建，保证调整相机/放置玩家在返回前完成，避免与下一次生成交错。
	_apply_map()

	# 记录生成完成后的朝向，重置时恢复（此时未翻转，是标准朝向）。
	_saved_cube_transform = global_transform

	update_cutaway_visibility()
	generation_finished.emit()


## 用上次保存的布局重建地图（方块、出生点、终点），供“重置本关”恢复。
func restore_saved_map() -> void:
	if not _map_saved:
		generate()
		return

	# 先清掉上一次生成的克隆体，避免重置时方块重复叠加。
	_clear_generated()

	matrix = _saved_matrix.duplicate(true)
	start_pos = _saved_start_pos
	end_pos = _saved_end_pos
	path = _saved_path.duplicate()
	cube_half_extent = float(n) / 2.0
	_wall_props.clear()

	# 恢复生成时的立方体朝向/位置，避免用已翻转的坐标系放置玩家。
	if is_instance_valid(self) and _map_saved:
		global_transform = _saved_cube_transform

	_apply_map()
	update_cutaway_visibility()
	generation_finished.emit()



func _apply_map() -> void:
	_scale_shell_walls()
	_clone_wall_boxes()
	_position_exit()
	_bind_boxes_to_walls()
	adjust_camera()

	# 玩家始终从底面出生 → 不需要旋转，直接放在 world 坐标
	_place_player_at()


## 根据矩阵尺寸 n（6–12）调节：
##  - Marker3D/Camera3D 的 Size：10 → 20
##  - Marker3D 的 position.y：0 → 3（尺寸越大相机抬得越高，画面更好看）
## Marker3D 是 Main（本节点的父级）的子节点，因此通过 get_parent() 访问。
## 公开方法：生成/重置流程都可能调用，保证相机始终跟随当前尺寸。
func adjust_camera() -> void:
	var t := clampf((float(n) - 6.0) / 6.0, 0.0, 1.0)

	var marker := get_parent().get_node_or_null("Marker3D") as Marker3D
	if marker == null:
		marker = get_node_or_null("Marker3D") as Marker3D
	if marker != null:
		var pos := marker.position
		pos.y = lerpf(0.0, 3.0, t)
		marker.position = pos

		# 同时调节 Marker3D 下的相机 Size。
		var cam := marker.get_node_or_null("Camera3D") as Camera3D
		if cam != null:
			cam.size = lerpf(10.0, 20.0, t)
			cam.make_current()
		return

	# 兜底：找不到 Marker3D 时，仍调节视口当前相机。
	var active := get_viewport().get_camera_3d()
	if active != null:
		active.size = lerpf(10.0, 20.0, t)
		active.make_current()


func _clear_generated() -> void:
	# Clear wall-prop bindings first so freed props are not referenced.
	_wall_props.clear()
	# Remove cloned static boxes (always keep the template & EXIT)
	var sboxes := get_node_or_null("staticboxes")
	if sboxes == null:
		return
	var to_delete: Array[Node] = []
	for c in sboxes.get_children():
		if c is StaticBody3D and String(c.name).begins_with("StaticBox"):
			if _staticbox_template == null or not is_instance_valid(_staticbox_template):
				_staticbox_template = c as StaticBody3D
			if c == _staticbox_template:
				continue   # always keep the template alive
			to_delete.append(c)
	for c in to_delete:
		sboxes.remove_child(c)
		c.free()


func _scale_shell_walls() -> void:
	var walls := get_node_or_null("WALLS")
	if walls == null:
		return
	var half := float(n) / 2.0
	# Wall specs matching the WALLS8_8 reference: each StaticBody3D is placed
	# directly on the wall plane, with the collision shape offset 0.5 along
	# local -Y (outward) so the walkable surface is exactly on the wall plane.
	# basis.y of each wall transform is the INWARD direction (toward cube center).
	var specs := {
		"m1": {"pos": Vector3(0, 0, 0),                "basis_y": Vector3.UP},       # bottom → inward +Y
		"m2": {"pos": Vector3(0, half, -half),         "basis_y": Vector3.BACK},      # back   → inward +Z
		"m3": {"pos": Vector3(half, half, 0),          "basis_y": Vector3.LEFT},      # right  → inward -X
		"m4": {"pos": Vector3(0, float(n), 0),         "basis_y": Vector3.DOWN},      # top    → inward -Y
		"m5": {"pos": Vector3(0, half, half),          "basis_y": Vector3.FORWARD},   # front  → inward -Z
		"m6": {"pos": Vector3(-half, half, 0),         "basis_y": Vector3.RIGHT},     # left   → inward +X
	}
	for child in walls.get_children():
		var spec: Dictionary = specs.get(child.name, {})
		if spec.is_empty():
			continue
		var wall := child as Node3D
		wall.visible = true
		var inward: Vector3 = spec["basis_y"]
		# Build a basis where local Y = inward direction, keeping local X/Z
		# aligned to world axes as much as possible.
		var b := Basis()
		b.y = inward
		# Pick a reference axis that is not parallel to inward.
		var ref := Vector3.UP if absf(inward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		b.x = ref.cross(inward).normalized()
		b.z = b.x.cross(inward).normalized()
		wall.transform = Transform3D(b, spec["pos"])
		wall.scale = Vector3.ONE

		var col := wall.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col != null:
			var shape := BoxShape3D.new()
			shape.size = Vector3(float(n), 1.0, float(n))
			col.shape = shape
			# Collision shape sits 0.5 along local -Y (outward side of wall).
			col.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0))

		var vis := wall.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if vis != null:
			var new_plane := PlaneMesh.new()
			new_plane.size = Vector2(float(n), float(n))
			vis.mesh = new_plane
			vis.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
			vis.visible = true


func _clone_wall_boxes() -> void:
	if _staticbox_template == null or not is_instance_valid(_staticbox_template):
		return
	var sboxes := get_node_or_null("staticboxes")
	if sboxes == null:
		return

	for x in range(n):
		for y in range(n):
			for z in range(n):
				if matrix[x][y][z] == 1:
					var clone := _staticbox_template.duplicate() as StaticBody3D
					clone.position = _wp(x, y, z)
					clone.scale = Vector3.ONE
					sboxes.add_child(clone)
					# Give each clone a unique name that starts with "StaticBox" so
					# binding/cleanup logic can identify them reliably.
					clone.name = "StaticBox" + str(sboxes.get_child_count())

	# Hide the template – it's only for cloning, not gameplay
	if _staticbox_template != null and is_instance_valid(_staticbox_template):
		_staticbox_template.visible = false
		var tcol := _staticbox_template.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if tcol != null:
			tcol.disabled = true


func _bind_boxes_to_walls() -> void:
	## Bind each cloned StaticBox to its nearest shell wall(s) so
	## the existing cutaway toggles their visibility automatically.
	## This runs AFTER _orient_start_as_floor(), so global_transform is valid.
	var walls := get_node_or_null("WALLS")
	if walls == null:
		return
	var sboxes := get_node_or_null("staticboxes")
	if sboxes == null:
		return

	for child in sboxes.get_children():
		if child == _staticbox_template:
			continue   # skip the clone template
		if not (child is StaticBody3D and String(child.name).begins_with("StaticBox")):
			continue
		var bound := _find_nearest_walls(child as Node3D, walls)
		if bound.is_empty():
			continue
		child.add_to_group("wall_prop")
		_wall_props.append({"prop": child, "walls": bound})
		_set_prop_visible(child as Node3D, true)


func _position_exit() -> void:
	var sboxes := get_node_or_null("staticboxes")
	if sboxes == null:
		return
	var exit_area := sboxes.get_node_or_null("StaticBox_EXIT") as Area3D
	if exit_area == null:
		return

	var outward := _surface_normal(end_pos)
	# Offset INWARD so the exit marker pokes into the room from the wall.
	exit_area.position = _wp(end_pos.x, end_pos.y, end_pos.z) - outward * 0.6
	exit_area.scale = Vector3.ONE

	# Bind the exit Area to nearest wall(s) so it hides with cutaway.
	var walls := get_node_or_null("WALLS")
	if walls != null:
		var bound := _find_nearest_walls(exit_area as Node3D, walls)
		if not bound.is_empty():
			exit_area.add_to_group("wall_prop")
			_wall_props.append({"prop": exit_area, "walls": bound})
			_set_prop_visible(exit_area as Node3D, true)



func _orient_start_as_floor() -> void:
	## Rotate this node around its geometric center so the start face becomes the floor.
	var outward := _surface_normal(start_pos)
	if outward.dot(Vector3.DOWN) > 0.99:
		return  # 已经是底面，不需要旋转
	var q := Quaternion(outward, Vector3.DOWN)
	if q.get_angle() < 0.01:
		return
	var center := to_global(Vector3(0.0, cube_half_extent, 0.0))
	global_transform = _rotated_xform(global_transform, center, q)
	global_transform.basis = global_transform.basis.orthonormalized()


func _place_player_at() -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	if player == null:
		return

	# _wp 返回格子的精确中心，用 local 坐标转 world
	var world_pos := to_global(_wp(start_pos.x, start_pos.y, start_pos.z))
	world_pos.y = 0.55  # 底面碰撞壳顶部（壳厚1，-0.5~0.5）
	# x/z 保持 _wp 返回的精确中心值（不 snapped）

	var player_scale := player.scale
	var xform := Transform3D(Basis.IDENTITY, world_pos).scaled(player_scale)
	if player.has_method("set_start_transform"):
		player.set_start_transform(xform)
	player.global_transform = xform
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


# ═══════════════════════════════════════════════════════════════
#  Grid helpers
# ═══════════════════════════════════════════════════════════════

func _wp(x: int, y: int, z: int) -> Vector3:
	# Block centers sit 0.5 inside each face so 1×1×1 boxes rest on the
	# shell plane and stay flush with its interior surface.
	var o := -(n - 1) / 2.0
	return Vector3(x + o, float(y) + 0.5, z + o)


func _surface_normal(p: Vector3i) -> Vector3:
	if p.x == 0:       return Vector3.LEFT
	if p.x == n - 1:   return Vector3.RIGHT
	if p.y == 0:       return Vector3.DOWN
	if p.y == n - 1:   return Vector3.UP
	if p.z == 0:       return Vector3.FORWARD
	return Vector3.BACK


func _is_on_surface(x: int, y: int, z: int) -> bool:
	return x == 0 or x == n - 1 or y == 0 or y == n - 1 or z == 0 or z == n - 1


func _get_faces(p: Vector3i) -> Array[String]:
	var faces: Array[String] = []
	if p.x == 0:       faces.append("Left")
	elif p.x == n - 1: faces.append("Right")
	if p.y == 0:       faces.append("Bottom")
	elif p.y == n - 1: faces.append("Top")
	if p.z == 0:       faces.append("Back")
	elif p.z == n - 1: faces.append("Front")
	return faces


func _count_path_faces(p: Array[Vector3i]) -> int:
	var used := {}
	for cell in p:
		for face in _get_faces(cell):
			used[face] = true
	return used.size()


# ═══════════════════════════════════════════════════════════════
#  Matrix & path-finding
# ═══════════════════════════════════════════════════════════════

func _init_matrix() -> void:
	matrix.clear()
	for x in range(n):
		var p: Array = []
		for y in range(n):
			var r: Array = []
			for _z in range(n):
				r.append(0)
			p.append(r)
		matrix.append(p)


func _generate_surface() -> void:
	for x in range(n):
		for y in range(n):
			for z in range(n):
				if not _is_on_surface(x, y, z):
					continue
				# Never place a solid block on start or end position.
				var p := Vector3i(x, y, z)
				if p == start_pos or p == end_pos:
					matrix[x][y][z] = 0
				else:
					matrix[x][y][z] = rng.randi_range(0, 1)


func _pick_start_end() -> bool:
	# Called before _generate_surface, so the matrix is all zeros here.
	# Pick start/end from all surface cells; _generate_surface will keep
	# those two cells clear when scattering solid blocks.
	var cells: Array[Vector3i] = []
	for x in range(n):
		for y in range(n):
			for z in range(n):
				if _is_on_surface(x, y, z):
					cells.append(Vector3i(x, y, z))
	if cells.size() < 2:
		return false

	# Prefer a spawn strictly inside the bottom face (y == 0, not on any edge)
	# so surface_normal returns DOWN and the player spawns flat on the floor.
	var bottom_cells: Array[Vector3i] = []
	for r in cells:
		if r.y == 0 and r.x != 0 and r.x != n - 1 and r.z != 0 and r.z != n - 1:
			bottom_cells.append(r)
	if not bottom_cells.is_empty():
		start_pos = bottom_cells[rng.randi_range(0, bottom_cells.size() - 1)]
	else:
		# Fallback: any bottom-face cell, even on an edge.
		var any_bottom: Array[Vector3i] = []
		for r in cells:
			if r.y == 0:
				any_bottom.append(r)
		if not any_bottom.is_empty():
			start_pos = any_bottom[rng.randi_range(0, any_bottom.size() - 1)]
		else:
			start_pos = cells[rng.randi_range(0, cells.size() - 1)]
	var cand: Array[Vector3i] = []
	for c in cells:
		var d := maxi(absi(c.x - start_pos.x), maxi(absi(c.y - start_pos.y), absi(c.z - start_pos.z)))
		if c != start_pos and d > 2:
			cand.append(c)
	if cand.is_empty():
		cand = cells.duplicate()
		cand.erase(start_pos)
	end_pos = cand[rng.randi_range(0, cand.size() - 1)]
	return true


func _neighbors(p: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for d: Vector3i in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var q: Vector3i = p + d
		if q.x >= 0 and q.y >= 0 and q.z >= 0 and q.x < n and q.y < n and q.z < n:
			if _is_on_surface(q.x, q.y, q.z) and matrix[q.x][q.y][q.z] == 0:
				out.append(q)
	return out


func _find_path_with_retry() -> Array[Vector3i]:
	for _i in range(5000):
		var p := _bfs()
		if not p.is_empty():
			return p
		_remove_wall()
	return []


func _bfs() -> Array[Vector3i]:
	var q: Array[Vector3i] = [start_pos]
	var head := 0
	var vis: Dictionary = {}
	var par: Dictionary = {}
	vis[start_pos] = true
	while head < q.size():
		var c: Vector3i = q[head]; head += 1
		if c == end_pos:
			var r: Array[Vector3i] = [c]
			while par.has(c):
				c = par[c]
				r.push_front(c)
			return r
		for nb: Vector3i in _neighbors(c):
			if not vis.has(nb):
				vis[nb] = true
				par[nb] = c
				q.append(nb)
	_last_visited = vis
	return []


func _remove_wall() -> void:
	var list: Array[Vector3i] = []
	for k in _last_visited.keys():
		var c: Vector3i = k
		for d: Vector3i in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var q2: Vector3i = c + d
			if q2.x >= 0 and q2.y >= 0 and q2.z >= 0 and q2.x < n and q2.y < n and q2.z < n:
				if _is_on_surface(q2.x, q2.y, q2.z) and matrix[q2.x][q2.y][q2.z] == 1 and not list.has(q2):
					list.append(q2)
	if list.is_empty():
		return
	var w := list[rng.randi_range(0, list.size() - 1)]
	matrix[w.x][w.y][w.z] = 0

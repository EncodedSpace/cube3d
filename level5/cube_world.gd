extends Node3D

## Rotates the cube so a hit face becomes the new floor.
## Player is carried through the same rotation, then falls onto it.

@export var flip_duration: float = 0.55
@export var cube_half_extent: float = 3.0
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


func _ready() -> void:
	start_transform = global_transform
	_bind_props_to_walls()
	# Camera may not be current on the first frame after a scene change.
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
	global_transform = start_transform
	update_cutaway_visibility()


func request_flip(collision_normal: Vector3, player: Node3D) -> bool:
	if flipping:
		return false

	# Collision normal points toward the player (into the room).
	# The face's outward direction is the opposite; that should become world down.
	var outward := _snap_to_axis(-collision_normal)
	if outward.dot(Vector3.DOWN) > 0.99:
		return false

	var rotation_quat := Quaternion(outward, Vector3.DOWN)
	if rotation_quat.get_angle() < 0.01:
		return false

	# Only empty floor-wall junctions can flip (no StaticBox / MovableBox there).
	if player != null and _is_flip_blocked_by_box(collision_normal, player):
		return false

	_animate_flip(rotation_quat, player)
	return true


## Orient so this wall becomes the floor (portal teleport). Skips junction-box blocking.
func request_orient_wall_as_floor(wall: Node3D, player: Node3D) -> bool:
	if flipping or wall == null:
		return false
	var inward := wall.global_transform.basis.y.normalized()
	var outward := _snap_to_axis(-inward)
	if outward.dot(Vector3.DOWN) > 0.99:
		return false
	var rotation_quat := Quaternion(outward, Vector3.DOWN)
	if rotation_quat.get_angle() < 0.01:
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
		if absf(offset.dot(Vector3.UP)) > clearance:
			continue
		if absf(offset.dot(along_wall)) > clearance:
			continue
		if absf(offset.dot(toward_wall)) > clearance:
			continue
		return true
	return false


func _collect_obstacle_boxes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	_gather_obstacle_boxes(self, result)
	return result


## True when a prop at this cell explicitly allows the player to occupy it (e.g. open E2).
func is_passable_for_player(world_pos: Vector3) -> bool:
	const HALF_CELL := 0.51
	return _has_passable_prop_at(self, world_pos, HALF_CELL)


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
				# E2 解锁后允许玩家进入，不再当翻滚障碍。
				if child.get("allows_player_enter") == true or child.get("is_open") == true:
					pass
				else:
					result.append(child as Node3D)
			# Closed D_Wall blocks player rolls (check parent tool part by name).
			elif (
				("D_Wall" in n or n.begins_with("D_Wall"))
				and child.get("is_open") != true
			):
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

	# Recover boxes left under the scene root (Main) instead of the cube.
	var host := get_parent()
	if host != null:
		for child in host.get_children():
			if child is Node3D and _is_wall_prop_name(String(child.name)):
				var found := child as Node3D
				if found not in props:
					props.append(found)

	# Recover boxes that may still sit under WALLS from older parenting.
	for pattern in ["*StaticBox*", "*MovableBox*", "*D_Wall*", "*B_Tool*", "*G_Tool*", "*Portal*", "*F_Trigger*", "*Final_*"]:
		for node in walls.find_children(pattern, "Node3D", true, false):
			var found := node as Node3D
			if found != null and found not in props:
				props.append(found)

	for prop in props:
		var n := String(prop.name)
		# Static props live under staticboxes; movable boxes stay under the cube root
		# so ui_ingame / physics keep finding them as direct children.
		# Tool_B_D_G parts stay under their tool group (do not reparent).
		if "StaticBox" in n:
			if prop.get_parent() != boxes_root:
				prop.reparent(boxes_root, true)
		elif "MovableBox" in n:
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
		or n.begins_with("Final_")
		or n == "D_Wall"
		or n == "B_Tool"
		or n == "G_Tool"
		or n == "F_Trigger"
		or n.begins_with("D_Wall")
		or n.begins_with("B_Tool")
		or n.begins_with("G_Tool")
		or n.begins_with("F_Trigger")
	)


func _gather_wall_props(node: Node, result: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D and _is_wall_prop_name(String(child.name)):
			result.append(child as Node3D)
		# Keep walking containers; skip descending into a prop itself.
		if child is Node3D and not _is_wall_prop_name(String(child.name)):
			_gather_wall_props(child, result)


## All walls at the minimum plane-distance (equal attach for corners/edges).
func _find_nearest_walls(prop: Node3D, walls: Node) -> Array[Node3D]:
	var best_dist := INF
	var dists: Dictionary = {} # wall -> dist

	for child in walls.get_children():
		var wall := child as Node3D
		if wall == null:
			continue
		var inward: Vector3 = wall.global_transform.basis.y.normalized()
		var dist := absf(inward.dot(prop.global_position - wall.global_position))
		dists[wall] = dist
		if dist < best_dist:
			best_dist = dist

	var result: Array[Node3D] = []
	if best_dist == INF:
		return result

	# 棱/角上等距绑多面。容差要覆盖刚体落稳后的微小偏移，
	# 否则会从「地板+侧墙」退化成只绑侧墙，侧墙裁切时箱子在亮着的地板上消失。
	const EPS := 0.25
	for wall in dists:
		if dists[wall] <= best_dist + EPS:
			result.append(wall)
	return result


## 所有道具统一：等距多面绑定；裁切时任一面可见则道具可见。
func _bound_walls_for_prop(prop: Node3D, walls: Node) -> Array[Node3D]:
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

	var to_camera: Vector3 = (cam.global_position - get_center_global()).normalized()
	var wall_shown: Dictionary = {} # wall -> bool

	for child in walls.get_children():
		var wall := child as Node3D
		if wall == null:
			continue
		var inward: Vector3 = wall.global_transform.basis.y.normalized()
		var outward: Vector3 = -inward
		var show_wall := outward.dot(to_camera) <= wall_visible_dot
		wall_shown[wall] = show_wall
		var mesh := wall.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh != null:
			mesh.visible = show_wall

	# Drop props that were freed (e.g. G_Tool after player collects it).
	var alive_props: Array[Dictionary] = []
	for entry in _wall_props:
		var prop_ref = entry.get("prop")
		if prop_ref == null or not is_instance_valid(prop_ref):
			continue
		var prop := prop_ref as Node3D
		if prop == null:
			continue
		alive_props.append(entry)

		# 每次刷新等距绑定；绑定面中任一面可见则道具可见。
		entry["walls"] = _bound_walls_for_prop(prop, walls)
		var bound: Array = entry["walls"]

		# MovableBox / B（开重力后）：只绑天花板或已真正下落中时自管显隐。
		if (
			prop.has_method("sync_ceiling_fall")
			and prop.sync_ceiling_fall(bound, _hold_props_frozen)
		):
			continue

		var show_prop := false
		for wall in bound:
			if wall != null and is_instance_valid(wall) and wall_shown.get(wall, false):
				show_prop = true
				break
		_set_prop_visible(prop, show_prop)
	_wall_props = alive_props


func _set_prop_visible(prop: Node3D, wall_visible: bool) -> void:
	# D_Wall / D_Wall2：始终跟随绑定墙裁切（与 G 无关）；开门后无固体碰撞。
	# 隐藏时只关 StaticBody，保留 Area。
	if prop.has_method("should_keep_player_block"):
		var closed: bool = prop.should_keep_player_block()
		if not closed:
			# 已开门：跟墙显隐，不挡人；同步吸附的 B（D+B 合体贴面隐藏）。
			if prop.has_method("sync_adsorbed_partner_visibility"):
				prop.sync_adsorbed_partner_visibility(wall_visible)
			else:
				prop.visible = wall_visible
			_set_d_solid_disabled(prop, true)
			return

		prop.visible = wall_visible
		if wall_visible:
			if prop.has_method("ensure_player_block"):
				prop.ensure_player_block()
		else:
			_set_d_solid_disabled(prop, true)
		return

	# B_Tool / Portal / Portal_Key / E1 / E2：自管碰撞与显隐。
	if prop.has_method("apply_cutaway_visibility"):
		prop.apply_cutaway_visibility(wall_visible)
		return

	prop.visible = wall_visible
	_set_collision_shapes_disabled(prop, not wall_visible)
	# Only MovableBox uses freeze for cutaway. G_Tool manages freeze itself.
	# 锁在 E1 里的箱子保持 freeze，不被裁切逻辑解开。
	if prop is RigidBody3D and "MovableBox" in String(prop.name):
		var rb := prop as RigidBody3D
		if prop.has_meta("locked_in_e1") and bool(prop.get_meta("locked_in_e1")):
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.freeze = true
		elif not wall_visible or _hold_props_frozen:
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			rb.freeze = true
		elif not get_tree().paused:
			rb.freeze = false


func _set_collision_shapes_disabled(node: Node, disabled: bool) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disabled
	for child in node.get_children():
		_set_collision_shapes_disabled(child, disabled)


## 只开关 D 的固体碰撞，不动 Area（B 检测）。
func _set_d_solid_disabled(d_prop: Node, disabled: bool) -> void:
	var static_body := d_prop.get_node_or_null("StaticBody3D") as StaticBody3D
	if static_body == null:
		return
	if disabled:
		static_body.collision_layer = 0
	else:
		static_body.collision_layer = 1
	for child in static_body.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = disabled


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
	var n := String(rb.name)
	if "MovableBox" in n:
		if rb.has_meta("locked_in_e1") and bool(rb.get_meta("locked_in_e1")):
			return false
		return true
	if rb.is_in_group("b_tool"):
		return rb.get("gravity_enabled") == true and rb.get("adsorbed") != true
	return false


func _body_is_settled(rb: RigidBody3D) -> bool:
	if rb == null or not is_instance_valid(rb):
		return true
	# Locked / adsorbed / cutaway-hidden bodies stay frozen → settled.
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
	# Let physics start falling for at least one frame after unfreeze.
	await get_tree().physics_frame
	var stable := 0
	var elapsed := 0.0
	while elapsed < settle_timeout:
		if get_tree().paused:
			await get_tree().process_frame
			continue
		if _all_fallable_props_settled():
			stable += 1
			if stable >= settle_stable_frames:
				return
		else:
			stable = 0
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

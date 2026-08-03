extends Node3D

## Rotates the cube so a hit face becomes the new floor.
## Player is carried through the same rotation, then falls onto it.

@export var flip_duration: float = 0.55
@export var cube_half_extent: float = 3.0
## How strongly an outer wall must face the camera to be cut away.
@export var wall_visible_dot: float = 0.2
## Half-size of the floor-wall junction cell that must be clear of boxes to flip.
@export var flip_junction_clearance: float = 0.75

var flipping: bool = false
var start_transform: Transform3D

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
	for pattern in ["*StaticBox*", "*MovableBox*", "*D_Wall*", "*B_Tool*", "*G_Tool*"]:
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

		var bound_walls: Array[Node3D] = _find_nearest_walls(prop, walls)
		if bound_walls.is_empty():
			continue
		prop.add_to_group("wall_prop")
		_wall_props.append({"prop": prop, "walls": bound_walls})
		_set_prop_visible(prop, true)


func _is_wall_prop_name(n: String) -> bool:
	return (
		"StaticBox" in n
		or "MovableBox" in n
		or n == "D_Wall"
		or n == "B_Tool"
		or n == "G_Tool"
		or n.begins_with("D_Wall")
		or n.begins_with("B_Tool")
		or n.begins_with("G_Tool")
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

	const EPS := 0.001
	for wall in dists:
		if dists[wall] <= best_dist + EPS:
			result.append(wall)
	return result


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

		# Moving props / D_Wall: refresh nearest walls (keeps multi-face binds).
		var prop_name := String(prop.name)
		if (
			"MovableBox" in prop_name
			or prop_name == "D_Wall"
			or prop_name.begins_with("D_Wall")
			or prop_name == "B_Tool"
			or prop_name == "G_Tool"
			or prop_name.begins_with("B_Tool")
			or prop_name.begins_with("G_Tool")
		):
			entry["walls"] = _find_nearest_walls(prop, walls)
		var bound: Array = entry["walls"]
		var show_prop := false
		for wall in bound:
			if wall != null and is_instance_valid(wall) and wall_shown.get(wall, false):
				show_prop = true
				break
		_set_prop_visible(prop, show_prop)
	_wall_props = alive_props


func _set_prop_visible(prop: Node3D, wall_visible: bool) -> void:
	# Falling B must keep WALLS collision, or it will drop out of the cube.
	if (
		prop.is_in_group("b_tool")
		and prop.get("gravity_enabled") == true
		and prop.get("adsorbed") != true
	):
		prop.visible = true
		_set_collision_shapes_disabled(prop, false)
		return

	# D_Wall:
	# - before G: any bound face lit → visible + collision
	# - after G, before open: always visible + collision
	# - after open: no solid collision
	if prop.has_method("should_keep_player_block"):
		var closed: bool = prop.should_keep_player_block()
		if not closed:
			prop.visible = true
			_set_collision_shapes_disabled(prop, true)
			return

		var show_d := wall_visible
		if prop.has_method("should_force_visible_block") and prop.should_force_visible_block():
			show_d = true

		prop.visible = show_d
		if show_d:
			if prop.has_method("ensure_player_block"):
				prop.ensure_player_block()
		else:
			_set_collision_shapes_disabled(prop, true)
		return

	prop.visible = wall_visible
	_set_collision_shapes_disabled(prop, not wall_visible)
	# Only MovableBox uses freeze for cutaway. B_Tool/G_Tool manage freeze themselves.
	if prop is RigidBody3D and "MovableBox" in String(prop.name):
		var rb := prop as RigidBody3D
		if not wall_visible:
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


## Rotates cube and player together. Afterward the player stands upright but
## keeps the facing continuous with the rotation (no sudden yaw snap).
func _animate_flip(rot: Quaternion, player: Node3D, _keep_relative_facing: bool = false) -> void:
	flipping = true
	flip_started.emit()

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

	update_cutaway_visibility()

	player.set_physics_process(true)
	flipping = false
	flip_finished.emit()

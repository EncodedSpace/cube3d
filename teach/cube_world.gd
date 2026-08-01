extends Node3D

## Rotates the cube so a hit face becomes the new floor.
## Player is carried through the same rotation, then falls onto it.

@export var flip_duration: float = 0.55
@export var cube_half_extent: float = 3.0
## How strongly an outer wall must face the camera to be cut away.
@export var wall_visible_dot: float = 0.2

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
	# Wait one frame so the camera exists in the tree.
	await get_tree().process_frame
	update_cutaway_visibility()


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

	_animate_flip(rotation_quat, player)
	return true


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


## Bind every node whose name contains "StaticBox" to nearby wall face(s).
func _bind_props_to_walls() -> void:
	_wall_props.clear()
	var walls := get_node_or_null("WALLS")
	if walls == null:
		return

	var props: Array[Node3D] = []
	for child in get_children():
		if child is Node3D and "StaticBox" in child.name:
			props.append(child as Node3D)
	# Recover boxes that may still sit under WALLS from older parenting.
	for node in walls.find_children("*StaticBox*", "Node3D", true, false):
		var found := node as Node3D
		if found != null and found not in props:
			props.append(found)

	for prop in props:
		if prop.get_parent() != self:
			prop.reparent(self, true)
		var bound_walls: Array[Node3D] = _find_nearest_walls(prop, walls)
		if bound_walls.is_empty():
			continue
		prop.add_to_group("wall_prop")
		_wall_props.append({"prop": prop, "walls": bound_walls})
		_set_prop_visible(prop, true)


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
	var cam := get_viewport().get_camera_3d()
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
		var is_outer_cutaway := outward.dot(to_camera) > wall_visible_dot
		var show_wall := not is_outer_cutaway
		wall_shown[wall] = show_wall

		var mesh := wall.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh != null:
			mesh.visible = show_wall

	for entry in _wall_props:
		var prop := entry["prop"] as Node3D
		var bound: Array = entry["walls"]
		if prop == null or not is_instance_valid(prop):
			continue
		var show_prop := false
		for wall in bound:
			if wall != null and is_instance_valid(wall) and wall_shown.get(wall, false):
				show_prop = true
				break
		_set_prop_visible(prop, show_prop)


func _set_prop_visible(prop: Node3D, wall_visible: bool) -> void:
	prop.visible = wall_visible
	for child in prop.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not wall_visible
	if prop is CollisionObject3D:
		var body := prop as CollisionObject3D
		body.set_collision_layer_value(1, true)
		body.set_collision_mask_value(1, true)


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

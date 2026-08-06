extends Node3D

## Zen-mode cube world: procedurally generates surface-block maps
## and supports Q/E rotation like the main game levels.

@export var n: int = 8
@export var flip_duration: float = 0.55
## How strongly an outer wall must face the camera to be cut away.
@export var wall_visible_dot: float = 0.4

var matrix: Array = []
var start_pos: Vector3i
var end_pos: Vector3i
var path: Array[Vector3i] = []
var rng := RandomNumberGenerator.new()
var _last_visited: Dictionary = {}
var flipping: bool = false
var start_transform: Transform3D

# Saved map for reset
var _saved_matrix: Array = []
var _saved_start_pos: Vector3i
var _saved_end_pos: Vector3i
var _saved_path: Array[Vector3i] = []
var _map_saved: bool = false

# Wall blocks under WALLS node, for cutaway visibility
var _wall_blocks: Array[StaticBody3D] = []

signal flip_started
signal flip_finished
signal generation_finished


func _ready() -> void:
	start_transform = global_transform
	rng.randomize()
	if not Engine.is_editor_hint():
		generate()


func get_center_global() -> Vector3:
	return global_position


func cube_half_extent() -> float:
	return float(n - 1) / 2.0


func can_flip() -> bool:
	return not flipping


# ── Generation ──────────────────────────────────────────────────

func generate() -> void:
	_clear_generated()
	rng.randomize()

	var ok := false
	for _i in range(300):
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

	_saved_matrix = matrix.duplicate(true)
	_saved_start_pos = start_pos
	_saved_end_pos = end_pos
	_saved_path = path.duplicate()
	_map_saved = true

	_build_walls()
	_build_exit()
	_place_player_at()
	_generation_finished()


func _generation_finished() -> void:
	# Wait one frame for scene tree to settle, then emit.
	await get_tree().process_frame
	update_cutaway_visibility()
	generation_finished.emit()


func restore_saved_map() -> void:
	if not _map_saved:
		generate()
		return

	# 先重置魔方旋转状态，避免墙壁/终点位置偏移
	global_transform = start_transform

	_clear_generated()

	matrix = _saved_matrix.duplicate(true)
	start_pos = _saved_start_pos
	end_pos = _saved_end_pos
	path = _saved_path.duplicate()

	_build_walls()
	_build_exit()
	_place_player_at()

	update_cutaway_visibility()
	generation_finished.emit()


func reset_to_start() -> void:
	restore_saved_map()


func _clear_generated() -> void:
	# Clear wall blocks
	var walls := get_node_or_null("WALLS")
	if walls != null:
		for child in walls.get_children():
			child.queue_free()
	_wall_blocks.clear()

	# Clear ALL exit areas（用 find_children 而非 get_node_or_null，
	# 防止 queue_free 延迟导致旧节点仍在树中时只找到第一个）
	for child in find_children("StaticBox_EXIT", "Area3D", true, false):
		remove_child(child)
		child.queue_free()


# ── Matrix & path-finding ───────────────────────────────────────

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


func _is_on_surface(x: int, y: int, z: int) -> bool:
	return x == 0 or x == n - 1 or y == 0 or y == n - 1 or z == 0 or z == n - 1


func _pick_start_end() -> bool:
	var cells: Array[Vector3i] = []
	for x in range(n):
		for y in range(n):
			for z in range(n):
				if _is_on_surface(x, y, z):
					cells.append(Vector3i(x, y, z))
	if cells.size() < 2:
		return false

	# Prefer start on bottom face (y == 0)
	var bottom_cells: Array[Vector3i] = []
	for r in cells:
		if r.y == 0:
			bottom_cells.append(r)
	if not bottom_cells.is_empty():
		start_pos = bottom_cells[rng.randi_range(0, bottom_cells.size() - 1)]
	else:
		start_pos = cells[rng.randi_range(0, cells.size() - 1)]

	var cand: Array[Vector3i] = []
	for c in cells:
		if c != start_pos and max(abs(c.x - start_pos.x), max(abs(c.y - start_pos.y), abs(c.z - start_pos.z))) > 2:
			cand.append(c)
	if cand.is_empty():
		cand = cells.duplicate()
		cand.erase(start_pos)
	end_pos = cand[rng.randi_range(0, cand.size() - 1)]
	return true


func _generate_surface() -> void:
	for x in range(n):
		for y in range(n):
			for z in range(n):
				if not _is_on_surface(x, y, z):
					continue
				var p := Vector3i(x, y, z)
				if p == start_pos or p == end_pos:
					matrix[x][y][z] = 0
				else:
					matrix[x][y][z] = rng.randi_range(0, 1)


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
			var q: Vector3i = c + d
			if q.x >= 0 and q.y >= 0 and q.z >= 0 and q.x < n and q.y < n and q.z < n:
				if _is_on_surface(q.x, q.y, q.z) and matrix[q.x][q.y][q.z] == 1 and not list.has(q):
					list.append(q)
	if list.is_empty():
		return
	var w := list[rng.randi_range(0, list.size() - 1)]
	matrix[w.x][w.y][w.z] = 0


func _wp(x: int, y: int, z: int) -> Vector3:
	var o := -(n - 1) / 2.0
	return Vector3(x + o, float(y) + 0.5, z + o)


func _surface_normal(p: Vector3i) -> Vector3:
	if p.x == 0:       return Vector3.LEFT
	if p.x == n - 1:   return Vector3.RIGHT
	if p.y == 0:       return Vector3.DOWN
	if p.y == n - 1:   return Vector3.UP
	if p.z == 0:       return Vector3.FORWARD
	return Vector3.BACK


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


# ── Building ─────────────────────────────────────────────────────

func _build_walls() -> void:
	var walls := get_node_or_null("WALLS")
	if walls == null:
		return

	var mesh := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.55)

	for x in range(n):
		for y in range(n):
			for z in range(n):
				if matrix[x][y][z] == 1:
					var body := StaticBody3D.new()
					body.name = "Wall%d_%d_%d" % [x, y, z]

					var col := CollisionShape3D.new()
					var shape := BoxShape3D.new()
					shape.size = Vector3(1, 1, 1)
					col.shape = shape
					body.add_child(col)

					var vis := MeshInstance3D.new()
					vis.mesh = mesh
					vis.material_override = mat
					body.add_child(vis)

					body.position = _wp(x, y, z)
					walls.add_child(body)
					_wall_blocks.append(body)


func _build_exit() -> void:
	# 彻底清除所有旧终点（queue_free 是延迟的，必须立即 remove_child）
	for child in find_children("StaticBox_EXIT", "Area3D", true, false):
		remove_child(child)
		child.queue_free()

	var exit_area := Area3D.new()
	exit_area.name = "StaticBox_EXIT"

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 1, 1)
	col.shape = shape
	exit_area.add_child(col)

	var outward := _surface_normal(end_pos)
	# 终点碰撞体放在格子中心，1x1x1 占满整个立方格
	var pos := _wp(end_pos.x, end_pos.y, end_pos.z)

	var rot := Quaternion(Vector3.DOWN, outward)
	exit_area.transform = Transform3D(Basis(rot), pos)

	# 断开旧连接再重新连接，防止 generate/restore 多次调用时重复绑定导致信号失效
	if exit_area.body_entered.is_connected(_on_exit_body_entered):
		exit_area.body_entered.disconnect(_on_exit_body_entered)
	exit_area.body_entered.connect(_on_exit_body_entered)
	add_child(exit_area)


func _place_player_at() -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	if player == null:
		return

	var world_pos := to_global(_wp(start_pos.x, start_pos.y, start_pos.z))
	world_pos.y = 0.55

	var player_scale := player.scale
	var xform := Transform3D(Basis.IDENTITY, world_pos).scaled(player_scale)
	if player.has_method("set_start_transform"):
		player.set_start_transform(xform)
	player.global_transform = xform
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO


# ── Exit signal ──────────────────────────────────────────────────

func _on_exit_body_entered(body: Node) -> void:
	if body.name != "Player":
		return
	var ui := get_parent().get_node_or_null("ui_ingame")
	if ui != null and ui.has_method("_on_exit_body_entered"):
		ui._on_exit_body_entered(body)


# ── Rotation ─────────────────────────────────────────────────────

func request_flip(collision_normal: Vector3, player: Node3D) -> bool:
	if flipping:
		return false

	var outward := _snap_to_axis(-collision_normal)
	if outward.dot(Vector3.DOWN) > 0.99:
		return false

	var rotation_quat := Quaternion(outward, Vector3.DOWN)
	if rotation_quat.get_angle() < 0.01:
		return false

	_animate_flip(rotation_quat, player)
	return true


func request_rotate_left(player: Node3D) -> bool:
	if flipping or player == null:
		return false
	var rotation_quat := Quaternion(Vector3.UP, -PI / 2.0)
	_animate_flip(rotation_quat, player, true)
	return true


func request_rotate_right(player: Node3D) -> bool:
	if flipping or player == null:
		return false
	var rotation_quat := Quaternion(Vector3.UP, PI / 2.0)
	_animate_flip(rotation_quat, player, true)
	return true


func _on_left_pressed() -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	request_rotate_left(player)


func _on_right_pressed() -> void:
	var player := get_parent().get_node_or_null("Player") as Node3D
	request_rotate_right(player)


func _snap_to_axis(v: Vector3) -> Vector3:
	var a := v.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector3(signf(v.x), 0.0, 0.0)
	if a.y >= a.z:
		return Vector3(0.0, signf(v.y), 0.0)
	return Vector3(0.0, 0.0, signf(v.z))


func _rotated_xform(xform: Transform3D, center: Vector3, q: Quaternion) -> Transform3D:
	return Transform3D(Basis(q) * xform.basis, center + q * (xform.origin - center))


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
	var facing: Vector3 = rot * facing_start
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = rot * Vector3.UP
		facing.y = 0.0
	if facing.length_squared() < 0.0001:
		facing = Vector3(0.0, 0.0, -1.0)
	else:
		facing = facing.normalized()

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

	player.set_physics_process(true)
	update_cutaway_visibility()
	flipping = false
	flip_finished.emit()


# ── Cutaway visibility ───────────────────────────────────────────

func update_cutaway_visibility() -> void:
	var cam := _get_camera()
	if cam == null:
		return

	var center := get_center_global()
	var to_camera: Vector3 = (cam.global_position - center).normalized()
	var scores: Array[Dictionary] = []

	for body in _wall_blocks:
		if body == null or not is_instance_valid(body):
			continue
		# The outward direction from cube center to this wall block
		var dir := (body.global_position - center).normalized()
		if dir.length_squared() < 0.0001:
			continue
		var score := dir.dot(to_camera)  # >0 means block faces camera
		scores.append({"body": body, "score": score})

	# Sort by score descending (most camera-facing first)
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])

	# Hide blocks that strongly face the camera
	for entry in scores:
		var body := entry["body"] as StaticBody3D
		if body == null or not is_instance_valid(body):
			continue
		var show := entry["score"] < wall_visible_dot
		body.visible = show
		var col := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col != null:
			col.disabled = not show


func _get_camera() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam
	# Try to find camera as sibling
	var host := get_parent()
	if host != null:
		cam = host.find_child("Camera3D", true, false) as Camera3D
	return cam

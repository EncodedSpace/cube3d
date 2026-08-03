extends StaticBody3D

## StaticBox_E1：仅 MovableBox 可进入并与之重叠；重叠后 E1 消失，只留箱子，并打开 E2。
## 玩家不能进入 E1（翻滚障碍仍挡人）。


## 玩家永远不能进入此格。
var allows_player_enter := false

@export var e2_path: NodePath = ^"../StaticBox_E2"
@export var movable_name_filter := "MovableBox"

var _unlocked := false
var _held_box: RigidBody3D
var _area: Area3D
## 重叠锁定后 E1 本体隐藏；裁切也不再显示。
var _consumed := false


func _ready() -> void:
	# 无固体碰撞，箱子可推进来与 E1 重叠。
	collision_layer = 0
	collision_mask = 0
	_set_own_solid_disabled(true)

	_area = Area3D.new()
	_area.name = "MovableDetect"
	_area.collision_layer = 0
	_area.collision_mask = 1
	_area.monitoring = true
	_area.monitorable = false

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# 略大于 1，避免贴格边缘测不到。
	box.size = Vector3(1.05, 1.05, 1.05)
	col.shape = box
	_area.add_child(col)
	add_child(_area)

	_area.body_entered.connect(_on_body_entered)
	set_physics_process(true)
	call_deferred("_check_overlaps")


func _physics_process(_delta: float) -> void:
	if _unlocked:
		_keep_held_box_overlap()
		return
	_check_overlaps()


func apply_cutaway_visibility(wall_visible: bool) -> void:
	collision_layer = 0
	collision_mask = 0
	_set_own_solid_disabled(true)
	if _consumed:
		# 已与箱子重叠：E1 永远隐藏，只保留锁定逻辑。
		visible = false
		_keep_held_box_overlap()
		return
	visible = wall_visible
	if _area != null:
		for child in _area.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not wall_visible
	_keep_held_box_overlap()


func _check_overlaps() -> void:
	if _unlocked or _area == null:
		return
	for body in _area.get_overlapping_bodies():
		if _is_movable(body):
			_on_movable_entered(body as RigidBody3D)
			return


func _on_body_entered(body: Node3D) -> void:
	if _unlocked:
		return
	if not _is_movable(body):
		return
	_on_movable_entered(body as RigidBody3D)


func _is_movable(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	return body is RigidBody3D and movable_name_filter in String(body.name)


func _on_movable_entered(box: RigidBody3D) -> void:
	if _unlocked or box == null:
		return
	_unlocked = true
	_hold_box(box)
	_consume_e1()

	var e2 := get_node_or_null(e2_path)
	if e2 != null and e2.has_method("unlock_for_player"):
		e2.unlock_for_player()
	else:
		push_warning("StaticBox_E1: 找不到 E2（%s）" % String(e2_path))


## 箱子与 E1 重合锁定，叠在同一格。
func _hold_box(box: RigidBody3D) -> void:
	_held_box = box
	box.set_meta("locked_in_e1", true)
	box.global_transform = global_transform
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	box.freeze = true
	box.sleeping = true


## E1 视觉消失，该格只剩 MovableBox。
func _consume_e1() -> void:
	_consumed = true
	visible = false
	collision_layer = 0
	collision_mask = 0
	_set_own_solid_disabled(true)
	if _area != null:
		_area.monitoring = false
		for child in _area.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = true


func _keep_held_box_overlap() -> void:
	if _held_box == null or not is_instance_valid(_held_box):
		return
	_held_box.global_transform = global_transform
	_held_box.linear_velocity = Vector3.ZERO
	_held_box.angular_velocity = Vector3.ZERO
	_held_box.freeze = true


func _set_own_solid_disabled(disabled: bool) -> void:
	for child in get_children():
		# 不要关掉 Area 下的检测形状。
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = disabled

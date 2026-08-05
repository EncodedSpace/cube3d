extends StaticBody3D

## StaticBox_E1：仅 MovableBox 可进入并与之重叠；重叠后 E1 消失并打开 E2。
## lock_movable_on_overlap=true（默认）：箱子锁定在 E1 格。
## lock_movable_on_overlap=false：箱子保持可移动（如 level3）。
## 玩家不能进入 E1（翻滚障碍仍挡人）。
## 激活需箱子中心足够靠近且速度足够慢，避免半空「磁吸」。


## 玩家永远不能进入此格。
var allows_player_enter := false

@export var e2_path: NodePath = ^"../StaticBox_E2"
@export var movable_name_filter := "MovableBox"
## 重叠后是否把 MovableBox 锁死在 E1 位置。
@export var lock_movable_on_overlap := true
## 水平方向中心距上限（米）。
@export var overlap_lateral_max := 0.35
## 竖直方向中心距上限（米）。
@export var overlap_vertical_max := 0.35
## 速度上限；仍在快速下落/滑入时不激活。
@export var overlap_speed_max := 1.2

var _unlocked := false
var _held_box: RigidBody3D
var _area: Area3D
## 重叠后 E1 本体隐藏；裁切也不再显示。
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
	# 略大于 1，用于粗检测；真正激活看 _is_settled_on_e1。
	box.size = Vector3(1.05, 1.05, 1.05)
	col.shape = box
	_area.add_child(col)
	add_child(_area)

	set_physics_process(true)
	call_deferred("_check_overlaps")


func _physics_process(_delta: float) -> void:
	if _unlocked:
		if lock_movable_on_overlap:
			_keep_held_box_overlap()
		return
	_check_overlaps()


func apply_cutaway_visibility(wall_visible: bool) -> void:
	collision_layer = 0
	collision_mask = 0
	_set_own_solid_disabled(true)
	if _consumed:
		# 已触发：E1 永远隐藏。
		visible = false
		if lock_movable_on_overlap:
			_keep_held_box_overlap()
		return
	visible = wall_visible
	if _area != null:
		for child in _area.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = not wall_visible
	if lock_movable_on_overlap:
		_keep_held_box_overlap()


func _check_overlaps() -> void:
	if _unlocked or _area == null:
		return
	for body in _area.get_overlapping_bodies():
		if not _is_movable(body):
			continue
		var box := body as RigidBody3D
		if _is_settled_on_e1(box):
			_on_movable_entered(box)
			return


## 箱子中心已贴近 E1 且基本停稳，才算真正重叠（避免半空触发）。
func _is_settled_on_e1(box: RigidBody3D) -> bool:
	if box == null or not is_instance_valid(box):
		return false
	var offset := box.global_position - global_position
	var along_up := offset.dot(Vector3.UP)
	var lateral := offset - Vector3.UP * along_up
	if lateral.length() > overlap_lateral_max:
		return false
	if absf(along_up) > overlap_vertical_max:
		return false
	if box.linear_velocity.length() > overlap_speed_max:
		return false
	return true


func _is_movable(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	return body is RigidBody3D and movable_name_filter in String(body.name)


func _on_movable_entered(box: RigidBody3D) -> void:
	if _unlocked or box == null:
		return
	_unlocked = true
	if lock_movable_on_overlap:
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


## E1 视觉消失。
func _consume_e1() -> void:
	_consumed = true
	visible = false
	collision_layer = 0
	collision_mask = 0
	_set_own_solid_disabled(true)
	# E1 已消失：不再当翻滚障碍（箱子若仍在该格会单独挡人）。
	allows_player_enter = true
	if _area != null:
		_area.monitoring = false
		for child in _area.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = true
	if not lock_movable_on_overlap:
		set_physics_process(false)


func _keep_held_box_overlap() -> void:
	if not lock_movable_on_overlap:
		return
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

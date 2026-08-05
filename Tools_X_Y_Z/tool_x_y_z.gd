@tool
extends Node3D

## X/Y/Z 道具组：
## - Tool_X：金色小圆球钥匙（收集后消失）
## - Tool_Y：始终可通行；收集 X 后变为跳板，站在上面可按空格跳跃
## - Tool_Z：默认在 Y 上方一格；跳跃撞到后消失，玩家落回 Y
## 节点名含 Tool_X/Y/Z，随附着墙面裁切显隐。
## 统一等距多面绑定：绑定面中任一面亮起即可见。
## @tool：编辑器里改导出位置会实时同步到子节点。


@export var x_position := Vector3(0.0, 0.5, 0.0)
@export var y_position := Vector3(1.5, 0.5, 0.0)
## 若开启，Z 始终放在 Y 正上方一格（忽略 z_position）。
@export var auto_place_z_above_y := true
@export var z_position := Vector3(1.5, 1.5, 0.0)
@export var launch_height := 1.0

signal player_entered_y(player: Node3D)
signal player_exited_y(player: Node3D)
signal x_collected
signal pad_activated
signal z_broken


@onready var x_key: Area3D = $Tool_X
@onready var y_zone: Area3D = $Tool_Y
@onready var z_box: StaticBody3D = $Tool_Z

var _x_collected := false
var _pad_active := false
var _z_broken := false
var _player_on_y: Node3D
## 进入 Y 前玩家是否已有跳跃权限，离开时据此恢复。
var _jump_was_enabled := false
var _z_hit_area: Area3D


func _ready() -> void:
	_apply_positions()
	_refresh_y_look()
	if Engine.is_editor_hint():
		set_process(true)
		return

	_setup_x()
	_setup_y()
	_setup_z_hit()
	set_physics_process(true)
	set_process(false)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_positions()
		_refresh_y_look()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _z_broken or not _pad_active:
		return
	if z_box == null or not is_instance_valid(z_box):
		return
	# 跳起接近 Z 时立刻撞碎，避免卡在 Z 顶面。
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not _is_player_jumping_up(player):
		return
	if player.global_position.distance_to(z_box.global_position) <= 0.95:
		_break_z()


func _apply_positions() -> void:
	if x_key:
		x_key.position = x_position
	if y_zone:
		y_zone.position = y_position
	if z_box:
		if auto_place_z_above_y:
			z_box.position = y_position + Vector3.UP * launch_height
		else:
			z_box.position = z_position


func _setup_x() -> void:
	if x_key == null:
		return
	x_key.monitoring = true
	x_key.monitorable = false
	x_key.collision_layer = 0
	x_key.collision_mask = 1
	if not x_key.body_entered.is_connected(_on_x_body_entered):
		x_key.body_entered.connect(_on_x_body_entered)
	call_deferred("_check_x_initial_overlaps")


func _setup_y() -> void:
	if y_zone == null:
		return
	# Y 始终只是检测区，不挡人。
	y_zone.monitoring = true
	y_zone.monitorable = false
	y_zone.collision_layer = 0
	y_zone.collision_mask = 1
	if not y_zone.body_entered.is_connected(_on_y_body_entered):
		y_zone.body_entered.connect(_on_y_body_entered)
	if not y_zone.body_exited.is_connected(_on_y_body_exited):
		y_zone.body_exited.connect(_on_y_body_exited)
	call_deferred("_check_y_initial_overlaps")


func _setup_z_hit() -> void:
	if z_box == null:
		return
	_z_hit_area = Area3D.new()
	_z_hit_area.name = "HitDetect"
	_z_hit_area.collision_layer = 0
	_z_hit_area.collision_mask = 1
	_z_hit_area.monitoring = true
	_z_hit_area.monitorable = false
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# 略大于 Z，并略向下延伸，跳起时更容易先检测到再碎裂。
	shape.size = Vector3(1.15, 1.35, 1.15)
	col.shape = shape
	_z_hit_area.position = Vector3(0.0, -0.15, 0.0)
	_z_hit_area.add_child(col)
	z_box.add_child(_z_hit_area)
	_z_hit_area.body_entered.connect(_on_z_hit_body_entered)


func _check_x_initial_overlaps() -> void:
	if _x_collected or x_key == null:
		return
	for body in x_key.get_overlapping_bodies():
		if body.is_in_group("player"):
			_collect_x()
			return


func _check_y_initial_overlaps() -> void:
	if y_zone == null:
		return
	for body in y_zone.get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_y_body_entered(body)
			return


func _on_x_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_collect_x()


func _on_y_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_entered_y.emit(body)
	_player_on_y = body
	if _pad_active:
		_grant_jump(body)


func _on_y_body_exited(body: Node3D) -> void:
	if body == null or body != _player_on_y:
		return
	player_exited_y.emit(body)
	_player_on_y = null
	# 起跳离区后不立刻收回权限，等跳跃结束后再清（避免打断空中跳跃）。
	_revoke_jump_when_idle(body)


func _revoke_jump_when_idle(player: Node3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	while is_instance_valid(player) and _is_player_jumping_up(player):
		await get_tree().physics_frame
	# 若已回到 Y，保持跳跃权限。
	if _player_on_y == player:
		return
	_revoke_jump(player)


func _on_z_hit_body_entered(body: Node3D) -> void:
	if _z_broken or not _pad_active:
		return
	if not body.is_in_group("player"):
		return
	if not _is_player_jumping_up(body):
		return
	_break_z()


func _is_player_jumping_up(body: Node3D) -> bool:
	if not (body is CharacterBody3D):
		return false
	var p := body as CharacterBody3D
	if p.velocity.y > 0.05:
		return true
	if "jump_controller" in p and p.jump_controller != null:
		if bool(p.jump_controller.get("active")) or bool(p.jump_controller.get("preparing")):
			return true
	return false


func _collect_x() -> void:
	if _x_collected:
		return
	_x_collected = true
	x_collected.emit()
	if x_key != null and is_instance_valid(x_key):
		x_key.queue_free()
		x_key = null
	_activate_pad()
	# 若玩家已站在 Y 上，立刻给予跳跃权限。
	if _player_on_y != null and is_instance_valid(_player_on_y):
		_grant_jump(_player_on_y)


func _activate_pad() -> void:
	if _pad_active:
		return
	_pad_active = true
	_refresh_y_look()
	pad_activated.emit()


func _grant_jump(player: Node3D) -> void:
	if player == null or not player.has_method("set_jump_enabled"):
		return
	if player.has_method("is_jump_enabled"):
		_jump_was_enabled = bool(player.is_jump_enabled())
	else:
		_jump_was_enabled = false
	player.set_jump_enabled(true)


func _revoke_jump(player: Node3D) -> void:
	if player == null or not player.has_method("set_jump_enabled"):
		return
	# 本关原本就不能跳时，离开 Y 收回权限。
	if not _jump_was_enabled:
		player.set_jump_enabled(false)


func _break_z() -> void:
	if _z_broken:
		return
	_z_broken = true
	z_broken.emit()
	if z_box != null and is_instance_valid(z_box):
		z_box.queue_free()
		z_box = null
		_z_hit_area = null


func _refresh_y_look() -> void:
	if y_zone == null or not is_instance_valid(y_zone):
		return
	var mi := y_zone.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _pad_active:
		# 激活：亮橙跳板感（仍可通行）。
		mat.albedo_color = Color(1.0, 0.55, 0.15, 0.45)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.1, 1.0)
		mat.emission_energy_multiplier = 1.8
	else:
		# 未激活：淡蓝可通行区。
		mat.albedo_color = Color(0.35, 0.75, 1.0, 0.28)
		mat.emission_enabled = true
		mat.emission = Color(0.25, 0.65, 1.0, 1.0)
		mat.emission_energy_multiplier = 0.8
	mi.material_override = mat

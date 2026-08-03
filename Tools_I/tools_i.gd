@tool
extends Node3D

## 一对 1×1×1 传送门 + 一枚直径 0.9 的钥匙球。
## 玩家先吃掉钥匙，传送门才可传送；传送后以出口门所附着墙面为新地板。
## 节点名含 Portal，会随附着墙面一起裁切显隐。


@export var portal_a_position := Vector3(-1.5, 0.5, -1.5)
@export var portal_b_position := Vector3(1.5, 0.5, 1.5)
@export var key_position := Vector3(0.0, 0.45, 0.0)

## 传送后短时间内禁止再次触发，避免来回弹射。
@export var teleport_cooldown := 0.45


@onready var portal_a: Area3D = $Portal_A
@onready var portal_b: Area3D = $Portal_B
@onready var portal_key: Area3D = $Portal_Key

var _cooldown_left := 0.0
var portals_unlocked := false


func _ready() -> void:
	_apply_positions()
	if Engine.is_editor_hint():
		return

	if portal_a:
		portal_a.setup(self, portal_b)
	if portal_b:
		portal_b.setup(self, portal_a)
	if portal_key and portal_key.has_method("setup"):
		portal_key.setup(self)

	_refresh_portal_look()
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_positions()
		return

	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


func _apply_positions() -> void:
	if portal_a:
		portal_a.position = portal_a_position
	if portal_b:
		portal_b.position = portal_b_position
	if portal_key:
		portal_key.position = key_position


func unlock_portals() -> void:
	if portals_unlocked:
		return
	portals_unlocked = true
	_refresh_portal_look()


func can_teleport() -> bool:
	return portals_unlocked and _cooldown_left <= 0.0


func begin_cooldown(extra: float = 0.0) -> void:
	_cooldown_left = maxf(teleport_cooldown, extra)


func teleport_player(player: Node3D, exit_portal: Area3D) -> void:
	if player == null or exit_portal == null:
		return
	if not can_teleport():
		return

	var cube := _find_cube_world()
	if cube != null and bool(cube.get("flipping")):
		return

	# 中断翻滚 / 跳跃，避免传送后状态错乱。
	if "jump_controller" in player and player.jump_controller:
		if player.jump_controller.has_method("cancel"):
			player.jump_controller.cancel()
	if "roll_controller" in player and player.roll_controller:
		if player.roll_controller.has_method("cancel"):
			player.roll_controller.cancel()

	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO

	# 先落到出口门，再把该门附着墙翻成地板（玩家随立方体一起转）。
	player.global_position = exit_portal.global_position

	var flipped := false
	var wall := _pick_wall_to_become_floor(cube, exit_portal)
	if wall != null and cube != null and cube.has_method("request_orient_wall_as_floor"):
		flipped = bool(cube.request_orient_wall_as_floor(wall, player))

	var extra := 0.0
	if flipped and cube != null:
		extra = float(cube.get("flip_duration")) + 0.15
	begin_cooldown(extra)


func _refresh_portal_look() -> void:
	if portal_a and portal_a.has_method("set_active_look"):
		portal_a.set_active_look(portals_unlocked)
	if portal_b and portal_b.has_method("set_active_look"):
		portal_b.set_active_look(portals_unlocked)


func _find_cube_world() -> Node:
	var n: Node = self
	while n != null:
		if n.has_method("request_orient_wall_as_floor"):
			return n
		n = n.get_parent()
	return null


## 出口门附着的墙中，优先选尚未是地板的立面（交界时偏向侧墙）。
func _pick_wall_to_become_floor(cube: Node, exit_portal: Node3D) -> Node3D:
	if cube == null or exit_portal == null:
		return null
	if not cube.has_method("get_nearest_walls_for"):
		return null

	var bound: Array = cube.get_nearest_walls_for(exit_portal)
	var best: Node3D = null
	var best_score := -INF

	for item in bound:
		var wall := item as Node3D
		if wall == null:
			continue
		var outward := -wall.global_transform.basis.y.normalized()
		# 已经是地板 → 无需翻转。
		if outward.y < -0.7:
			continue
		var score := -exit_portal.global_position.distance_squared_to(wall.global_position)
		# 侧墙优先于天花板，落地后更像「以墙为地板」。
		if absf(outward.y) < 0.35:
			score += 10.0
		if score > best_score:
			best_score = score
			best = wall

	return best

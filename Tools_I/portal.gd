extends Area3D

## 单扇传送门：
## - 每种视觉元素都可以在检查器中设置是否始终可见
## - 未勾选“始终可见”的元素，只会在传送门激活后出现
## - 玩家进入后，由 ToolsI 负责传送到配对门


@export_category("传送门元素可见性")

## 勾选后，未激活时也显示门框。
@export var frame_always_visible: bool = true

## 勾选后，未激活时也显示黑色核心。
@export var core_always_visible: bool = false

## 勾选后，未激活时也显示并播放粒子。
@export var particles_always_visible: bool = false

## 勾选后，未激活时也显示四边光束。
@export var beams_always_visible: bool = false


var tools_root: Node3D
var exit_portal: Area3D


@onready var frame_root: Node3D = get_node_or_null(
	"PortalVisual/Frame"
) as Node3D

@onready var black_hole: Node3D = get_node_or_null(
	"PortalVisual/BlackHole"
) as Node3D

@onready var black_core: MeshInstance3D = get_node_or_null(
	"PortalVisual/BlackHole/BlackCore"
) as MeshInstance3D

@onready var particle_layer: GPUParticles3D = get_node_or_null(
	"PortalVisual/BlackHole/ParticleLayer"
) as GPUParticles3D

@onready var edge_beams: Node3D = get_node_or_null(
	"PortalVisual/BlackHole/EdgeBeams"
) as Node3D


func setup(root: Node3D, other: Area3D) -> void:
	tools_root = root
	exit_portal = other

	monitoring = true
	monitorable = false

	# 检测默认碰撞层上的 Player。
	collision_layer = 0
	collision_mask = 1

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## 由 cube_world 调用，使传送门跟随所在墙面显隐。
func apply_cutaway_visibility(wall_visible: bool) -> void:
	visible = wall_visible
	monitoring = wall_visible

	for child in get_children():
		if child is CollisionShape3D:
			var shape := child as CollisionShape3D
			shape.set_deferred("disabled", not wall_visible)


## 切换传送门激活状态。
func set_active_look(active: bool) -> void:
	# BlackHole 是 Core、粒子和光束的共同父节点。
	# 父节点必须保持显示，具体显隐由各子节点控制。
	if black_hole != null:
		black_hole.visible = true

	# 门框：始终可见，或激活后可见。
	if frame_root != null:
		frame_root.visible = frame_always_visible or active

	# 黑色核心：始终可见，或激活后可见。
	if black_core != null:
		black_core.visible = core_always_visible or active

	# 粒子：始终播放，或激活后播放。
	if particle_layer != null:
		var particles_should_show := particles_always_visible or active
		var was_emitting := particle_layer.emitting

		particle_layer.visible = particles_should_show
		particle_layer.emitting = particles_should_show

		# 仅在粒子从关闭变为开启时重新启动，
		# 避免重复刷新状态时不断重置粒子。
		if particles_should_show and not was_emitting:
			particle_layer.restart()

	# 四边向外光束：始终可见，或激活后可见。
	if edge_beams != null:
		edge_beams.visible = beams_always_visible or active


func _on_body_entered(body: Node3D) -> void:
	if tools_root == null or exit_portal == null:
		return

	if not body.is_in_group("player"):
		return

	if not tools_root.has_method("teleport_player"):
		return

	tools_root.teleport_player(body, exit_portal)

extends Node3D

## Flat screen-covering backdrop (cover mode: no stretch, crop overflow).
## Kept behind gameplay: distance is at least past the scene center.
@export var bg_distance: float = 60.0
@export var bg_behind_margin: float = 80.0
@export var bg_brightness: float = 1.0
@export var scene_center: Vector3 = Vector3(0, 3, -20)

@onready var bg_space: MeshInstance3D = $BG_Space
@onready var title_showed := false

var _bg_mesh: QuadMesh
var _tex_aspect: float = 16.0 / 9.0


func _ready() -> void:
	$CanvasLayer/CenterContainer/Title.visible = false
	_setup_bg()
	var exit_btn := get_node_or_null("CanvasLayer/Button") as Button
	if exit_btn != null:
		SciFiButtonStyle.apply(exit_btn, 22)


func _process(_delta: float) -> void:
	_update_bg_cover()


func _setup_bg() -> void:
	if bg_space == null:
		return

	_bg_mesh = bg_space.mesh as QuadMesh
	if _bg_mesh == null:
		_bg_mesh = QuadMesh.new()
		bg_space.mesh = _bg_mesh

	var mat := bg_space.get_active_material(0) as ShaderMaterial
	if mat != null:
		var tex := mat.get_shader_parameter("bg_texture") as Texture2D
		if tex != null and tex.get_height() > 0:
			_tex_aspect = float(tex.get_width()) / float(tex.get_height())

	bg_space.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bg_space.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _update_bg_cover() -> void:
	if bg_space == null or _bg_mesh == null:
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var forward := -cam.global_transform.basis.z
	var up := cam.global_transform.basis.y

	# Always sit behind the playable space (critical during ortho cube-close cam).
	var depth_to_center := (scene_center - cam.global_position).dot(forward)
	var dist := maxf(bg_distance, depth_to_center + bg_behind_margin)

	var view_aspect := get_viewport().get_visible_rect().size.aspect()
	if view_aspect <= 0.001:
		view_aspect = 16.0 / 9.0

	var frustum_h: float
	var frustum_w: float
	if cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var half_fov := deg_to_rad(cam.fov) * 0.5
		frustum_h = 2.0 * dist * tan(half_fov)
		frustum_w = frustum_h * view_aspect
	else:
		# Orthographic frustum size is constant with distance.
		frustum_h = cam.size
		frustum_w = frustum_h * view_aspect

	# Cover: keep texture aspect, enlarge until frustum is fully covered.
	var quad_w: float
	var quad_h: float
	if _tex_aspect >= view_aspect:
		quad_h = frustum_h
		quad_w = frustum_h * _tex_aspect
	else:
		quad_w = frustum_w
		quad_h = frustum_w / _tex_aspect

	_bg_mesh.size = Vector2(quad_w, quad_h)

	bg_space.global_position = cam.global_position + forward * dist
	bg_space.look_at(cam.global_position, up)
	bg_space.rotate_object_local(Vector3.UP, PI)

	var mat := bg_space.get_active_material(0) as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("brightness", bg_brightness)


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu/control.tscn")


func _on_area_3d_body_entered(_body: Node3D) -> void:
	if title_showed == false:
		$CanvasLayer/CenterContainer/Title.visible = !$CanvasLayer/CenterContainer/Title.visible
		title_showed = true
		await get_tree().create_timer(1.5).timeout
		$CanvasLayer/CenterContainer/Title.visible = !$CanvasLayer/CenterContainer/Title.visible

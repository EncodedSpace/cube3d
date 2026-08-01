extends Node3D

@onready var env: WorldEnvironment = $WorldEnvironment

var sky_material: ShaderMaterial
var travel_distance := 0.0
var last_position := Vector3.ZERO
@onready var title_showed := false

func _ready():
	$CanvasLayer/CenterContainer/Title.visible = false
	
	sky_material = env.environment.sky.sky_material

	var cam := get_viewport().get_camera_3d()
	if cam:
		last_position = cam.global_position
	
	
func _process(delta):
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	
	travel_distance += cam.global_position.distance_to(last_position)
	last_position = cam.global_position

	sky_material.set_shader_parameter("travel_distance", travel_distance)


func _on_button_pressed() -> void:
	get_tree().quit()


func _on_area_3d_body_entered(body: Node3D) -> void:
	if title_showed == false:
		$CanvasLayer/CenterContainer/Title.visible = !$CanvasLayer/CenterContainer/Title.visible 
		title_showed = true
		# 使用 SceneTreeTimer
		await get_tree().create_timer(1.5).timeout
		$CanvasLayer/CenterContainer/Title.visible = !$CanvasLayer/CenterContainer/Title.visible
